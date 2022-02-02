#!/bin/bash

OS=$(uname)
KUBECTL=$(which kubectl)
DIR_NAME="$(dirname $0)"
if [ $(type -P "kcat") ]; then
  KCAT=$(which kcat)
fi

source ${DIR_NAME}/kas-installer.env
MK_EXISTING_ID=${1}
DELETE_INSTANCE='true'

if [ "$OS" = 'Darwin' ]; then
  # for MacOS
  DATE=$(which gdate)
else
  # for Linux and Windows
  DATE=$(which date)
fi

echo "Obtaining owner token"
OWNER_TOKEN=$(${DIR_NAME}/get_access_token.sh --owner 2>/dev/null)

if [ "${MK_EXISTING_ID:-}" != "" ] ; then
    DELETE_INSTANCE='false'
    MK_SMOKE=$(${DIR_NAME}/managed_kafka.sh --get ${MK_EXISTING_ID} --access-token ${OWNER_TOKEN})

    if [ ${?} -ne 0 ] || [ "$(echo ${MK_SMOKE} | jq -r .kind)" = "Error" ] ; then
        echo "Failed to get ManagedKafka instance for ID: ${MK_EXISTING_ID}"
        exit 1
    fi
else
    MK_SMOKE=$(${DIR_NAME}/managed_kafka.sh --create 'kafka-smoke' --access-token ${OWNER_TOKEN})

    if [ ${?} -ne 0 ] ; then
        echo "Failed to create a ManagedKafka instance"
        exit 1
    fi
fi

BOOTSTRAP_HOST=$(echo ${MK_SMOKE} | jq -r .bootstrap_server_host)
ADMIN_SERVER_HOST="admin-server-$(echo ${BOOTSTRAP_HOST} | cut -d':' -f 1)" # Remove the port
ADMIN_SERVER_SCHEME='https'

if [ "$(curl -s -o /dev/null -w "%{http_code}" http://${ADMIN_SERVER_HOST}/openapi)" = "200" ] ; then
    ADMIN_SERVER_SCHEME='http'
fi

SMOKE_TOPIC="smoke_topic-$(${DATE} +%Y%j%H%M)"

SERVICE_ACCOUNT_RESOURCE=$(${DIR_NAME}/service_account.sh --create --access-token ${OWNER_TOKEN})

if [ ${?} -ne 0 ] ; then
    echo "Failed to create a service account!"
    exit 1
else
    echo "Service account created"
fi

SA_ID=$(echo ${SERVICE_ACCOUNT_RESOURCE} | jq -r .id)
# MAS SSO (via KFM API) use different properties for client ID/secret than SSO directly. Support both forms here
SA_CLIENT_ID=$(echo ${SERVICE_ACCOUNT_RESOURCE} | jq -r '.client_id // .clientId')
SA_CLIENT_SECRET=$(echo ${SERVICE_ACCOUNT_RESOURCE} | jq -r '.client_secret // .secret')

if [ ${?} -ne 0 ] ; then
    echo "Failed obtain owner access token! Did you configure RH_USERNAME, RH_USER_ID, and RH_ORG_ID in kas-installer.env?"
    exit 1
fi

curl -f -skXPOST -H'Content-type: application/json' \
  -H "Authorization: Bearer ${OWNER_TOKEN}" \
  --data '{"resourceType":"TOPIC", "resourceName":"'${SMOKE_TOPIC}'", "patternType":"LITERAL", "principal":"User:'${SA_CLIENT_ID}'", "operation":"ALL", "permission":"ALLOW"}' \
  "${ADMIN_SERVER_SCHEME}://${ADMIN_SERVER_HOST}/api/v1/acls"

if [ ${?} -ne 0 ] ; then
    echo "Failed to grant topic permissions to service account!"
    exit 1
else
    echo "Granted service account access to topic '${SMOKE_TOPIC}'"
fi

ACCESS_TOKEN=$(${DIR_NAME}/get_access_token.sh ${SA_CLIENT_ID} ${SA_CLIENT_SECRET} 2>/dev/null)

if [ ${?} -ne 0 ] ; then
    echo "Failed to obtain an access token!"
    exit 1
else
    echo "Obtained access token for service account"
fi

SMOKE_TOPIC_INFO=$(curl -skXPOST -H'Content-type: application/json' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  --data '{ "name":"'${SMOKE_TOPIC}'", "settings": { "numPartitions":3, "config": [] } }' \
  "${ADMIN_SERVER_SCHEME}://${ADMIN_SERVER_HOST}/api/v1/topics")

MSG_FILE=$(mktemp)
SMOKE_MESSAGE="Smoke message from $(date)"
echo "${SMOKE_MESSAGE}" > ${MSG_FILE}

PARGS=()
CARGS=()
if [ "${KCAT}" ]; then
    CMD=${KCAT}
else
    CMD=docker
    PARGS=(run --rm --mount type=bind,source=${MSG_FILE},target=${MSG_FILE} --network=host edenhill/kcat:1.7.0)
    CARGS=(run --rm --network=host edenhill/kcat:1.7.0)
fi

${CMD} \
 ${PARGS[@]} \
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
 ${CARGS[@]} \
 -t "${SMOKE_TOPIC}" \
 -b "${BOOTSTRAP_HOST}" \
 -X security.protocol=SASL_SSL \
 -X sasl.mechanisms=PLAIN \
 -X sasl.username="${SA_CLIENT_ID}" \
 -X sasl.password="${SA_CLIENT_SECRET}" \
 -X enable.ssl.certificate.verification=false \
 -C -c1)

echo "Smoke message read from topic: [${SMOKE_MESSAGE_OUT}]"

if [ "${DELETE_INSTANCE}" = 'true' ] ; then
    MK_SMOKE_ID=$(echo ${MK_SMOKE} | jq -r .id)
    ${DIR_NAME}/managed_kafka.sh --delete ${MK_SMOKE_ID}
else
    TOPIC_DELETE_RESPONSE=$(curl -skXDELETE -H "Authorization: Bearer $ACCESS_TOKEN" "${ADMIN_SERVER_SCHEME}://${ADMIN_SERVER_HOST}/api/v1/topics/${SMOKE_TOPIC}")
    ACL_DELETE_RESPONSE=$(curl -skXDELETE -H "Authorization: Bearer ${OWNER_TOKEN}" \
        "${ADMIN_SERVER_SCHEME}://${ADMIN_SERVER_HOST}/api/v1/acls?principal=User:${SA_CLIENT_ID}")
fi

${DIR_NAME}/service_account.sh --delete ${SA_ID} --access-token ${OWNER_TOKEN}

if [ "${SMOKE_MESSAGE_OUT}" = "${SMOKE_MESSAGE}" ] ; then
    echo "Smoke test successful"
else
    echo "Failed smoke test: '${SMOKE_MESSAGE_OUT}' != '${SMOKE_MESSAGE}'"
fi
