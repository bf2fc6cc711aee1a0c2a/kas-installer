#!/bin/bash

DIR_NAME="$(dirname $0)"
source ${DIR_NAME}/../kas-installer.env
OS=$(uname)
NAMESPACE=${STRIMZI_OPERATOR_NAMESPACE:-redhat-managed-kafka-operator}
BUNDLE_IMAGE=${STRIMZI_OPERATOR_BUNDLE_IMAGE:-quay.io/osd-addons/rhosak-index@sha256:be31e47139581c1ad08254a0349887109e93bf7a84e47747f805186007240c13}
OC=$(which oc)

# Create the namespace if it's not found
${OC} get ns ${NAMESPACE} >/dev/null || ${OC} create ns ${NAMESPACE}

${OC} create secret docker-registry "rhoas-image-pull-secret" -n ${NAMESPACE} \
  --docker-server="quay.io/osd-addons" \
  --docker-username=${IMAGE_REPOSITORY_USERNAME} \
  --docker-password=${IMAGE_REPOSITORY_PASSWORD}

${OC} process -f ${DIR_NAME}/kas-strimzi-bundle-template.yaml \
  -p BUNDLE_IMAGE=${BUNDLE_IMAGE} \
  -p NAMESPACE=${NAMESPACE} \
  | ${OC} apply -f -

exit ${?}
