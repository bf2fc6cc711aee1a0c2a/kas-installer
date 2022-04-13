#!/bin/bash

OS=$(uname)
NAMESPACE=${KAS_FLEETSHARD_OPERATOR_NAMESPACE:-redhat-kas-fleetshard-operator}
BUNDLE_IMAGE=${KAS_FLEETSHARD_OPERATOR_BUNDLE_IMAGE:-quay.io/osd-addons/rhoas-fleetshard-operator-bundle-index:v4.9-v1.0.0.e301eb9-2}
KUBECTL=$(which kubectl)
OC=$(which oc)

# Create the namespace if it's not found
${KUBECTL} get ns ${NAMESPACE} >/dev/null \
  || ${KUBECTL} create ns ${NAMESPACE}

${KUBECTL} create -f kas-fleetshard/resources -n ${NAMESPACE}

$OC process -f kas-fleetshard-bundle-template.yaml \
  -p BUNDLE_IMAGE=${BUNDLE_IMAGE} \
  -p NAMESPACE=${NAMESPACE} \
  -p NAMESPACE=MANAGEDKAFKA_ADMINSERVER_EDGE_TLS_ENABLED=${MANAGEDKAFKA_ADMINSERVER_EDGE_TLS_ENABLED-false} \
  | $OC create -f -

exit ${?}
