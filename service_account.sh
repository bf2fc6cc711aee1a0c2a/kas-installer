#!/bin/bash

DIR_NAME="$(dirname $0)"
source ${DIR_NAME}/kas-installer.env
source ${DIR_NAME}/kas-fleet-manager/kas-fleet-manager-deploy.env

if [ "${INSTALL_MAS_SSO:-"n"}" = "y" ]; then
    # Service accounts via kas-fleet-manager when using MAS SSO
    SA_BASE_URL="https://kas-fleet-manager-kas-fleet-manager-${USER}.apps.${K8S_CLUSTER_DOMAIN}/api/kafkas_mgmt/v1/service_accounts"
else
    SA_BASE_URL="${MAS_SSO_BASE_URL}/auth/realms/${MAS_SSO_REALM}/apis/service_accounts/v1"
fi

create() {
    local RESPONSE=$(curl -sXPOST -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H 'Content-Type: application/json' \
      ${SA_BASE_URL} \
      --data-raw '{ "name": "'${USER}'-kafka-service-account", "description": "Test service account" }')

    local KIND=$(echo ${RESPONSE} | jq -r .kind)

    if [ "${KIND}" = "Error" ]; then
        local ERRCODE=$(echo ${RESPONSE} | jq -r .code)
        local ERR_REASON=$(echo ${RESPONSE} | jq -r .reason)
        echo "[ERROR] - ${ERRCODE} - ${ERR_REASON}"

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
    local RESPONSE=$(curl -sXGET -H "Authorization: Bearer ${ACCESS_TOKEN}" ${SA_BASE_URL})
    echo ${RESPONSE}
}

get() {
    local SERVICE_ACCOUNT_ID=${1}

    local RESPONSE=$(curl -sXGET -H "Authorization: Bearer ${ACCESS_TOKEN}" -w '\n\n%{http_code}' ${SA_BASE_URL}/${SERVICE_ACCOUNT_ID})
    local BODY=$(echo "${RESPONSE}" | head -n 1)
    local CODE=$(echo "${RESPONSE}" | tail -n -1)

    if [ ${CODE} -ge 400 ] ; then
        echo "Status code: ${CODE}" >>/dev/stderr
    fi

    # Pretty print
    echo "${BODY}" | jq
}

delete() {
    local SERVICE_ACCOUNT_ID=${1}

    local RESPONSE=$(curl -sXDELETE -H "Authorization: Bearer ${ACCESS_TOKEN}" -w '\n\n%{http_code}' ${SA_BASE_URL}/${SERVICE_ACCOUNT_ID})
    local BODY=$(echo "${RESPONSE}" | head -n 1)
    local CODE=$(echo "${RESPONSE}" | tail -n -1)

    if [ ${CODE} -ge 400 ] ; then
        echo "Status code: ${CODE}"
        # Pretty print
        echo "${BODY}" | jq
    else
        echo "Service account successfully deleted"
    fi
}

OPERATION='<NONE>'
ACCOUNT_ID='<NONE>'
ACCESS_TOKEN=''

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
    "--create" )
        OPERATION='create'
        shift
        ;;
    "--list" )
        OPERATION='list'
        shift
        ;;
    "--delete" )
        OPERATION='delete'
        ACCOUNT_ID="${2}"
        shift
        shift
        ;;
    "--get" )
        OPERATION='get'
        ACCOUNT_ID="${2}"
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

if [ -z "${ACCESS_TOKEN}" ] ; then
    ACCESS_TOKEN="$(${DIR_NAME}/get_access_token.sh --owner)"
fi

case "${OPERATION}" in
    "create" )
        create
        ;;
    "list" )
        list
        ;;
    "get" )
        get ${ACCOUNT_ID}
        ;;
    "delete" )
        delete ${ACCOUNT_ID}
        ;;
    *)
        echo "Unknown operation '${OPERATION}'";
        exit 1
        ;;
esac
