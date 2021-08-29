#!/bin/bash
# Takes the secret produced by the fleetmanager kas-installer and uses that initialise the kas-fleetshard-operator-qe addon with the same parameters,
# Useful for testing dataplane addons with the kas-installer installed control plane.

set -e

if [ $# -ne 1 ]; then
    echo "$0: illegal number of parameters"
    echo "$0 <ocm cluster id>"
    exit 1
fi

id=$1

OS=$(uname)
NAMESPACE=${NAMESPACE:-redhat-kas-fleetshard-operator}
KUBECTL=$(which kubectl)
OCM=$(which ocm)

${KUBECTL} get secrets -n ${NAMESPACE}  addon-kas-fleetshard-operator-parameters -o json \
  | jq  '.data | to_entries |  map({id: .key , value: (.value | @base64d)}) | {addon: {id: "kas-fleetshard-operator-qe"}, parameters: {items : .}}' \
  | ${OCM} post "/api/clusters_mgmt/v1/clusters/${id}/addons" 

exit ${?}
