#!/bin/bash

set -euo pipefail

DIR_NAME="$(dirname $0)"
source "${DIR_NAME}/utils/common.sh"
source "${DIR_NAME}/kas-installer.env"
source "${DIR_NAME}/kas-installer-defaults.env"

CLUSTER_ID="${1:-""}"
ACCESS_TOKEN="$(${DIR_NAME}/get_access_token.sh --owner 2>/dev/null)"
CLUSTERS_BASE_URL="https://kas-fleet-manager-kas-fleet-manager-${USER}.apps.${K8S_CLUSTER_DOMAIN}/api/kafkas_mgmt/v1/clusters"

if [ -z "${CLUSTER_ID}" ] ; then
    CLUSTERS=$(curl -sXGET -H "Authorization: Bearer ${ACCESS_TOKEN}" ${CLUSTERS_BASE_URL})
    CLUSTER_COUNT=$(echo "${CLUSTERS}" | jq -r .total)

    if [ "${CLUSTER_COUNT}" -eq "0" ] ; then
        echo "No clusters found to deregister"
        exit 1
    elif [ "${CLUSTER_COUNT}" -gt "1" ] ; then
        echo "Multiple clusters found, please provide a cluster_id"
        exit 1
    else
        CLUSTER_ID=$(echo "${CLUSTERS}" | jq -r .items[0].cluster_id)
        echo "Single cluster found: ${CLUSTER_ID}"
    fi
fi

for MKID in $(${DIR_NAME}/managed_kafka.sh --list | jq -r '.items[] | select(.cluster_id == "'${CLUSTER_ID}'") | .id') ; do
    echo "Removing Kafka instance ${MKID}"
    ${DIR_NAME}/managed_kafka.sh --delete ${MKID} --wait
done

echo "De-registering cluster ${CLUSTER_ID} from kas-fleet-manager"
curl -sXDELETE -H "Authorization: Bearer ${ACCESS_TOKEN}" ${CLUSTERS_BASE_URL}/${CLUSTER_ID}?async=true

delete_dataplane_resources 'true' 'true' "${CLUSTER_ID}"
