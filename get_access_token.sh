#!/bin/bash

DIR_NAME="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
${DIR_NAME}/bin/get_token.sh 'access_token' "${@}"
