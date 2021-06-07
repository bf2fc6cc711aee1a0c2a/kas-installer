#!/bin/bash

DIR_NAME="$(dirname $0)"
source ${DIR_NAME}/kas-installer.env

CLIENT_ID=$1
CLIENT_SECRET=$2

if [ -z "${CLIENT_ID}" ] || [ -z "${CLIENT_SECRET}" ]; then
    echo "Service account clientID and clientSecret are both required."
    echo "Values may be obtained from Fleet Manager API using create_service_account.sh script"
    exit 1
fi

RESPONSE=$(curl --fail --show-error -sX POST -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}" \
  https://keycloak-mas-sso.apps.${K8S_CLUSTER_DOMAIN}/auth/realms/rhoas/protocol/openid-connect/token)

if [ ${?} -ne 0 ]; then
    exit 1
fi

ACCESS_TOKEN=$(echo "${RESPONSE}" | jq -r .access_token)
EXPIRES_IN=$(echo "${RESPONSE}" | jq -r .expires_in)

printf "Access Token (expires at %s):\n%s\n" "$(date --date="${EXPIRES_IN} seconds")" ${ACCESS_TOKEN}
