#!/bin/bash

set -Eeuo pipefail

DIR_NAME="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
source ${DIR_NAME}/../utils/common.sh
source ${DIR_NAME}/../kas-installer.env
source ${DIR_NAME}/../kas-installer-defaults.env
source ${DIR_NAME}/../kas-installer-runtime.env

ACTION=''
CLUSTER_ID=''
CONNECTORS_ADDON_STANDALONE='false'

while [[ ${#} -gt 0 ]]; do
    case ${1} in
        "install" )
            ACTION="install"
            CLUSTER_ID=${2:?cluster ID must be given to install the Connectors addon}
            shift; shift;
            ;;
        "uninstall" )
            ACTION="uninstall"
            shift;
            ;;
        "--standalone" )
            CONNECTORS_ADDON_STANDALONE='true'
            shift;
            ;;
        *)
            echo "Unknown option '${1}'";
            exit 1
            ;;
    esac
done

if [ -z "${ACTION}" ] || ! [[ "${ACTION}" =~ ^(install|uninstall)$ ]] ; then
    echo "Missing or invalid action argument. Must be one of 'install', 'uninstall'"
    exit 1
fi

MODE=''

if [ -n "${OCM_SERVICE_TOKEN-""}" ] && [ -n "${OCM_CLUSTER_ID-""}" ] && [ "${CONNECTORS_ADDON_STANDALONE:-"false"}" != "true" ] ; then
    MODE='ocm'
else
    MODE='standalone'
fi

CURRENT_RHOAS_USER=$(rhoas whoami || true)

if [ -z "${CURRENT_RHOAS_USER}" ] ; then
    exit 1
fi

if [ "${ACTION}" == 'install' ] ; then
    ADDON_LITERAL_PARAMS=$(rhoas connector cluster addon-parameters --id "${CLUSTER_ID}" -o json | \
        jq -r 'map("--from-literal=\(.id)=\(.value|tostring)") | join(" ")')

    if [ "${MODE}" == "standalone" ] ; then
        NAMESPACE='redhat-openshift-connectors'

        if [ -z "$(${OC} get namespace/${NAMESPACE} -o jsonpath="{.metadata.name}" --ignore-not-found)" ]; then
            echo "K8s namespace ${NAMESPACE} does not exist. Creating it..."
            ${OC} create namespace ${NAMESPACE}
        fi

        if [ -n "$(${OC} get secret addon-connectors-operator-parameters -n ${NAMESPACE} -o jsonpath="{.metadata.name}" --ignore-not-found)" ]; then
            ${OC} delete secret addon-connectors-operator-parameters -n ${NAMESPACE}
        fi

        ${OC} create secret generic "addon-connectors-operator-parameters" ${ADDON_LITERAL_PARAMS} -n "${NAMESPACE}"

        if [ -n "$(${OC} get secret addon-pullsecret -n ${NAMESPACE} -o jsonpath="{.metadata.name}" --ignore-not-found)" ]; then
            ${OC} delete secret addon-pullsecret -n ${NAMESPACE}
        fi

        ${OC} create secret docker-registry "addon-pullsecret" -n ${NAMESPACE} \
          --docker-server=${COS_FLEET_MANAGER_IMAGE_REGISTRY} \
          --docker-username=${COS_FLEET_MANAGER_IMAGE_REPOSITORY_USERNAME} \
          --docker-password=${COS_FLEET_MANAGER_IMAGE_REPOSITORY_PASSWORD}

        echo "apiVersion: addons.managed.openshift.io/v1alpha1
kind: Addon
metadata:
  name: connectors-operator
spec:
  displayName: Red Hat OpenShift Connectors
  install:
    olmAllNamespaces:
      catalogSourceImage: ${CONNECTORS_OPERATOR_OLM_INDEX_IMAGE}
      channel: stable
      config:
        env: []
      namespace: redhat-openshift-connectors
      packageName: cos-fleetshard-sync
    type: OLMAllNamespaces
  namespaces:
    - name: redhat-openshift-connectors
  pause: false" | ${OC} apply -f -

    elif [ "${MODE}" == "ocm" ] ; then
        ${OC} create secret generic "add-secret" ${ADDON_LITERAL_PARAMS} --dry-run="client" -o yaml | \
            jq '.data | to_entries | map({ id: .key , value: (.value | @base64d) }) | { addon: { id: "connectors-operator" }, parameters: { items : . }}' | \
            ${OCM} post "/api/clusters_mgmt/v1/clusters/${OCM_CLUSTER_ID}/addons"
    fi
else
    if [ "${MODE}" == "standalone" ] ; then
        ${OC} delete Addon 'connectors-operator' || true
    elif [ "${MODE}" == "ocm" ] ; then
        ADDON=$(${OCM} get "/api/clusters_mgmt/v1/clusters/${OCM_CLUSTER_ID}/addons/connectors-operator" 2>&1 || true)
        KIND=$(echo "${ADDON}" | jq -r .kind || true)

        if [ "${KIND}" == "Error" ] && [ "$(echo "${ADDON}" | jq -r .id || true)" == "404" ] ; then
            echo "OCM Addon not found, attempting to remove Addon CR"
            ${OC} delete Addon 'connectors-operator' || true
        else
            ${OCM} delete "/api/clusters_mgmt/v1/clusters/${OCM_CLUSTER_ID}/addons/connectors-operator" || true
        fi
    fi
fi
