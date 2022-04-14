#!/bin/bash

DIR_NAME="$(dirname $0)"
source ${DIR_NAME}/../kas-installer.env
OS=$(uname)
NAMESPACE=${KAS_FLEETSHARD_OPERATOR_NAMESPACE:-redhat-kas-fleetshard-operator}
BUNDLE_IMAGE=${KAS_FLEETSHARD_OPERATOR_BUNDLE_IMAGE:-quay.io/osd-addons/rhosak-fleetshard-operator-bundle-index:v4.9-v1.0.0.efe8ba8-1}
OC=$(which oc)

# Create the namespace if it's not found
${OC} get ns ${NAMESPACE} >/dev/null || ${OC} create ns ${NAMESPACE}

${OC} create secret docker-registry "rhoas-image-pull-secret" -n ${NAMESPACE} \
  --docker-server="quay.io/osd-addons" \
  --docker-username=${IMAGE_REPOSITORY_USERNAME} \
  --docker-password=${IMAGE_REPOSITORY_PASSWORD}

${OC} create -f ${DIR_NAME}/kas-fleetshard/resources -n ${NAMESPACE}

${OC} process -f ${DIR_NAME}/kas-fleetshard-bundle-template.yaml \
  -p BUNDLE_IMAGE=${BUNDLE_IMAGE} \
  -p NAMESPACE=${NAMESPACE} \
  -p MANAGEDKAFKA_ADMINSERVER_EDGE_TLS_ENABLED=${MANAGEDKAFKA_ADMINSERVER_EDGE_TLS_ENABLED-false} \
  | ${OC} create -f -

DISPLAY_NAME="Fleetshard Operator"
SUBSCRIPTION_NAME=$(${OC} get subscriptions -n ${NAMESPACE} -o name)
CATALOG_SOURCE=$(${OC} get catalogsources -n ${NAMESPACE} -o name | awk -F/ '{ print $2 }')

echo "Waiting for healthy ${DISPLAY_NAME} CatalogSource..."
${OC} wait --for=condition=CatalogSourcesUnhealthy=False ${SUBSCRIPTION_NAME} --timeout=120s -n ${NAMESPACE} \
    && echo "${DISPLAY_NAME} is healthy" \
    || { echo "${DISPLAY_NAME} error" ; exit 1; }

if ${OC} wait --for=condition=Installed --all installplans --timeout=1s -n ${NAMESPACE} ; then
    echo "${DISPLAY_NAME} InstallPlan is installed..."
else
    echo "Waiting for ${DISPLAY_NAME} InstallPlanPending..."
    ${OC} wait --for=condition=InstallPlanPending=True ${SUBSCRIPTION_NAME} --timeout=120s -n ${NAMESPACE} \
        && echo "${DISPLAY_NAME} InstallPlan is pending" \
        || { echo "${DISPLAY_NAME} error" ; exit 1; }

    echo "Waiting until ${DISPLAY_NAME} InstallPlan is installed..."
    ${OC} wait --for=condition=Installed --all installplans --timeout=240s -n ${NAMESPACE} \
        && echo "${DISPLAY_NAME} InstallPlan installed" \
        || { echo "${DISPLAY_NAME} error" ; exit 1; }
fi

echo "Waiting until ${DISPLAY_NAME} deployments are available..."
${OC} wait --for=condition=available --all deployments --timeout=240s -n ${NAMESPACE} \
    && echo "${DISPLAY_NAME} deployments available" \
    || { echo "${DISPLAY_NAME} error" ; exit 1; }

exit ${?}
