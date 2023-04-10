#!/bin/bash

DIR_NAME="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
source ${DIR_NAME}/kas-installer.env
source ${DIR_NAME}/kas-installer-runtime.env
CLIENT_ID=''

setvars() {
    AUTH_URL="${SSO_REALM_URL}"
    API_GATEWAY="https://${MAS_FLEET_MANAGEMENT_DOMAIN}"

    if [ -n "${CLIENT_ID}" ] ; then
        continue
    elif [ "${SSO_PROVIDER_TYPE:-}" = "mas_sso" ] ; then
        CLIENT_ID='kas-installer-client'

        if [ -z "${OFFLINE_TOKEN:-}" ] ; then
            OFFLINE_TOKEN=$(${DIR_NAME}/bin/get_token.sh refresh_token --owner)
        fi
    elif [ "${SSO_PROVIDER_TYPE:-}" = "redhat_sso" ] && [ "${REDHAT_SSO_HOSTNAME:-}" = "sso.stage.redhat.com" ] ; then
        CLIENT_ID='rhoas-cli-stage'
    else
        CLIENT_ID='rhoas-cli-prod'
    fi
}

login() {
    echo "Login with ${RH_USERNAME}/${RH_USERNAME}"
    OS=$(uname)

    if [ "$OS" = 'Darwin' ]; then
        # for MacOS
        if command -v pbcopy >/dev/null 2>&1; then
          COPYCMD=$(command -v pbcopy)
        fi
    else
        # for Linux and Windows
        if command -v xclip >/dev/null 2>&1; then
            COPYCMD="$(command -v xclip) -selection clipboard"
        fi
    fi

    if [ -n "${COPYCMD}" ] ; then
        echo "Copying ${RH_USERNAME} in the clipboard"
        echo "${RH_USERNAME}" | ${COPYCMD}
    fi

    setvars

    if [ -n "${OFFLINE_TOKEN}" ] ; then
        TOKEN_PARAM="--token ${OFFLINE_TOKEN}"
    else
        TOKEN_PARAM=''
    fi

    rhoas login \
     --insecure \
     --client-id ${CLIENT_ID} \
     --auth-url ${AUTH_URL} \
     --api-gateway ${API_GATEWAY} \
     ${TOKEN_PARAM}
}

dryrun() {
    setvars
    echo "     --auth-url ${AUTH_URL}  "
    echo "     --api-gateway ${API_GATEWAY} "
}

OPERATION='<NONE>'

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
    "--dry-run" )
        OPERATION='dryrun'
        shift
        ;;
    "--login" )
        OPERATION='login'
        shift
        ;;
    "--token" )
        OFFLINE_TOKEN=${2}
        shift; shift;
        ;;
    "--client-id" )
        CLIENT_ID=${2}
        shift; shift;
        ;;
    *) # default operation
        OPERATION="$key"
        shift
        ;;
    esac
done

case "${OPERATION}" in
    "login" )
        login
        ;;
    "dryrun" )
        dryrun
        ;;
    "<NONE>" )
        login
        ;;
    *)
        echo "Unknown operation '${OPERATION}'";
        exit 1
        ;;
esac

