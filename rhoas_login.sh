#!/bin/bash

DIR_NAME="$(dirname $0)"
source ${DIR_NAME}/kas-installer.env
source ${DIR_NAME}/kas-fleet-manager/kas-fleet-manager-deploy.env

echo "Login with ${RH_USERNAME}/${RH_USERNAME}"

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

rhoas login --insecure --auth-url ${AUTH_URL} ${MAS_AUTH_URL_ARG} --api-gateway ${API_GATEWAY}
