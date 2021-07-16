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
source ${KAS_INSTALLER_ENV_FILE}

KAS_FLEET_MANAGER_DIR="${DIR_NAME}/kas-fleet-manager"
KAS_FLEET_MANAGER_DEPLOY_ENV_FILE="${KAS_FLEET_MANAGER_DIR}/kas-fleet-manager-deploy.env"
TERRAFORM_FILES_BASE_DIR="terraforming"
TERRAFORM_GENERATED_DIR="${KAS_FLEET_MANAGER_DIR}/${TERRAFORM_FILES_BASE_DIR}/terraforming-generated-k8s-resources"
source ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

(cd ${DIR_NAME}/operators && \
  ./uninstall-kas-fleetshard.sh && \
  ./uninstall-strimzi-cluster-operator.sh)

${KUBECTL} delete namespace ${KAS_FLEETSHARD_OPERATOR_NAMESPACE} || true
${KUBECTL} delete namespace ${STRIMZI_OPERATOR_NAMESPACE} || true

${KUBECTL} delete observabilities --all -n managed-application-services-observability || true

for i in $(find ${TERRAFORM_GENERATED_DIR} -type f | sort); do
    echo "Deleting K8s resource ${i} ..."
    ${KUBECTL} delete -f ${i} || true
done

${KUBECTL} delete namespace ${KAS_FLEET_MANAGER_NAMESPACE} || true
${KUBECTL} delete namespace managed-application-services-observability || true

if [ "${SKIP_SSO}n" = "n" ] ; then
    ${KUBECTL} delete keycloakclients -l app=mas-sso --all-namespaces || true
    ${KUBECTL} delete keycloakrealms --all -n mas-sso || true
    ${KUBECTL} delete keycloaks -l app=mas-sso --all-namespaces || true
    ${KUBECTL} delete namespace mas-sso || true
else
    echo "MAS SSO not uninstalled"
fi
