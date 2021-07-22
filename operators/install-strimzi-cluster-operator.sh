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

if ! [ -d strimzi-cluster-operator/resources/security/tmp ]; then
    mkdir strimzi-cluster-operator/resources/security/tmp
fi

rm -rf strimzi-cluster-operator/resources/security/tmp/*

${CP} -t strimzi-cluster-operator/resources/security/tmp/ strimzi-cluster-operator/resources/security/*.yaml

${SED} -i "s/namespace: .*/namespace: ${NAMESPACE}/" \
    strimzi-cluster-operator/resources/security/tmp/*RoleBinding*.yaml

# Create the namespace if it's not found
${KUBECTL} get ns ${NAMESPACE} >/dev/null \
  || ${KUBECTL} create ns ${NAMESPACE}

${KUBECTL} create clusterrolebinding strimzi-cluster-operator-namespaced \
    --clusterrole=strimzi-cluster-operator-namespaced \
    --serviceaccount ${NAMESPACE}:strimzi-cluster-operator
${KUBECTL} label clusterrolebinding strimzi-cluster-operator-namespaced app=strimzi

${KUBECTL} create clusterrolebinding strimzi-cluster-operator-entity-operator-delegation \
    --clusterrole=strimzi-entity-operator \
    --serviceaccount ${NAMESPACE}:strimzi-cluster-operator
${KUBECTL} label clusterrolebinding strimzi-cluster-operator-entity-operator-delegation app=strimzi

${KUBECTL} create clusterrolebinding strimzi-cluster-operator-topic-operator-delegation \
    --clusterrole=strimzi-topic-operator \
    --serviceaccount ${NAMESPACE}:strimzi-cluster-operator
${KUBECTL} label clusterrolebinding strimzi-cluster-operator-topic-operator-delegation app=strimzi

${KUBECTL} create -f strimzi-cluster-operator/resources/security/tmp -n ${NAMESPACE}
${KUBECTL} create -f strimzi-cluster-operator/resources -n ${NAMESPACE}

echo "Waiting until Strimzi Deployment is available..."
${KUBECTL} wait --timeout=90s \
    --for=condition=available \
    deployment \
    --namespace=${NAMESPACE} \
    --selector app=strimzi

exit ${?}
