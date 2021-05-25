#!/bin/bash

FLEETSHARD_NS=kas-fleetshard

. _olm_setup.sh

export IMAGE_TAG="$1"

(cd kas-fleetshard/bundle/ && \
    echo "****** Creating bundle image: ${IMAGE_TAG}" && \
    docker build -t ${IMAGE_TAG} -f bundle.Dockerfile . && \
    echo "****** Pushing bundle image" && \
    docker push ${IMAGE_TAG} && \
    cd ../..)

kubectl get ns ${FLEETSHARD_NS}

if [ $? -ne 0 ] ; then
    echo "Creating Fleetshard namespace"
    kubectl create ns ${FLEETSHARD_NS}
fi

echo "****** Running bundle: ${IMAGE_TAG}"
${OPSDK} run bundle ${IMAGE_TAG} --install-mode=AllNamespaces --namespace=${FLEETSHARD_NS}
