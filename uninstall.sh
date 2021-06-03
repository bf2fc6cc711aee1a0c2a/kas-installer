#!/bin/bash

set -euo pipefail

OS=$(uname)

GIT=$(which git)
OC=$(which oc)
KUBECTL=$(which kubectl)
MAKE=$(which make)
OPENSSL=$(which openssl)

if [ "$OS" = 'Darwin' ]; then
  # for MacOS
  SED=$(which gsed)
else
  # for Linux and Windows
  SED=$(which sed)
fi

DIR_NAME="$(dirname $0)"

KAS_INSTALLER_ENV_FILE="kas-installer.env"

(cd operators && ./uninstall-kas-fleetshard.sh && ./uninstall-strimzi-cluster-operator.sh)

source kas-fleet-manager/kas-fleet-manager-deploy.env

${KUBECTL} delete namespace ${KAS_FLEET_MANAGER_NAMESPACE}

${KUBECTL} delete observabilities --all -n managed-application-services-observability
${KUBECTL} delete namespace managed-application-services-observability

${KUBECTL} delete keycloakclients -l app=mas-sso --all-namespaces
${KUBECTL} delete keycloakrealms -n mas-sso
${KUBECTL} delete keycloaks -l app=mas-sso --all-namespaces
${KUBECTL} delete namespace mas-sso
