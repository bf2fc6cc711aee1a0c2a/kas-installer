#!/bin/bash

NAMESPACE=${KAS_FLEETSHARD_OPERATOR_NAMESPACE:-redhat-kas-fleetshard-operator}
KUBECTL=$(which kubectl)

${KUBECTL} delete -f kas-fleetshard/resources -n ${NAMESPACE}
${KUBECTL} delete ns ${NAMESPACE}
${KUBECTL} delete clusterrolebinding kas-fleetshard-operator
${KUBECTL} delete clusterrolebinding kas-fleetshard-sync
