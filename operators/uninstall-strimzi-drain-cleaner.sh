#!/bin/bash

NAMESPACE=${STRIMZI_OPERATOR_NAMESPACE:-redhat-managed-kafka-operator}
KUBECTL=$(which kubectl)

${KUBECTL} delete -f strimzi-drain-cleaner/resources/tmp -n ${NAMESPACE}

exit 0
