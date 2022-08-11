#!/bin/bash

set -euo pipefail

DIR_NAME="$(dirname $0)"

source "${DIR_NAME}/utils/common.sh"

if [ $(type -P "kcat") ]; then
  KCAT=$(which kcat)
else
  KCAT=''
fi

source ${DIR_NAME}/kas-installer.env
MK_EXISTING_ID=${1:-}

function cleanup()
{
    if [[ "${CREATED_MK_ID:-}" ]] ; then
        ${DIR_NAME}/managed_kafka.sh --delete ${CREATED_MK_ID}
    elif [[ "${SMOKE_TOPIC:-}" ]] ; then
        curl -skXDELETE -H "Authorization: Bearer ${ACCESS_TOKEN}" "${ADMIN_SERVER_URL}/api/v1/topics/${SMOKE_TOPIC}" || true
        curl -skXDELETE -H "Authorization: Bearer ${OWNER_TOKEN}"  "${ADMIN_SERVER_URL}/api/v1/acls?principal=User:${SA_CLIENT_ID}" || true
    fi

    if [[ "${SA_ID:-}" ]] ; then
        ${DIR_NAME}/service_account.sh --delete "${SA_ID}" --access-token ${OWNER_TOKEN}
    fi
}

trap cleanup EXIT

echo "Obtaining owner token"
OWNER_TOKEN=$(${DIR_NAME}/get_access_token.sh --owner 2>/dev/null)

echo "Creating service account"
SERVICE_ACCOUNT_RESOURCE=$(${DIR_NAME}/service_account.sh --create --access-token ${OWNER_TOKEN})
SA_ID=$(echo ${SERVICE_ACCOUNT_RESOURCE} | jq -r .id)
echo "Service account created: ${SA_ID}"

# MAS SSO (via KFM API) use different properties for client ID/secret than SSO directly. Support both forms here
SA_CLIENT_ID=$(echo ${SERVICE_ACCOUNT_RESOURCE} | jq -r '.client_id // .clientId')
SA_CLIENT_SECRET=$(echo ${SERVICE_ACCOUNT_RESOURCE} | jq -r '.client_secret // .secret')

echo "Obtaining access token for service account"
ACCESS_TOKEN=$(${DIR_NAME}/get_access_token.sh ${SA_CLIENT_ID} ${SA_CLIENT_SECRET} 2>/dev/null)

if [ "${MK_EXISTING_ID:-}" != "" ] ; then
    MK_SMOKE=$(${DIR_NAME}/managed_kafka.sh --get ${MK_EXISTING_ID} --access-token ${OWNER_TOKEN})
else
    MK_SMOKE=$(${DIR_NAME}/managed_kafka.sh --create 'kafka-smoke' --access-token ${OWNER_TOKEN})
    CREATED_MK_ID=$(echo ${MK_SMOKE} | jq -r .id)
fi

BOOTSTRAP_HOST=$(echo ${MK_SMOKE} | jq -r .bootstrap_server_host)
ADMIN_SERVER_URL=$(echo ${MK_SMOKE} | jq -r .admin_api_server_url)

SMOKE_TOPIC="smoke_topic-$(${DATE} +%Y%j%H%M)"

curl -f -skXPOST -H'Content-type: application/json' \
  -H "Authorization: Bearer ${OWNER_TOKEN}" \
  --data '{"resourceType":"TOPIC", "resourceName":"'${SMOKE_TOPIC}'", "patternType":"LITERAL", "principal":"User:'${SA_CLIENT_ID}'", "operation":"ALL", "permission":"ALLOW"}' \
  "${ADMIN_SERVER_URL}/api/v1/acls"

echo "Granted service account access to topic '${SMOKE_TOPIC}'"

SMOKE_TOPIC_INFO=$(curl -skXPOST -H'Content-type: application/json' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  --data '{ "name":"'${SMOKE_TOPIC}'", "settings": { "numPartitions":3, "config": [] } }' \
  "${ADMIN_SERVER_URL}/api/v1/topics")

MSG_FILE=$(mktemp)
SMOKE_MESSAGE="Smoke message from $(date)"
echo "${SMOKE_MESSAGE}" > ${MSG_FILE}

PARGS=()
CARGS=()
if [ "${KCAT}" ]; then
    CMD=${KCAT}
    PARGS=()
    CARGS=()
else
    CMD=docker
    PARGS=(run --rm --mount type=bind,source=${MSG_FILE},target=${MSG_FILE} --network=host edenhill/kcat:1.7.0)
    CARGS=(run --rm --network=host edenhill/kcat:1.7.0)
fi

${CMD} \
 ${PARGS[@]+"${PARGS[@]}"} \
 -t "${SMOKE_TOPIC}" \
 -b "${BOOTSTRAP_HOST}" \
 -X security.protocol=SASL_SSL \
 -X sasl.mechanisms=PLAIN \
 -X sasl.username="${SA_CLIENT_ID}" \
 -X sasl.password="${SA_CLIENT_SECRET}" \
 -X enable.ssl.certificate.verification=false \
 -P -l ${MSG_FILE}

rm ${MSG_FILE}

echo "Smoke message sent to topic: [${SMOKE_MESSAGE}]"

SMOKE_MESSAGE_OUT=$(${CMD} \
 ${CARGS[@]+"${CARGS[@]}"} \
 -t "${SMOKE_TOPIC}" \
 -b "${BOOTSTRAP_HOST}" \
 -X security.protocol=SASL_SSL \
 -X sasl.mechanisms=PLAIN \
 -X sasl.username="${SA_CLIENT_ID}" \
 -X sasl.password="${SA_CLIENT_SECRET}" \
 -X enable.ssl.certificate.verification=false \
 -C -c1)

echo "Smoke message read from topic: [${SMOKE_MESSAGE_OUT}]"

if [ "${SMOKE_MESSAGE_OUT}" = "${SMOKE_MESSAGE}" ] ; then
    echo "Smoke test successful"
else
    echo "Failed smoke test: '${SMOKE_MESSAGE_OUT}' != '${SMOKE_MESSAGE}'"
fi
