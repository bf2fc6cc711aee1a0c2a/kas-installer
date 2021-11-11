#!/bin/bash

DIR_NAME="$(dirname $0)"
source ${DIR_NAME}/kas-installer.env

echo "Login with ${RH_USERNAME}/${RH_USERNAME}"

rhoas login --auth-url $(oc get route -n mas-sso keycloak -o json | jq -r '"https://"+.spec.host+"/auth/realms/rhoas"')  --api-gateway $(oc get route -n kas-fleet-manager-${USER} kas-fleet-manager -o json | jq -r '"https://"+.spec.host')

