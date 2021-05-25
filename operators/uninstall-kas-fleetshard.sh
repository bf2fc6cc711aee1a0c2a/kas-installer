#!/bin/bash

FLEETSHARD_NS=kas-fleetshard

. _olm_setup.sh

${OPSDK} cleanup kas-fleetshard --delete-all --namespace=${FLEETSHARD_NS}
