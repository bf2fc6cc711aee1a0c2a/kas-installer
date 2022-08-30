#!/bin/bash

DIR_NAME="$(dirname $0)"
source ${DIR_NAME}/kas-installer.env
source ${DIR_NAME}/kas-fleet-manager/kas-fleet-manager-deploy.env

setvars() {
    AUTH_URL="${SSO_REALM_URL}"

    API_GATEWAY="$(oc get route -n kas-fleet-manager-${USER} kas-fleet-manager -o json | jq -r '"https://"+.spec.host')"

    if [ "${SSO_PROVIDER_TYPE:-}" = "redhat_sso" ] && [ "${REDHAT_SSO_HOSTNAME:-}" = "sso.stage.redhat.com" ] ; then
        CLIENT_ID='rhoas-cli-stage'
    else
        CLIENT_ID='rhoas-cli-prod'
    fi

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

    rhoas login \
     --insecure \
     --client-id ${CLIENT_ID} \
     --auth-url ${AUTH_URL} \
     --api-gateway ${API_GATEWAY}

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

