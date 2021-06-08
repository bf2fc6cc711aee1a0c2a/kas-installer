#!/bin/bash

DIR_NAME="$(dirname $0)"
source ${DIR_NAME}/kas-installer.env

create() {
    local RESPONSE=$(curl -sXPOST -H "Authorization: Bearer $(ocm token)" \
      https://kas-fleet-manager-kas-fleet-manager-${USER}.apps.${K8S_CLUSTER_DOMAIN}/api/kafkas_mgmt/v1/serviceaccounts \
      -d '{ "name": "'${USER}-kafka-service-account'" }')

    # Pretty print
    echo ${RESPONSE} | jq

    local KIND=$(echo ${RESPONSE} | jq -r .kind)

    if [ "${KIND}" = "Error" ]; then
        local ERRCODE=$(echo ${RESPONSE} | jq -r .code)

        # Display existing service accounts if limit has been reached
        if [ "${ERRCODE}" = "KAFKAS-MGMT-4" ]; then
            list
        fi

        exit 1
    fi
}

list() {
    local RESPONSE=$(curl -sXGET -H "Authorization: Bearer $(ocm token)" \
      https://kas-fleet-manager-kas-fleet-manager-${USER}.apps.${K8S_CLUSTER_DOMAIN}/api/kafkas_mgmt/v1/serviceaccounts)

    echo "Existing service accounts:"
    echo ${RESPONSE} | jq
}

delete() {
    local SERVICE_ACCOUNT_ID=${1}

    local RESPONSE=$(curl -sXDELETE -H "Authorization: Bearer $(ocm token)" -w '\n\n%{http_code}' \
      https://kas-fleet-manager-kas-fleet-manager-${USER}.apps.${K8S_CLUSTER_DOMAIN}/api/kafkas_mgmt/v1/serviceaccounts/${SERVICE_ACCOUNT_ID})
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
