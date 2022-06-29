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
source ${DIR_NAME}/kas-fleet-manager/kas-fleet-manager-deploy.env

GRANT_TYPE=''
USER_PARAMS=''
SCOPES=''

case ${1} in
    "--owner" )
        if [ "${RHOAS_TOKEN:-false}" = 'true' ] ; then
            RHOAS_WHOAMI=$(rhoas whoami)

            if [ ${?} -ne 0 ]; then
                echo ${RHOAS_WHOAMI} > /dev/stderr
                exit 1
            fi

            ACCESS_TOKEN=$(cat ${HOME}/.config/rhoas/config.json | jq -r '.access_token')
            printf "%s\n" ${ACCESS_TOKEN}
            exit 0
        fi

        if [ "${SSO_PROVIDER_TYPE:-}" = "redhat_sso" ] && [ -n "${REDHAT_SSO_CLIENT_ID:-}" ] && [ -n "${REDHAT_SSO_CLIENT_SECRET:-}" ]; then
            GRANT_TYPE='client_credentials'
            CLIENT_ID=${REDHAT_SSO_CLIENT_ID}
            CLIENT_SECRET=${REDHAT_SSO_CLIENT_SECRET}

            if [ -n "${REDHAT_SSO_SCOPE:-}" ] ; then
                SCOPES="&scope=${REDHAT_SSO_SCOPE}"
            fi
        else
            GRANT_TYPE='password'
            CLIENT_ID='kas-installer-client'
            CLIENT_SECRET='kas-installer-client'
            USER_PARAMS="&username=${RH_USERNAME}&password=${RH_USERNAME}"
        fi
        ;;
    "--sre-admin" )
        SSO_REALM_URL=${MAS_SSO_BASE_URL}/auth/realms/rhoas-kafka-sre
        GRANT_TYPE='client_credentials'
        CLIENT_ID='kafka-admin'
        CLIENT_SECRET='kafka-admin'
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

TOKEN_URI="${SSO_REALM_URL}/protocol/openid-connect/token"

RESPONSE=$(curl --fail --show-error -sX POST -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=${GRANT_TYPE}&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}${USER_PARAMS}${SCOPES}" \
  ${TOKEN_URI})

if [ ${?} -ne 0 ]; then
    echo ${RESPONSE} > /dev/stderr
    exit 1
fi

ACCESS_TOKEN=$(echo "${RESPONSE}" | jq -r .access_token)
EXPIRES_IN=$(echo "${RESPONSE}" | jq -r .expires_in)

printf "Access Token (expires at %s):\n" "$(${DATE} --date="${EXPIRES_IN} seconds")" >>/dev/stderr
printf "%s\n" ${ACCESS_TOKEN}
