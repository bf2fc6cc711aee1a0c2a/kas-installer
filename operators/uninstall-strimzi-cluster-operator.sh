#!/bin/bash

STRIMZI_NS=strimzi-cluster-operator

. _olm_setup.sh

${OPSDK} cleanup strimzi-cluster-operator --delete-all --namespace=${STRIMZI_NS}
