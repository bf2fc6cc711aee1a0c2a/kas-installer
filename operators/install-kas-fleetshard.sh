#!/bin/bash

NAMESPACE=${KAS_FLEETSHARD_OPERATOR_NAMESPACE:-redhat-kas-fleetshard-operator}
KUBECTL=$(which kubectl)

${KUBECTL} create ns ${NAMESPACE}
${KUBECTL} create -f kas-fleetshard/resources -n ${NAMESPACE}

if [[ ${MANAGEDKAFKA_ADMINSERVER_EDGE_TLS_ENABLED-false} == "true" ]];
then 
    ${KUBECTL} set env deployment/kas-fleetshard-operator -n ${NAMESPACE} MANAGEDKAFKA_ADMINSERVER_EDGE_TLS_ENABLED=true
fi

${KUBECTL} create clusterrolebinding kas-fleetshard-operator \
    --clusterrole=kas-fleetshard-operator \
    --serviceaccount ${NAMESPACE}:kas-fleetshard-operator

${KUBECTL} create clusterrolebinding kas-fleetshard-sync \
    --clusterrole=kas-fleetshard-sync \
    --serviceaccount ${NAMESPACE}:kas-fleetshard-sync

echo "Waiting until KAS Fleet Shard Deployment is available..."
${KUBECTL} wait --timeout=90s \
    --for=condition=available \
    deployment/kas-fleetshard-operator \
    --namespace=${NAMESPACE}

if [ -n "${SSO_TRUSTED_CA:-}" ] ; then
    CRT_FILE=$(mktemp)
    echo "${SSO_TRUSTED_CA}" > ${CRT_FILE}.pem

    keytool -import \
      -file ${CRT_FILE}.pem \
      -keystore ${CRT_FILE}.p12 \
      -storepass changeit\
      -alias sso-ca \
      -noprompt

    ${KUBECTL} delete secret sync-sso-tls-config -n ${NAMESPACE} 2>/dev/null || true

    ${KUBECTL} create secret generic \
      sync-sso-tls-config \
      -n ${NAMESPACE} \
      --from-file=sso-trust.p12=${CRT_FILE}.p12

    rm ${CRT_FILE} ${CRT_FILE}.pem ${CRT_FILE}.p12

    ${KUBECTL} set env \
      deployment/kas-fleetshard-sync \
      -n ${NAMESPACE} \
      QUARKUS_OIDC_CLIENT_TLS_TRUST_STORE_FILE=/config-sso-tls/sso-trust.p12 \
      QUARKUS_OIDC_CLIENT_TLS_TRUST_STORE_PASSWORD=changeit
fi

exit ${?}
