#!/bin/bash

set -euo pipefail

DIR_NAME="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
source "${DIR_NAME}/utils/common.sh"

KI_CONFIG="${DIR_NAME}/kas-installer.env"
source ${KI_CONFIG}

mkdir -vp ${DIR_NAME}/certs

if ! [ -f ${DIR_NAME}/certs/ca-key.pem ] ; then
    ${OPENSSL} genrsa 4096 > ${DIR_NAME}/certs/ca-key.pem
    ${OPENSSL} req -new -x509 -nodes -days 365000 \
      -subj "/CN=kas-installer Root CA" \
      -key ${DIR_NAME}/certs/ca-key.pem \
      -out ${DIR_NAME}/certs/ca-cert.pem
fi

rm -vf \
  ${DIR_NAME}/certs/san.ext \
  ${DIR_NAME}/certs/server-key.pem \
  ${DIR_NAME}/certs/server-req.pem \
  ${DIR_NAME}/certs/server-cert.pem

echo "subjectAltName = DNS:*.kas.${K8S_CLUSTER_DOMAIN},DNS:*.kafka.bf2.dev,DNS:prod.foo.redhat.com" > ${DIR_NAME}/certs/san.ext

${OPENSSL} req -newkey rsa:2048 -nodes \
  -subj "/CN=*.kas.${K8S_CLUSTER_DOMAIN}" \
  -keyout ${DIR_NAME}/certs/server-key.pem \
  -out ${DIR_NAME}/certs/server-req.pem

${OPENSSL} x509 -req \
 -CA ${DIR_NAME}/certs/ca-cert.pem \
 -CAkey ${DIR_NAME}/certs/ca-key.pem \
 -extfile ${DIR_NAME}/certs/san.ext \
 -in ${DIR_NAME}/certs/server-req.pem \
 -out ${DIR_NAME}/certs/server-cert.pem \
 -days 365 \
 -CAcreateserial

cat ${DIR_NAME}/certs/server-cert.pem ${DIR_NAME}/certs/ca-cert.pem > ${DIR_NAME}/certs/cert-chain.pem
