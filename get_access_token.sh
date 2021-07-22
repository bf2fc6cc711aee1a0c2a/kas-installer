#!/bin/bash

DIR_NAME="$(dirname $0)"
OS=$(uname)

if [ "$OS" = 'Darwin' ]; then
  # for MacOS
  DATE=$(which gdate)
else
  # for Linux and Windows
  DATE=$(which date)
fi

source ${DIR_NAME}/kas-installer.env

GRANT_TYPE=''
USER_PARAMS=''

case ${1} in
    "--owner" )
        GRANT_TYPE='password'
        CLIENT_ID=${RH_USERNAME}
        CLIENT_SECRET=${RH_USERNAME}
        USER_PARAMS="&username=${RH_USERNAME}&password=${RH_USERNAME}"
        ;;
    *) # Assume client ID and secret were provided
        GRANT_TYPE='client_credentials'
        CLIENT_ID=${1}
        CLIENT_SECRET=${2}
        ;;
esac

if [ -z "${CLIENT_ID}" ] || [ -z "${CLIENT_SECRET}" ]; then
    echo "Service account clientID and clientSecret are both required."
    echo "Values may be obtained from Fleet Manager API using create_service_account.sh script"
    exit 1
fi

RESPONSE=$(curl --fail --show-error -sX POST -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=${GRANT_TYPE}&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}${USER_PARAMS}" \
  https://keycloak-mas-sso.apps.${K8S_CLUSTER_DOMAIN}/auth/realms/rhoas/protocol/openid-connect/token)

if [ ${?} -ne 0 ]; then
    echo ${RESPONSE} > /dev/stderr
    exit 1
fi

ACCESS_TOKEN=$(echo "${RESPONSE}" | jq -r .access_token)
EXPIRES_IN=$(echo "${RESPONSE}" | jq -r .expires_in)

printf "Access Token (expires at %s):\n" "$(${DATE} --date="${EXPIRES_IN} seconds")" >>/dev/stderr
printf "%s\n" ${ACCESS_TOKEN}
