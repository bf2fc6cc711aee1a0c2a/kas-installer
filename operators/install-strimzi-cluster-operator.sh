#!/bin/bash

OS=$(uname)
NAMESPACE=${STRIMZI_OPERATOR_NAMESPACE:-redhat-managed-kafka-operator}
BUNDLE_IMAGE=${STRIMZI_OPERATOR_BUNDLE_IMAGE:-quay.io\\\/mk-ci-cd\\\/kas-strimzi-bundle:index}
KUBECTL=$(which kubectl)

if [ "$OS" = 'Darwin' ]; then
  # for MacOS
  SED=$(which gsed)
  CP=$(which gcp)
else
  # for Linux and Windows
  SED=$(which sed)
  CP=$(which cp)
fi

if ! [ -d strimzi-cluster-operator/resources/tmp ]; then
    mkdir strimzi-cluster-operator/resources/tmp
fi

rm -rf strimzi-cluster-operator/resources/tmp/*

${CP} -t strimzi-cluster-operator/resources/tmp/ strimzi-cluster-operator/resources/*.yaml

${SED} -i "s/namespace: .*/namespace: ${NAMESPACE}/" \
    strimzi-cluster-operator/resources/tmp/*.yaml

# Create the namespace if it's not found
${KUBECTL} get ns ${NAMESPACE} >/dev/null \
  || ${KUBECTL} create ns ${NAMESPACE}

${SED} -i "s/image: .*/image: ${BUNDLE_IMAGE}/" \
    strimzi-cluster-operator/resources/tmp/*.yaml

${KUBECTL} create -f strimzi-cluster-operator/resources/tmp/kas-catalog-source.yaml
${KUBECTL} create -f strimzi-cluster-operator/resources/tmp/kas-strimzi-opgroup.yaml
${KUBECTL} create -f strimzi-cluster-operator/resources/tmp/kas-strimzi-subscription.yaml

exit ${?}
