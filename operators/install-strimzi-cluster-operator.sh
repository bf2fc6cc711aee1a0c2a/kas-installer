#!/bin/bash

STRIMZI_NS=strimzi-cluster-operator

. _olm_setup.sh

export IMAGE_TAG="$1"

(cd strimzi-cluster-operator/bundle/ && \
    echo "****** Creating bundle image: ${IMAGE_TAG}" && \
    docker build -t ${IMAGE_TAG} -f bundle.Dockerfile . && \
    echo "****** Pushing bundle image" && \
    docker push ${IMAGE_TAG} && \
    cd ../..)

kubectl get ns ${STRIMZI_NS}

if [ $? -ne 0 ] ; then
    echo "Creating Strimzi namespace"
    kubectl create ns ${STRIMZI_NS}
fi

echo "****** Running bundle: ${IMAGE_TAG}"
${OPSDK} run bundle ${IMAGE_TAG} --install-mode=AllNamespaces --namespace=${STRIMZI_NS}
