#!/bin/bash

DIR_NAME="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
SCRIPT_PATH=${1:?path to cos-tools script is a required argument}
shift

if ! [ -f "${SCRIPT_PATH}" ] ; then
    echo "${SCRIPT_PATH}: file not found"
    exit 1
fi

SCRIPT=$(mktemp)
# Override `ocm` command to utilize the SSO environment configured by kas-installer
echo "ocm() { ${DIR_NAME}/get_access_token.sh --owner 2>/dev/null ; } ; source ${SCRIPT_PATH}" > ${SCRIPT}

chmod +x ${SCRIPT}

${SCRIPT} "${@}"

rm -f ${SCRIPT}
