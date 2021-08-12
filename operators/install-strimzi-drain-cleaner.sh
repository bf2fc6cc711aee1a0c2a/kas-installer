#!/bin/bash

OS=$(uname)
NAMESPACE=${STRIMZI_OPERATOR_NAMESPACE:-redhat-managed-kafka-operator}
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

if ! [ -d strimzi-drain-cleaner/resources/tmp ]; then
    mkdir strimzi-drain-cleaner/resources/tmp
fi

rm -rf strimzi-drain-cleaner/resources/tmp/*

${CP} -t strimzi-drain-cleaner/resources/tmp/ strimzi-drain-cleaner/resources/*.yaml

${SED} -i "s/namespace: .*/namespace: ${NAMESPACE}/" \
    strimzi-drain-cleaner/resources/tmp/*.yaml

# Create the namespace if it's not found
${KUBECTL} get ns ${NAMESPACE} >/dev/null \
  || ${KUBECTL} create ns ${NAMESPACE}

${KUBECTL} create -f strimzi-drain-cleaner/resources/tmp -n ${NAMESPACE}

echo "Waiting until Strimzi Drain Cleaner Deployment is available..."
${KUBECTL} wait --timeout=90s \
    --for=condition=available \
    deployment \
    --namespace=${NAMESPACE} \
    --selector app=strimzi-drain-cleaner

exit ${?}
