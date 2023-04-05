#!/bin/bash

set -Eeuo pipefail

DIR_NAME="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
source ${DIR_NAME}/../utils/common.sh
source ${DIR_NAME}/../kas-installer.env
source ${DIR_NAME}/../kas-installer-defaults.env
source ${DIR_NAME}/../kas-installer-runtime.env

ACTION=''
MODE=''

while [[ ${#} -gt 0 ]]; do
    case ${1} in
        "install" )
            ACTION="install"
            shift;
            ;;
        "uninstall" )
            ACTION="uninstall"
            shift;
            ;;
        "--mode" )
            MODE="${2}"
            shift; shift;
            ;;
        *)
            echo "Unknown option '${1}'";
            exit 1
            ;;
    esac
done

if [ -z "${ACTION}" ] ; then
    echo "Missing required action argument, one of 'install', 'uninstall'"
    exit 1
fi

if [ -z "${MODE}" ] ; then
    echo "Missing required '--mode' argument. Options are OCM or STANDALONE"
    exit 1
fi

if ! [[ "${MODE}" =~ ^(standalone|ocm)$ ]] ; then
    echo "Invalid value for '--mode': ${MODE}"
    exit 1
fi

if [ "${ACTION}" == 'install' ] ; then
    if ! [ -d "${DIR_NAME}/../cos-fleet-manager/cos-tools" ] ; then
        echo "cos-tools not found, cloning to cos-fleet-manager/cos-tools..."
        ${GIT} clone https://github.com/bf2fc6cc711aee1a0c2a/cos-tools.git "${DIR_NAME}/../cos-fleet-manager/cos-tools"
    fi

    COS_CLUSTER="$(${DIR_NAME}/cos_tool.sh "${DIR_NAME}/../cos-fleet-manager/cos-tools/bin/create-cluster" "test")"

    if [ "${MODE}" == "standalone" ] ; then
        NAMESPACE='redhat-openshift-connectors'
        COS_BASE_PATH="https://$(${OC} get route -l app=cos-fleet-manager -n ${COS_FLEET_MANAGER_NAMESPACE} -o json | jq -r '.items[].spec.host')"
        ACCESS_TOKEN="$(${DIR_NAME}/../get_access_token.sh --owner 2>/dev/null)"
        CLUSTER_ID="$(echo "${COS_CLUSTER}" | jq -r .id -)"

        if [ -z "$(${OC} get namespace/${NAMESPACE} -o jsonpath="{.metadata.name}" --ignore-not-found)" ]; then
            echo "K8s namespace ${NAMESPACE} does not exist. Creating it..."
            ${OC} create namespace ${NAMESPACE}
        fi

        ${DIR_NAME}/cos_tool.sh "${DIR_NAME}/../cos-fleet-manager/cos-tools/bin/create-cluster-secret" \
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
        continue
    fi
fi
