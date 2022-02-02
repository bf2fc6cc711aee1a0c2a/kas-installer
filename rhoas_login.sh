#!/bin/bash

DIR_NAME="$(dirname $0)"
source ${DIR_NAME}/kas-installer.env
source ${DIR_NAME}/kas-fleet-manager/kas-fleet-manager-deploy.env

setvars() {
    AUTH_URL="${MAS_SSO_BASE_URL}/auth/realms/${MAS_SSO_REALM}"
    MAS_AUTH_URL_ARG=""

    if [ "${MAS_SSO_REALM}" = 'rhoas' ] ; then
        MAS_AUTH_URL_ARG="--mas-auth-url=${AUTH_URL}"
    fi

    API_GATEWAY="$(oc get route -n kas-fleet-manager-${USER} kas-fleet-manager -o json | jq -r '"https://"+.spec.host')"

    if [ ${?} != 0 ] ; then
        echo "Failed to retrieve kas-fleet-manager URL"
        exit 1
    fi
}

login() {
    echo "Login with ${RH_USERNAME}/${RH_USERNAME}"
    OS=$(uname)

    if [ "$OS" = 'Darwin' ]; then
        # for MacOS
        COPYCMD=$(which pbcopy &>/dev/null)
    else
        # for Linux and Windows
        COPYCMD=$(which xclip &>/dev/null)
        if [ -n "${COPYCMD}" ] ; then
            COPYCMD="${COPYCMD} -selection clipboard"
        fi
    fi

    if [ -n "${COPYCMD}" ] ; then
        echo "Copying ${RH_USERNAME} in the clipboard"
        echo "${RH_USERNAME}" | ${COPYCMD}
    fi

    setvars

    rhoas login \
     --insecure \
     --auth-url ${AUTH_URL} \
     ${MAS_AUTH_URL_ARG} \
     --api-gateway ${API_GATEWAY}

}

dryrun() {
    setvars
    echo "     --auth-url ${AUTH_URL}  "
    if [ -n "${MAS_AUTH_URL_ARG}" ]; then
        echo "     ${MAS_AUTH_URL_ARG}  "
    fi
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

