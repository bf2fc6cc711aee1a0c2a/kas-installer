#!/bin/bash

DIR_NAME="$(dirname $0)"
source ${DIR_NAME}/kas-installer.env


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

    rhoas login \
     --insecure \
     --auth-url $(oc get route -n mas-sso keycloak -o json | jq -r '"https://"+.spec.host+"/auth/realms/rhoas"')  \
     --mas-auth-url $(oc get route -n mas-sso keycloak -o json | jq -r '"https://"+.spec.host+"/auth/realms/rhoas"')  \
     --api-gateway $(oc get route -n kas-fleet-manager-${USER} kas-fleet-manager -o json | jq -r '"https://"+.spec.host')

}

dryrun() {

    echo "     --auth-url $(oc get route -n mas-sso keycloak -o json | jq -r '"https://"+.spec.host+"/auth/realms/rhoas"')  "
    echo "     --mas-auth-url $(oc get route -n mas-sso keycloak -o json | jq -r '"https://"+.spec.host+"/auth/realms/rhoas"')  "
    echo "     --api-gateway $(oc get route -n kas-fleet-manager-${USER} kas-fleet-manager -o json | jq -r '"https://"+.spec.host') "
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

