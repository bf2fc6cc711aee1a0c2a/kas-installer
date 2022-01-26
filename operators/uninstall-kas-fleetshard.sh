#!/bin/bash

NAMESPACE=${KAS_FLEETSHARD_OPERATOR_NAMESPACE:-redhat-kas-fleetshard-operator}
KUBECTL=$(which kubectl)

${KUBECTL} delete kafkas --all --all-namespaces

CSV=$(${KUBECTL} get subscription kas-fleeshard-subscription -n ${NAMESPACE} -o json | jq -r '.status.installedCSV')
${KUBECTL} delete subscription kas-fleeshard-subscription -n ${NAMESPACE}
${KUBECTL} delete csv ${CSV} -n ${NAMESPACE}
${KUBECTL} delete operatorgroup kas-fleeshard-bundle -n ${NAMESPACE}
${KUBECTL} delete catalogsource kas-fleeshard-catalog -n ${NAMESPACE}
${KUBECTL} delete -f kas-fleetshard/resources -n ${NAMESPACE}

# remove all CRDs
for c in $(${KUBECTL} get crd -l operators.coreos.com/kas-fleetshard-operator.redhat-kas-fleetshard-operator='' --no-headers | cut -d " " -f1); do
    ${KUBECTL} delete crd ${c}
done

exit 0
