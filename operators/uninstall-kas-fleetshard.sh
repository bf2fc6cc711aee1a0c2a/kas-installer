#!/bin/bash

DIR_NAME="$(dirname $0)"
NAMESPACE=${KAS_FLEETSHARD_OPERATOR_NAMESPACE:-redhat-kas-fleetshard-operator}
KUBECTL=$(which kubectl)

${KUBECTL} delete managedkafkas --all --all-namespaces
${KUBECTL} delete managedkafkaagents --all --all-namespaces

CSV=$(${KUBECTL} get subscription kas-fleetshard-subscription -n ${NAMESPACE} -o json | jq -r '.status.installedCSV')
${KUBECTL} delete subscription kas-fleetshard-subscription -n ${NAMESPACE}
${KUBECTL} delete csv ${CSV} -n ${NAMESPACE}
${KUBECTL} delete operatorgroup kas-fleetshard-operator -n ${NAMESPACE}
${KUBECTL} delete catalogsource kas-fleetshard-catalog -n ${NAMESPACE}
${KUBECTL} delete -f ${DIR_NAME}/kas-fleetshard/resources -n ${NAMESPACE}
${KUBECTL} delete secret "rhoas-image-pull-secret" -n ${NAMESPACE}

# remove all CRDs
for c in $(${KUBECTL} get crd -l operators.coreos.com/kas-fleetshard-operator.redhat-kas-fleetshard-operator='' --no-headers | cut -d " " -f1); do
    ${KUBECTL} delete crd ${c}
done

exit 0
