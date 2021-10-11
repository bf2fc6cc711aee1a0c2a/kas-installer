#!/bin/bash

KUBECTL=$(which kubectl)
DIR_NAME="$(dirname $0)"
source ${DIR_NAME}/kas-installer.env

OS=$(uname)

BOOTSTRAP_SERVER_HOST=$(${DIR_NAME}/managed_kafka.sh --list | jq -r .items[0].bootstrap_server_host | awk -F: '{print $1}')
MK_ADMIN_URL="http://admin-server-${BOOTSTRAP_SERVER_HOST}/rest/acls"

if [ -z "${SA_CLIENT_ID:-}" ] ; then
        SERVICE_ACCOUNT_RESOURCE=$(${DIR_NAME}/service_account.sh --list)
        SA_CLIENT_ID=$(echo ${SERVICE_ACCOUNT_RESOURCE} | jq -r .items[0].client_id)
        SA_CLIENT_SECRET=$(cat app-services.properties | tail -n -1 | cut -d '=' -f4 | sed -e 's/"//g; s/;//g')

        if [ -z "${SA_CLIENT_ID:-}" ] ; then
            echo "Failed to retrive a service account!"
            exit 1
        fi

        echo "Using service account: ${SA_CLIENT_ID}"
fi

ACCESS_TOKEN=$(${DIR_NAME}/get_access_token.sh ${SA_CLIENT_ID} ${SA_CLIENT_SECRET})

apicall(){
    local TYPE=${1}
    local NAME=${2}
    local PERMISSION=${3}
    local BODY='{"resourceType":"'${TYPE}'","resourceName":"'${NAME}'","patternType":"LITERAL","principal":"User:'${SA_CLIENT_ID}'","operation":"ALL","permission":"'${PERMISSION}'"}'
    local RESPONSE=$(curl -s  -H"Authorization: Bearer ${ACCESS_TOKEN}" ${MK_ADMIN_URL} -XPOST -H'Content-type: application/json' --data ${BODY})

    local CODE=$(echo "${RESPONSE}" | jq .code)
    echo ${RESPONSE}
    if [ ${CODE} -ne 200 ] ; then
        echo "operation failed!"
    fi
}

allowall() {
    apicall 'TOPIC' '*' 'ALLOW'
    apicall 'GROUP' '*' 'ALLOW'
    apicall 'CLUSTER' '*' 'ALLOW'
    apicall 'TRANSACTIONAL_ID' '*' 'ALLOW'
}

allowtopic() {
    apicall 'TOPIC' ${1} 'ALLOW'
}

allowgroup() {
    apicall 'GROUP' ${1} 'ALLOW'
}

denyall() {
    apicall 'TOPIC' '*' 'DENY'
    apicall 'GROUP' '*' 'DENY'
    apicall 'CLUSTER' '*' 'DENY'
    apicall 'TRANSACTIONAL_ID' '*' 'DENY'
}

denytopic() {
    apicall 'TOPIC' ${1} 'DENY'
}

denygroup() {
    apicall 'GROUP' ${1} 'DENY'
}

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
    "--allow-all" )
        OPERATION='allow-all'
        shift
        ;;
    "--allow-topic" )
        OPERATION='allow-topic'
        RESOURCE_NAME=${2}
        shift
        shift
        ;;
    "--allow-group" )
        OPERATION='allow-group'
        RESOURCE_NAME=${2}
        shift
        shift
        ;;
    "--deny-all" )
        OPERATION='deny-all'
        shift
        ;;
    "--deny-topic" )
        OPERATION='deny-topic'
        RESOURCE_NAME=${2}
        shift
        shift
        ;;
    "--deny-group" )
        OPERATION='deny-group'
        RESOURCE_NAME=${2}
        shift
        shift
        ;;
    *) # unknown option
        shift
        ;;
    esac
done

case "${OPERATION}" in
    "allow-all" )
        allowall
        ;;
    "allow-topic" )
        allowtopic ${RESOURCE_NAME}
        ;;
    "allow-group" )
        allowgroup ${RESOURCE_NAME}
        ;;
    "deny-all" )
        denyall
        ;;
    "deny-topic" )
        denytopic ${RESOURCE_NAME}
        ;;
    "allow-group" )
        denygroup ${RESOURCE_NAME}
        ;;
    *)
        echo ""
        echo "usage: acl.sh [--allow-all|--allow-topic <topic-name>|--allow-group <group-name>|--deny-all|--deny-topic <topic-name>|--deny-group <group-name>"
        echo "NOTE: you can use * as the name to cover all topics or groups"
        echo ""
        exit 1
        ;;
esac