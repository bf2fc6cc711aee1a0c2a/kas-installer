#!/bin/bash

./install-kas-fleetshard.sh &
FSO_PID=${!}

./install-strimzi-cluster-operator.sh &
STRIMZI_PID=${!}

cancel_func() {
  echo "Received signal, terminating sub processes ${FSO_PID} and ${STRIMZI_PID}"
  kill -TERM ${FSO_PID}
  kill -TERM ${STRIMZI_PID}
  exit 0
}

trap cancel_func SIGTERM SIGINT

wait ${FSO_PID}
wait ${STRIMZI_PID}
