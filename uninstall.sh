#!/bin/bash

set -euo pipefail

DIR_NAME="$(dirname $0)"

source "${DIR_NAME}/utils/common.sh"

KAS_INSTALLER_ENV_FILE="kas-installer.env"
source ${KAS_INSTALLER_ENV_FILE}

if ! cluster_domain_check "${K8S_CLUSTER_DOMAIN}" "uninstall"; then
    echo "Exiting ${0}"
    exit 1
fi

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
    if [ "${SSO_PROVIDER_TYPE}" = "redhat_sso" ] ; then
        FLEETSHARD_AGENT_CLIENT_ID=$(${OC} get secret addon-kas-fleetshard-operator-parameters -n ${KAS_FLEETSHARD_OPERATOR_NAMESPACE} -o json | jq -r '.data."sso-client-id"' | base64 -d)
    fi

    if [ -n "${OCM_CLUSTER_ID-""}" ] ; then
        if [ -n "${OCM}" ] ; then
            ${OCM} delete "/api/clusters_mgmt/v1/clusters/${OCM_CLUSTER_ID}/addons/kas-fleetshard-operator-qe" || true
            ${OCM} delete "/api/clusters_mgmt/v1/clusters/${OCM_CLUSTER_ID}/addons/managed-kafka-qe" || true
        fi
    fi

    (cd ${DIR_NAME}/operators && ./uninstall-all.sh)
    ${KUBECTL} delete namespace ${KAS_FLEETSHARD_OPERATOR_NAMESPACE} || true
    ${KUBECTL} delete namespace ${STRIMZI_OPERATOR_NAMESPACE} || true

    if [ -n "${FLEETSHARD_AGENT_CLIENT_ID:-}" ] ; then
        echo "Deleting fleetshard agent service account: ${FLEETSHARD_AGENT_CLIENT_ID}"
        ${DIR_NAME}/service_account.sh --delete "${FLEETSHARD_AGENT_CLIENT_ID}"
    fi
fi

OBSERVABILITY_NS=managed-application-services-observability
${KUBECTL} delete subscription --all -n ${OBSERVABILITY_NS} || true
${KUBECTL} delete catalogsource --all -n ${OBSERVABILITY_NS} || true
${KUBECTL} delete observabilities --all -n ${OBSERVABILITY_NS} || true
${KUBECTL} delete csv --all -n ${OBSERVABILITY_NS} || true
${KUBECTL} delete operatorgroup --all -n ${OBSERVABILITY_NS} || true
${KUBECTL} delete namespace ${OBSERVABILITY_NS} || true
