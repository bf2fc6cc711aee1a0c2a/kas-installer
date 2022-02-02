#!/bin/bash

KUBECTL=$(which kubectl)
DIR_NAME="$(dirname $0)"
source ${DIR_NAME}/kas-installer.env
MK_BASE_URL="https://kas-fleet-manager-kas-fleet-manager-${USER}.apps.${K8S_CLUSTER_DOMAIN}/api/kafkas_mgmt/v1"

OS=$(uname)

if [ "$OS" = 'Darwin' ]; then
  # for MacOS
  BASE64=$(which gbase64)
else
  # for Linux and Windows
  BASE64=$(which base64)
fi

OPERATION='<NONE>'
OPERATION_PATH='/kafkas'
CREATE_NAME='<NONE>'
CREATE_PLAN='standard.x1'
REQUEST_BODY=''
OP_KAFKA_ID='<NONE>'
ACCESS_TOKEN=''
REFRESH_EXPIRED_TOKENS='false'
ADMIN_OPERATION='false'

access_token() {
    local FETCH_TOKEN='false'

    if [ -z "${ACCESS_TOKEN}" ] ; then
        FETCH_TOKEN='true'
    elif [ "${REFRESH_EXPIRED_TOKENS}" = "true" ] ; then
        # Extract expiration from token and compare to current date
        EXP=$(echo "${ACCESS_TOKEN}" | awk -F. '{ printf "%s", $2 }' | ${BASE64} -d 2>/dev/null | jq -r .exp)

        if [ $(date "+%s") -gt ${EXP:-0} ] ; then
            # Current date is after token expiration time, refresh the token
            FETCH_TOKEN='true'
        fi
    fi

    if [ "${FETCH_TOKEN}" = "true" ] ; then
        if [ "${ADMIN_OPERATION}" = "true" ] ; then
            USER=kafka-admin
            PWD=kafka-admin
            REALM=rhoas-kafka-sre
            ACCESS_TOKEN="$(export KEYCLOAK_REALM=${REALM} && ${DIR_NAME}/get_access_token.sh ${USER} ${PWD} 2>/dev/null)"
        else
            USER=owner
            ACCESS_TOKEN="$(${DIR_NAME}/get_access_token.sh --owner 2>/dev/null)"
        fi

        retVal=$?
        if [ ${retVal} -ne 0 ]; then
            echo "Failed to get access token for ${USER}: ${retVal}"
            exit 1
        fi
    fi

    echo "${ACCESS_TOKEN}"
}

create() {
    local KAFKA_NAME=${1}
    local KAFKA_PLAN=${2}

    local RESPONSE=$(curl -sXPOST -H "Authorization: Bearer $(access_token)" ${MK_BASE_URL}${OPERATION_PATH}?async=true \
      -d '{ "region": "'${REGION:-us-east-1}'", "cloud_provider": "aws", "name": "'${KAFKA_NAME}'", "plan": "'${KAFKA_PLAN}'" }')

    local KIND=$(echo ${RESPONSE} | jq -r .kind)

    if [ "${KIND}" = "Error" ]; then
        local REASON=$(echo ${RESPONSE} | jq -r .reason)
        echo "Error creating Kafka instance '${KAFKA_NAME}': ${REASON}"

        local ERRCODE=$(echo ${RESPONSE} | jq -r .code)

        # Display existing service accounts if limit has been reached
        if [ "${ERRCODE}" = "KAFKAS-MGMT-5" ]; then
            echo "Existing Kafka instance(s):"
            list
        fi

        exit 1
    else
        local KAFKA_ID=$(echo ${RESPONSE} | jq -r .id)
        local KAFKA_OWNER=$(echo ${RESPONSE} | jq -r .owner | tr '_' '-')
        local KAFKA_NS="${KAFKA_OWNER}-${KAFKA_ID}"

        local KAFKA_RESOURCE=$(get ${KAFKA_ID})
        local KAFKA_STATUS=$(echo ${KAFKA_RESOURCE} | jq -r .status)

        while [ "${KAFKA_STATUS}" != "ready" ]; do
            echo "Kafka instance '${KAFKA_NAME}' not yet ready: ${KAFKA_STATUS}" >>/dev/stderr
            sleep 10
            KAFKA_RESOURCE=$(get ${KAFKA_ID})
            KAFKA_STATUS=$(echo ${KAFKA_RESOURCE} | jq -r .status)
        done

        echo "Kafka instance '${KAFKA_NAME}' now ready" >>/dev/stderr
        echo ${KAFKA_RESOURCE}
    fi
}

list() {
    local RESPONSE=$(curl -sXGET -H "Authorization: Bearer $(access_token)" ${MK_BASE_URL}${OPERATION_PATH})
    echo ${RESPONSE}
}

get() {
    local KAFKA_ID=${1}
    local RESPONSE=$(curl -sXGET -H "Authorization: Bearer $(access_token)" ${MK_BASE_URL}${OPERATION_PATH}/${KAFKA_ID})

    echo ${RESPONSE}
}

patch() {
    local KAFKA_ID=${1}
    local PATCH_BODY=${2}
    local RESPONSE=$(curl -sXPATCH -H'Content-type: application/json' --data "${PATCH_BODY}" -H "Authorization: Bearer $(access_token)" ${MK_BASE_URL}${OPERATION_PATH}/${KAFKA_ID})

    echo ${RESPONSE}
}

delete() {
    local KAFKA_ID=${1}

    local RESPONSE=$(curl -sXDELETE -H "Authorization: Bearer $(access_token)" -w '\n\n%{http_code}' ${MK_BASE_URL}${OPERATION_PATH}/${KAFKA_ID}?async=true)
    local BODY=$(echo "${RESPONSE}" | head -n 1)
    local CODE=$(echo "${RESPONSE}" | tail -n -1)

    echo "Status code: ${CODE}"

    if [ ${CODE} -ge 400 ] ; then
        # Pretty print
        echo "${BODY}" | jq
    else
        echo "Kafka instance '${KAFKA_ID}' accepted for deletion"
    fi
}

certgen() {
    local KAFKA_ID=${1}
    local SA_CLIENT_ID=${2}
    local SA_CLIENT_SECRET=${3}

    echo "Creating truststore and app-services.properties files for kafka bin script utilization."

    KAFKA_RESOURCE=$(get ${KAFKA_ID})
    KAFKA_USERNAME=$(echo ${KAFKA_RESOURCE} | jq -r .name)
    KAFKA_CERT=$(mktemp)
    KAFKA_INSTANCE_NAMESPACE='kafka-'$(echo ${KAFKA_RESOURCE} | jq -r .id  | tr '[:upper:]' '[:lower:]')
    oc get secret -o yaml ${KAFKA_USERNAME}-cluster-ca-cert -n ${KAFKA_INSTANCE_NAMESPACE} -o json | jq -r '.data."ca.crt"' | base64 --decode  > ${KAFKA_CERT}
    keytool -import -trustcacerts -keystore truststore.jks -storepass password -noprompt -alias mk${KAFKA_ID} -file ${KAFKA_CERT}
    rm ${KAFKA_CERT}

    if [ -z "${SA_CLIENT_ID:-}" ] ; then
        echo "No service account provided, creating new account..."
        SERVICE_ACCOUNT_RESOURCE=$(${DIR_NAME}/service_account.sh --create)

        if [ ${?} -ne 0 ] ; then
            echo "Failed to create a service account!"
            exit 1
        fi

        # MAS SSO (via KFM API) use different properties for client ID/secret than SSO directly. Support both forms here
        SA_CLIENT_ID=$(echo ${SERVICE_ACCOUNT_RESOURCE} | jq -r '.client_id // .clientId')
        SA_CLIENT_SECRET=$(echo ${SERVICE_ACCOUNT_RESOURCE} | jq -r '.client_secret // .secret')
        echo "Service account created: ${SA_CLIENT_ID}"
    fi

    touch app-services.properties
    echo 'security.protocol=SASL_SSL' > app-services.properties
    echo 'sasl.mechanism=PLAIN' >> app-services.properties
    echo 'ssl.truststore.location = '${PWD}'/truststore.jks' >> app-services.properties
    echo 'ssl.truststore.password = password' >> app-services.properties
    echo 'sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="'${SA_CLIENT_ID}'" password="'${SA_CLIENT_SECRET}'";' >> app-services.properties

    echo "Certificate generation complete. Please use app-services.properties as the --command-config flag when using kafka bin scripts."
}

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
    "--admin" )
        OPERATION_PATH='/admin/kafkas'
        ADMIN_OPERATION='true'
        shift
        ;;
    "--create" )
        OPERATION='create'
        CREATE_NAME="${2}"
        shift
        shift
        ;;
    "--plan" )
        CREATE_PLAN="${2}"
        shift
        shift
        ;;
    "--list" )
        OPERATION='list'
        shift
        ;;
    "--get" )
        OPERATION='get'
        OP_KAFKA_ID="${2}"
        shift
        shift
        ;;
    "--patch" )
        OPERATION='patch'
        OP_KAFKA_ID="${2}"
        REQUEST_BODY="${3}"
        shift
        shift
        shift
        ;;
    "--delete" )
        OPERATION='delete'
        OP_KAFKA_ID="${2}"
        shift
        shift
        ;;
    "--certgen" )
        OPERATION='certgen'
        OP_KAFKA_ID="${2}"
        OP_CLIENT_ID="${3}"
        OP_CLIENT_SECRET="${4}"
        shift
        shift
        shift
        shift
        ;;
    "--access-token" )
        ACCESS_TOKEN="${2}"
        shift
        shift
        ;;
    *) # unknown option
        shift
        ;;
    esac
done

if [ "${ADMIN_OPERATION}" = "true" ] && [ "${OPERATION}" = "create" ] ; then
    echo "Parameter '--admin' may not be used with '--create'"
    exit 1
fi


if [ -z "${ACCESS_TOKEN}" ] ; then
    REFRESH_EXPIRED_TOKENS='true'
fi

case "${OPERATION}" in
    "create" )
        create ${CREATE_NAME} "${CREATE_PLAN}"
        ;;
    "list" )
        list
        ;;
    "get" )
        get ${OP_KAFKA_ID}
        ;;
    "patch" )
        patch ${OP_KAFKA_ID} "${REQUEST_BODY}"
        ;;
    "delete" )
        delete ${OP_KAFKA_ID}
        ;;
    "certgen" )
        certgen "${OP_KAFKA_ID}" "${OP_CLIENT_ID}" "${OP_CLIENT_SECRET}"
        ;;
    *)
        echo "Unknown operation '${OPERATION}'";
        exit 1
        ;;
esac
