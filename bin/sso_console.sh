#!/bin/bash

DIR_NAME="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
source "${DIR_NAME}/../kas-installer.env"
source "${DIR_NAME}/../kas-installer-defaults.env"
OC=$(which oc)

CONSOLE_URL="https://sso-keycloak.apps.${K8S_CLUSTER_DOMAIN}/auth/admin"

echo "********************************************************************************"
echo "* Opening Keycloak console: https://sso-keycloak.apps.${K8S_CLUSTER_DOMAIN}/auth/admin"
echo "* Keycloak admin user: $(${OC} get secret sso-keycloak-initial-admin -n mas-sso -o jsonpath='{.data.username}' | base64 --decode)"
echo "* Keycloak admin pass: $(${OC} get secret sso-keycloak-initial-admin -n mas-sso -o jsonpath='{.data.password}' | base64 --decode)"
echo "********************************************************************************"

xdg-open "${CONSOLE_URL}"
