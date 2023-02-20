#!/bin/bash

set -euo pipefail

DIR_NAME="$(dirname $0)"

source "${DIR_NAME}/utils/common.sh"
source "${DIR_NAME}/kas-installer.env"
source "${DIR_NAME}/kas-installer-defaults.env"

if ! cluster_domain_check "${K8S_CLUSTER_DOMAIN}" "uninstall"; then
    echo "Exiting ${0}"
    exit 1
fi

KAS_FLEET_MANAGER_DIR="${DIR_NAME}/kas-fleet-manager"
source "${KAS_FLEET_MANAGER_DIR}/kas-fleet-manager-deploy.env"

if [ -z "$(${OC} get namespace/${KAS_FLEET_MANAGER_NAMESPACE} -o jsonpath="{.metadata.name}" --ignore-not-found)" ]; then
    echo "namespace/${KAS_FLEET_MANAGER_NAMESPACE} is already removed"
else
    # Remove all Kafka instances
    for MKID in $(${DIR_NAME}/managed_kafka.sh --list | jq -r '.items[] | .id' 2>/dev/null || echo "") ; do
        echo "Removing Kafka instance ${MKID}"
        ${DIR_NAME}/managed_kafka.sh --delete ${MKID} --wait
    done

    ACCESS_TOKEN="$(${DIR_NAME}/get_access_token.sh --owner 2>/dev/null)"
    CLUSTERS_BASE_URL="https://kas-fleet-manager-kas-fleet-manager-${USER}.apps.${K8S_CLUSTER_DOMAIN}/api/kafkas_mgmt/v1/clusters"

    # Deregister all dedicated clusters
    for CID in $(curl -sXGET -H "Authorization: Bearer ${ACCESS_TOKEN}" ${CLUSTERS_BASE_URL} | jq -r '.items[] | .id' 2>/dev/null || echo "") ; do
        ${DIR_NAME}/deregister_cluster.sh "${CID}"
    done

    ${KUBECTL} delete namespace ${KAS_FLEET_MANAGER_NAMESPACE} || true
fi

if [ "${SKIP_SSO:-"n"}" = "y" ] ; then
    echo "Skipping removal of MAS SSO"
else
    ${KUBECTL} delete keycloakusers.keycloak.org -l app=mas-sso --all-namespaces || true
    ${KUBECTL} delete keycloakclients.keycloak.org -l app=mas-sso --all-namespaces || true
    ${KUBECTL} delete keycloakrealms.keycloak.org --all -n mas-sso || true
    ${KUBECTL} delete keycloaks.keycloak.org -l app=mas-sso --all-namespaces || true
    ${KUBECTL} delete namespace mas-sso || true
    # remove all CRDs
    ${KUBECTL} delete crd -l operators.coreos.com/mas-sso-operator.mas-sso=''

    ${KUBECTL} delete keycloaks.k8s.keycloak.org -l app=mas-sso -n mas-sso || true
    ${KUBECTL} delete keycloakrealmimports.k8s.keycloak.org -l app=mas-sso -n mas-sso || true
    ${KUBECTL} delete crd -l operators.coreos.com/keycloak-operator.mas-sso=''
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
elif [ -z "$(grep 'CLUSTER_LIST=\[[ ]*\]' ${DIR_NAME}/kas-fleet-manager/kas-fleet-manager-params.env || true)" ] ; then
    # Remove statically-configured cluster

    if [ "${SSO_PROVIDER_TYPE}" = "redhat_sso" ] ; then
        FLEETSHARD_AGENT_CLIENT_ID=$(${OC} get secret addon-kas-fleetshard-operator-parameters -n ${KAS_FLEETSHARD_OPERATOR_NAMESPACE} -o json | jq -r '.data."sso-client-id"' | base64 -d || echo "")
    fi

    OCM_MODE='false'

    if [ -n "${OCM_SERVICE_TOKEN-""}" ] && [ -n "${OCM_CLUSTER_ID-""}" ] ; then
        OCM_MODE='true'
    fi

    delete_dataplane_resources ${OCM_MODE} 'false' "${OCM_CLUSTER_ID}"

    if [ -n "${FLEETSHARD_AGENT_CLIENT_ID:-}" ] ; then
        echo "Deleting fleetshard agent service account: ${FLEETSHARD_AGENT_CLIENT_ID}"
        ${DIR_NAME}/service_account.sh --delete "${FLEETSHARD_AGENT_CLIENT_ID}"
    fi
else
    echo "Empty CLUSTER_LIST - skipping statically-configured data plane cleanup"
fi
