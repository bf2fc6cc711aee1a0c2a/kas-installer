#!/bin/bash

NAMESPACE=${STRIMZI_OPERATOR_NAMESPACE:-redhat-managed-kafka-operator}
KUBECTL=$(which kubectl)

${KUBECTL} delete clusterrolebinding strimzi-cluster-operator-namespaced
${KUBECTL} delete clusterrolebinding strimzi-cluster-operator-entity-operator-delegation
${KUBECTL} delete clusterrolebinding strimzi-cluster-operator-topic-operator-delegation
${KUBECTL} delete -f strimzi-cluster-operator/resources/security/tmp -n ${NAMESPACE}
${KUBECTL} delete -f strimzi-cluster-operator/resources -n ${NAMESPACE}
