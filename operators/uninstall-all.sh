#!/bin/bash

DIR_NAME="$(dirname $0)"

${DIR_NAME}/uninstall-kas-fleetshard.sh

${DIR_NAME}/uninstall-strimzi-cluster-operator.sh
