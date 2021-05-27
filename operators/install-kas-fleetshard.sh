#!/bin/bash

NAMESPACE=${KAS_FLEETSHARD_OPERATOR_NAMESPACE:-redhat-kas-fleetshard-operator}
KUBECTL=$(which kubectl)

${KUBECTL} create ns ${NAMESPACE}
${KUBECTL} create -f kas-fleetshard/resources -n ${NAMESPACE}

${KUBECTL} create clusterrolebinding kas-fleetshard-operator \
    --clusterrole=kas-fleetshard-operator \
    --serviceaccount ${NAMESPACE}:kas-fleetshard-operator

${KUBECTL} create clusterrolebinding kas-fleetshard-sync \
    --clusterrole=kas-fleetshard-sync \
    --serviceaccount ${NAMESPACE}:kas-fleetshard-sync

echo "Waiting until KAS Fleet Shard Deployment is available..."
${KUBECTL} wait --timeout=90s \
    --for=condition=available \
    deployment/kas-fleetshard-operator \
    --namespace=${NAMESPACE}

exit ${?}
