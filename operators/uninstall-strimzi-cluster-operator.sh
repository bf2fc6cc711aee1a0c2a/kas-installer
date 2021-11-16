#!/bin/bash

NAMESPACE=${STRIMZI_OPERATOR_NAMESPACE:-redhat-managed-kafka-operator}
KUBECTL=$(which kubectl)

${KUBECTL} delete kafkas --all --all-namespaces
${KUBECTL} delete clusterrolebinding strimzi-cluster-operator-namespaced
${KUBECTL} delete clusterrolebinding strimzi-cluster-operator-entity-operator-delegation
${KUBECTL} delete clusterrolebinding strimzi-cluster-operator-topic-operator-delegation

CSV=$(${KUBECTL} get subscription kas-strimzi-subscription -n ${NAMESPACE} -o json | jq -r '.status.installedCSV')
${KUBECTL} delete subscription kas-strimzi-subscription -n ${NAMESPACE}
${KUBECTL} delete csv ${CSV} -n ${NAMESPACE}
${KUBECTL} delete operatorgroup kas-strimzi-bundle -n ${NAMESPACE}
${KUBECTL} delete catalogsource kas-strimzi-catalog -n ${NAMESPACE}

# remove all CRDs
for c in $(${KUBECTL} get crd -l app=strimzi --no-headers | cut -d " " -f1); do
    ${KUBECTL} delete crd ${c}
done

exit 0
