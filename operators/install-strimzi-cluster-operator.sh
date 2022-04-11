#!/bin/bash

DIR_NAME="$(dirname $0)"
OS=$(uname)
NAMESPACE=${STRIMZI_OPERATOR_NAMESPACE:-redhat-managed-kafka-operator}
BUNDLE_IMAGE=${STRIMZI_OPERATOR_BUNDLE_IMAGE:-quay.io/osd-addons/rhosak-index@sha256:be31e47139581c1ad08254a0349887109e93bf7a84e47747f805186007240c13}
KUBECTL=$(which kubectl)
OC=$(which oc)

if [ "$OS" = 'Darwin' ]; then
  # for MacOS
  SED=$(which gsed)
else
  # for Linux and Windows
  SED=$(which sed)
fi

# Create the namespace if it's not found
${KUBECTL} get ns ${NAMESPACE} >/dev/null \
  || ${KUBECTL} create ns ${NAMESPACE}

$OC process -f ${DIR_NAME}/kas-strimzi-bundle-template.yaml -p BUNDLE_IMAGE=${BUNDLE_IMAGE} -p NAMESPACE=${NAMESPACE} | $OC apply -f -

exit ${?}
