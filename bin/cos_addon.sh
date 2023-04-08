#!/bin/bash

set -Eeuo pipefail

DIR_NAME="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
source ${DIR_NAME}/../utils/common.sh
source ${DIR_NAME}/../kas-installer.env
source ${DIR_NAME}/../kas-installer-defaults.env
source ${DIR_NAME}/../kas-installer-runtime.env
COS_TOOLS="${DIR_NAME}/cos-tools"

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

if ! [ -d "${COS_TOOLS}" ] ; then
    echo "cos-tools not found, cloning to ${COS_TOOLS}..."
    ${GIT} clone https://github.com/bf2fc6cc711aee1a0c2a/cos-tools.git "${COS_TOOLS}"
fi

MODE=''

if [ -n "${OCM_SERVICE_TOKEN-""}" ] && [ -n "${OCM_CLUSTER_ID-""}" ] && [ "${CONNECTORS_ADDON_STANDALONE:-"false"}" != "true" ] ; then
    MODE='ocm'
else
    MODE='standalone'
fi

if [ "${ACTION}" == 'install' ] ; then
    if [ "${MODE}" == "standalone" ] ; then
        NAMESPACE='redhat-openshift-connectors'

        if [ -z "$(${OC} get namespace/${NAMESPACE} -o jsonpath="{.metadata.name}" --ignore-not-found)" ]; then
            echo "K8s namespace ${NAMESPACE} does not exist. Creating it..."
            ${OC} create namespace ${NAMESPACE}
        fi

        ${DIR_NAME}/cos_tool.sh "${COS_TOOLS}/bin/create-cluster-secret" \
          "${CLUSTER_ID}" \
          "addon-connectors-operator-parameters" \
          "${NAMESPACE}"

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
        ACCESS_TOKEN=$(${DIR_NAME}/../get_access_token.sh --owner 2>/dev/null)

        literals=$(curl -L --insecure --oauth2-bearer "${ACCESS_TOKEN}" -S -s https://"${MAS_FLEET_MANAGEMENT_DOMAIN}"/api/connector_mgmt/v1/kafka_connector_clusters/"${CLUSTER_ID}"/addon_parameters \
            | jq -r 'map("--from-literal=\(.id)=\(.value|tostring)") | join(" ")')

        ${OC} create secret generic "add-secret" ${literals} --dry-run="client" -o yaml | \
            jq  '.data | to_entries | map({ id: .key , value: (.value | @base64d) }) | { addon: { id: "connectors-operator" }, parameters: { items : . }}' \
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
