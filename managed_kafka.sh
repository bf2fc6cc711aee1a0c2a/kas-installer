#!/bin/bash

KUBECTL=$(which kubectl)
DIR_NAME="$(dirname $0)"
source ${DIR_NAME}/kas-installer.env

create() {
    local KAFKA_NAME=${1}

    local RESPONSE=$(curl -sXPOST -H "Authorization: Bearer $(ocm token)" \
      https://kas-fleet-manager-kas-fleet-manager-${USER}.apps.${K8S_CLUSTER_DOMAIN}/api/kafkas_mgmt/v1/kafkas?async=true \
      -d '{ "region": "us-east-1", "cloud_provider": "aws",  "name": "'${KAFKA_NAME}'", "multi_az":true}')

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
    local RESPONSE=$(curl -sXGET -H "Authorization: Bearer $(ocm token)" \
      https://kas-fleet-manager-kas-fleet-manager-${USER}.apps.${K8S_CLUSTER_DOMAIN}/api/kafkas_mgmt/v1/kafkas)
    echo ${RESPONSE}
}

get() {
    local KAFKA_ID=${1}
    local RESPONSE=$(curl -sXGET -H "Authorization: Bearer $(ocm token)" \
      https://kas-fleet-manager-kas-fleet-manager-${USER}.apps.${K8S_CLUSTER_DOMAIN}/api/kafkas_mgmt/v1/kafkas/${KAFKA_ID})

    echo ${RESPONSE}
}

delete() {
    local KAFKA_ID=${1}

    local RESPONSE=$(curl -sXDELETE -H "Authorization: Bearer $(ocm token)" -w '\n\n%{http_code}' \
      https://kas-fleet-manager-kas-fleet-manager-${USER}.apps.${K8S_CLUSTER_DOMAIN}/api/kafkas_mgmt/v1/kafkas/${KAFKA_ID}?async=true)
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

    echo "Creating truststore and app-services.properties files for kafka bin script utilization."

    KAFKA_RESOURCE=$(get ${KAFKA_ID})
    SA_CLIENT_ID=$(echo ${SERVICE_ACCOUNT_RESOURCE} | jq -r .clientID)
    KAFKA_USERNAME=$(echo ${KAFKA_RESOURCE} | jq -r .name)
    KAFKA_CERT=$(mktemp)
    KAFKA_INSTANCE_NAMESPACE=$(echo ${KAFKA_RESOURCE} | jq -r .owner | sed 's/_/-/')'-'$(echo ${KAFKA_RESOURCE} | jq -r .id  | tr '[:upper:]' '[:lower:]')
    oc get secret -o yaml ${KAFKA_USERNAME}-cluster-ca-cert -n ${KAFKA_INSTANCE_NAMESPACE} -o json | jq -r '.data."ca.crt"' | base64 --decode  > ${KAFKA_CERT}
    keytool -import -trustcacerts -keystore truststore.jks -storepass password -noprompt -alias mkinstance -file ${KAFKA_CERT}
    rm ${KAFKA_CERT}
    SERVICE_ACCOUNT_RESOURCE=$(${DIR_NAME}/service_account.sh --create)

    if [ ${?} -ne 0 ] ; then
        echo "Failed to create a service account!"
        exit 1
    fi

    SA_CLIENT_ID=$(echo ${SERVICE_ACCOUNT_RESOURCE} | jq -r .clientID)
    SA_CLIENT_SECRET=$(echo ${SERVICE_ACCOUNT_RESOURCE} | jq -r .clientSecret)

    touch app-services.properties
    echo 'security.protocol=SASL_SSL' > app-services.properties
    echo 'sasl.mechanism=PLAIN' >> app-services.properties
    echo 'ssl.truststore.location = '${PWD}'/truststore.jks' >> app-services.properties
    echo 'ssl.truststore.password = password' >> app-services.properties
    echo 'sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="'${SA_CLIENT_ID}'" password="'${SA_CLIENT_SECRET}'";' >> app-services.properties

    echo "Certificate generation complete. Please use app-services.properties as the --command-config flag when using kafka bin scripts."
}

case "${1}" in
    "--create" )
        shift; create ${1}
        ;;
    "--list" )
        list
        ;;
    "--get" )
        shift; get ${1}
        ;;
    "--delete" )
        shift; delete ${1}
        ;;
    "--certgen" )
        shift; certgen ${1}
        ;;
    *)
        echo "Unknown operation '${1}'";
        exit 1
        ;;
esac
