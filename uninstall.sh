#!/bin/bash

set -euo pipefail

OS=$(uname)

GIT=$(which git)
OC=$(which oc)
KUBECTL=$(which kubectl)
MAKE=$(which make)
OPENSSL=$(which openssl)
OCM=$(which ocm)

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
source ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

${KUBECTL} delete namespace ${KAS_FLEET_MANAGER_NAMESPACE} || true

if [ "${SKIP_SSO:-"n"}" = "y" ] ; then
    echo "Skipping removal of MAS SSO"
else
    ${KUBECTL} delete keycloakusers -l app=mas-sso --all-namespaces || true
    ${KUBECTL} delete keycloakclients -l app=mas-sso --all-namespaces || true
    ${KUBECTL} delete keycloakrealms --all -n mas-sso || true
    ${KUBECTL} delete keycloaks -l app=mas-sso --all-namespaces || true
    ${KUBECTL} delete namespace mas-sso || true
fi

if [ "${SKIP_OBSERVATORIUM:-"n"}" = "y" ] ; then
    echo "Skipping removal of Observatorium"
else
  ${KUBECTL} delete namespace observatorium || true
  ${KUBECTL} delete namespace dex || true
  ${KUBECTL} delete namespace observatorium-minio || true
fi

if [ "${SKIP_KAS_FLEETSHARD:-"n"}" = "y" ]; then
    echo "Skipping removal of Strimzi and Fleetshard operators"
else
    if [ -n "${OCM_CLUSTER_ID-""}" ] ; then
        if [ -n "${OCM}" ] ; then
            ${OCM} delete "/api/clusters_mgmt/v1/clusters/${OCM_CLUSTER_ID}/addons/kas-fleetshard-operator-qe" || true
            ${OCM} delete "/api/clusters_mgmt/v1/clusters/${OCM_CLUSTER_ID}/addons/managed-kafka-qe" || true
        fi
    fi

    (cd ${DIR_NAME}/operators && ./uninstall-all.sh)
    ${KUBECTL} delete namespace ${KAS_FLEETSHARD_OPERATOR_NAMESPACE} || true
    ${KUBECTL} delete namespace ${STRIMZI_OPERATOR_NAMESPACE} || true
fi

OBSERVABILITY_NS=managed-application-services-observability
${KUBECTL} delete subscription --all -n ${OBSERVABILITY_NS} || true
${KUBECTL} delete catalogsource --all -n ${OBSERVABILITY_NS} || true
${KUBECTL} delete observabilities --all -n ${OBSERVABILITY_NS} || true
${KUBECTL} delete csv --all -n ${OBSERVABILITY_NS} || true
${KUBECTL} delete operatorgroup --all -n ${OBSERVABILITY_NS} || true
${KUBECTL} delete namespace ${OBSERVABILITY_NS} || true
