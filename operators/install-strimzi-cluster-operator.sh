#!/bin/bash

OS=$(uname)
NAMESPACE=${STRIMZI_OPERATOR_NAMESPACE:-redhat-managed-kafka-operator}
BUNDLE_IMAGE=${STRIMZI_OPERATOR_BUNDLE_IMAGE:-quay.io/osd-addons/rhosak-index@sha256:5dc60972abcec63bc2b584123f950cb6869bcb8718b6d12a9832de86b07ac699}
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

$OC process -f kas-strimzi-bundle-template.yaml -p BUNDLE_IMAGE=${BUNDLE_IMAGE} -p NAMESPACE=${NAMESPACE} | $OC apply -f -

exit ${?}
