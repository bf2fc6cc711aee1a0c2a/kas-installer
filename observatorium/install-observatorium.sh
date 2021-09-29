#!/bin/bash

OBSERVATORIUM_NAMESPACE=${OBSERVATORIUM_NAMESPACE:-observatorium}
DEX_NAMESPACE=${DEX_NAMESPACE:-dex}
MINIO_NAMESPACE=${MINIO_NAMESPACE:-observatorium-minio}
GRAFANA_NAMESPACE=${GRAFANA_NAMESPACE:-managed-application-services-observability}
OC=$(which oc)

cat observatorium/resources/dex/dev/config.yaml > observatorium/resources/dex/dev/config.generated.yaml
${OC} kustomize observatorium/resources/dex/dev |sed "s/<namespace>/${DEX_NAMESPACE}/g" |${OC} apply -f -

${OC} kustomize observatorium/resources/minio/dev |sed "s/<namespace>/${MINIO_NAMESPACE}/g" |${OC} apply -f -

${OC} kustomize observatorium/resources/operator/bases |sed "s/<namespace>/${OBSERVATORIUM_NAMESPACE}/g" |${OC} apply -f -

 for i in {1..12}; do 
  ${OC} -n ${OBSERVATORIUM_NAMESPACE} get pod -l control-plane=observatorium-operator -o name | grep "pod/observatorium-operator" && break 
  sleep 5; 
done

cat observatorium/resources/observatorium/dev/thanos.yaml  > observatorium/resources/observatorium/dev/thanos.generated.yaml
${OC} kustomize observatorium/resources/observatorium/dev |sed "s/<namespace>/${OBSERVATORIUM_NAMESPACE}/g;s/<hosturl>/${OBSERVATORIUM_ROUTE_HOST}/g" |oc apply -f -

#
