#!/bin/bash
# Installs the managed-kafka-operator

set -e

if [ $# -ne 1 ]; then
    echo "$0: illegal number of parameters"
    echo "$0 <ocm cluster id>"
    exit 1
fi

id=$1

OS=$(uname)
KUBECTL=$(which kubectl)
OCM=$(which ocm)

jq --null-input '{addon: {id: "managed-kafka-qe"}}' | ${OCM} post "/api/clusters_mgmt/v1/clusters/${id}/addons" 

exit ${?}
