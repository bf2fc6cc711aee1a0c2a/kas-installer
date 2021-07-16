#!/bin/bash

DIR_NAME="$(dirname $0)"
source ${DIR_NAME}/kas-installer.env
SA_BASE_URL="https://kas-fleet-manager-kas-fleet-manager-${USER}.apps.${K8S_CLUSTER_DOMAIN}/api/kafkas_mgmt/v1/service_accounts"

create() {
    local RESPONSE=$(curl -sXPOST -H "Authorization: Bearer $(ocm token)" \
      ${SA_BASE_URL} \
      -d '{ "name": "'${USER}-kafka-service-account'" }')

    local KIND=$(echo ${RESPONSE} | jq -r .kind)

    if [ "${KIND}" = "Error" ]; then
        local ERRCODE=$(echo ${RESPONSE} | jq -r .code)

        # Display existing service accounts if limit has been reached
        if [ "${ERRCODE}" = "KAFKAS-MGMT-4" ]; then
            echo "Existing service accounts:"
            list | jq
        fi

        exit 1
    fi

    echo ${RESPONSE}
}

list() {
    local RESPONSE=$(curl -sXGET -H "Authorization: Bearer $(ocm token)" ${SA_BASE_URL})
    echo ${RESPONSE}
}

delete() {
    local SERVICE_ACCOUNT_ID=${1}

    local RESPONSE=$(curl -sXDELETE -H "Authorization: Bearer $(ocm token)" -w '\n\n%{http_code}' ${SA_BASE_URL}/${SERVICE_ACCOUNT_ID})
    local BODY=$(echo "${RESPONSE}" | head -n 1)
    local CODE=$(echo "${RESPONSE}" | tail -n -1)

    echo "Status code: ${CODE}"

    if [ ${CODE} -ge 400 ] ; then
        # Pretty print
        echo "${BODY}" | jq
    else
        echo "Service account successfully deleted"
    fi
}

case "${1}" in
    "--create" )
        create
        ;;
    "--list" )
        list
        ;;
    "--delete" )
        shift; delete ${1}
        ;;
    *)
        echo "Unknown operation '${1}'";
        exit 1
        ;;
esac
