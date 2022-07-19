#!/bin/bash

set -euo pipefail

DIR_NAME="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
KI_CONFIG="${DIR_NAME}/../kas-installer.env"
source ${KI_CONFIG}
source "${DIR_NAME}/../utils/common.sh"
source "${DIR_NAME}/ui-common.sh"

remove() {
    ${CONTAINER_CLI} rm -f ${1} || true
}

remove 'kas-installer-app-services-ui'
remove 'kas-installer-kas-ui'
remove 'kas-installer-kafka-ui'

if [[ ${CONTAINER_CLI} == *podman ]] ; then
    ${CONTAINER_CLI} pod rm kas-installer-ui || true
fi
