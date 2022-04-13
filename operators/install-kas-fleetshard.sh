#!/bin/bash

DIR_NAME="$(dirname $0)"
source ${DIR_NAME}/../kas-installer.env
OS=$(uname)
NAMESPACE=${KAS_FLEETSHARD_OPERATOR_NAMESPACE:-redhat-kas-fleetshard-operator}
BUNDLE_IMAGE=${KAS_FLEETSHARD_OPERATOR_BUNDLE_IMAGE:-quay.io/osd-addons/rhoas-fleetshard-operator-bundle-index:v4.9-v1.0.0.e301eb9-2}
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

exit ${?}
