#!/bin/bash

NAMESPACE=${KAS_FLEETSHARD_OPERATOR_NAMESPACE:-redhat-kas-fleetshard-operator}
KUBECTL=$(which kubectl)

${KUBECTL} delete managedkafkas --all --all-namespaces --wait
${KUBECTL} delete managedkafkaagents --all --all-namespaces --wait
${KUBECTL} delete -f kas-fleetshard/resources -n ${NAMESPACE}
${KUBECTL} delete clusterrolebinding kas-fleetshard-operator
${KUBECTL} delete clusterrolebinding kas-fleetshard-sync

exit 0
