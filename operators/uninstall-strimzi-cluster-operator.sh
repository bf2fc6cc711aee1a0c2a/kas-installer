#!/bin/bash

NAMESPACE=${STRIMZI_OPERATOR_NAMESPACE:-redhat-managed-kafka-operator}
KUBECTL=$(which kubectl)

${KUBECTL} delete kafkas --all --all-namespaces

CSV=$(${KUBECTL} get subscription -n ${NAMESPACE} -o json | jq -r '.items[0].status.installedCSV')
${KUBECTL} delete subscription --all -n ${NAMESPACE}
${KUBECTL} delete csv ${CSV} -n ${NAMESPACE}
${KUBECTL} delete operatorgroup --all -n ${NAMESPACE}
${KUBECTL} delete catalogsource --all -n ${NAMESPACE}
${KUBECTL} delete secret "rhoas-image-pull-secret" -n ${NAMESPACE}

# remove all CRDs
for c in $(${KUBECTL} get crd -l app=strimzi --no-headers | cut -d " " -f1); do
    ${KUBECTL} delete crd ${c}
done

exit 0
