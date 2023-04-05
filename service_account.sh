#!/bin/bash

DIR_NAME="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
source ${DIR_NAME}/kas-installer.env
source ${DIR_NAME}/kas-installer-defaults.env
source ${DIR_NAME}/kas-installer-runtime.env

if [ "${SSO_PROVIDER_TYPE}" = "mas_sso" ] ; then
    # Service accounts via kas-fleet-manager when using MAS SSO
    SA_BASE_URL="https://${MAS_FLEET_MANAGEMENT_DOMAIN}/api/kafkas_mgmt/v1/service_accounts"
else
    SA_BASE_URL="${SSO_REALM_URL}/apis/service_accounts/v1"
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
        echo "[ERROR] - ${ERRCODE} - ${ERR_REASON}" >>/dev/stderr

        # Display existing service accounts if limit has been reached
        if [ "${ERRCODE}" = "KAFKAS-MGMT-4" ]; then
            echo "Existing service accounts:" >>/dev/stderr
            list | jq >>/dev/stderr
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
        echo "Status code: ${CODE}" >>/dev/stderr
        # Pretty print
        echo "${BODY}" | jq >>/dev/stderr
    else
        echo "Service account successfully deleted" >>/dev/stderr
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
    ACCESS_TOKEN="$(${DIR_NAME}/get_access_token.sh --owner 2>/dev/null)"
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
