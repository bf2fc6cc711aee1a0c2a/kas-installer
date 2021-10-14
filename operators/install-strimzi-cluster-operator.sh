#!/bin/bash

OS=$(uname)
NAMESPACE=${STRIMZI_OPERATOR_NAMESPACE:-redhat-managed-kafka-operator}
BUNDLE_IMAGE=${STRIMZI_OPERATOR_BUNDLE_IMAGE:-quay.io\\\/mk-ci-cd\\\/kas-strimzi-bundle:index}
KUBECTL=$(which kubectl)

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

CATALOG_SOURCE_YAML=$(< strimzi-cluster-operator/kas-catalog-source.yaml)

echo "$CATALOG_SOURCE_YAML" | sed "s/image: .*/image: ${BUNDLE_IMAGE}/" | ${KUBECTL} create -n ${NAMESPACE} -f -
${KUBECTL} create -f strimzi-cluster-operator/kas-strimzi-opgroup.yaml -n ${NAMESPACE}
${KUBECTL} create -f strimzi-cluster-operator/kas-strimzi-subscription.yaml -n ${NAMESPACE}

exit ${?}
