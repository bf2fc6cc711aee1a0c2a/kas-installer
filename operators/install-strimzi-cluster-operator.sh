#!/bin/bash

OS=$(uname)
NAMESPACE=${STRIMZI_OPERATOR_NAMESPACE:-redhat-managed-kafka-operator}
BUNDLE_IMAGE=${STRIMZI_OPERATOR_BUNDLE_IMAGE:-quay.io/osd-addons/rhosak-index@sha256:7835ce6fcdbd3d5c1317f762ffc4dd90eaacc852cefd9de1c8ce036e1c1d3bc9}
KUBECTL=$(which kubectl)
OC=$(which oc)


# Create the namespace if it's not found
${KUBECTL} get ns ${NAMESPACE} >/dev/null \
  || ${KUBECTL} create ns ${NAMESPACE}

$OC process -f kas-strimzi-bundle-template.yaml -p BUNDLE_IMAGE=${BUNDLE_IMAGE} -p NAMESPACE=${NAMESPACE} | $OC apply -f -

exit ${?}
