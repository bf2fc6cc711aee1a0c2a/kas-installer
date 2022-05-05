#!/bin/bash

NAMESPACE=${KAS_FLEETSHARD_OPERATOR_NAMESPACE:-redhat-kas-fleetshard-operator}
KUBECTL=$(which kubectl)

${KUBECTL} delete managedkafkas --all --all-namespaces
${KUBECTL} delete managedkafkaagents --all --all-namespaces

CSV=$(${KUBECTL} get subscription -n ${NAMESPACE} -o json | jq -r '.items[0].status.installedCSV')
${KUBECTL} delete subscription --all -n ${NAMESPACE}
${KUBECTL} delete csv ${CSV} -n ${NAMESPACE}
${KUBECTL} delete operatorgroup --all -n ${NAMESPACE}
${KUBECTL} delete catalogsource --all -n ${NAMESPACE}
${KUBECTL} delete secret "rhoas-image-pull-secret" -n ${NAMESPACE}

# remove all CRDs
for c in $(${KUBECTL} get crd -l operators.coreos.com/kas-fleetshard-operator.redhat-kas-fleetshard-operator='' --no-headers | cut -d " " -f1); do
    ${KUBECTL} delete crd ${c}
done

exit 0
