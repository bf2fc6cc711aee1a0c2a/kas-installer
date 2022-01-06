#!/bin/bash

OS=$(uname)
NAMESPACE=${KAS_FLEETSHARD_OPERATOR_NAMESPACE:-redhat-kas-fleetshard-operator}
BUNDLE_IMAGE=${KAS_FLEETSHARD_OPERATOR_BUNDLE_IMAGE:-quay.io/osd-addons/kas-fleetshard-operator-index@sha256:83f2727cb660185d50a2f724d6cbf3d3e311a4d7f9daaf33c820ddc0caac51e5}
KUBECTL=$(which kubectl)
OC=$(which oc)

if [ "$OS" = 'Darwin' ]; then
  # for MacOS
  SED=$(which gsed)
else
  # for Linux and Windows
  SED=$(which sed)
fi

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
