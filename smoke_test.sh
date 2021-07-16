#!/bin/bash

KUBECTL=$(which kubectl)
DIR_NAME="$(dirname $0)"
source ${DIR_NAME}/kas-installer.env

MK_SMOKE=$(${DIR_NAME}/managed_kafka.sh --create 'kafka-smoke')

if [ ${?} -ne 0 ] ; then
    echo "Failed to create a ManagedKafka instance"
    exit 1
fi

SERVICE_ACCOUNT_RESOURCE=$(${DIR_NAME}/service_account.sh --create)

if [ ${?} -ne 0 ] ; then
    echo "Failed to create a service account!"
    exit 1
fi

SA_ID=$(echo ${SERVICE_ACCOUNT_RESOURCE} | jq -r .id)
SA_CLIENT_ID=$(echo ${SERVICE_ACCOUNT_RESOURCE} | jq -r .client_id)
SA_CLIENT_SECRET=$(echo ${SERVICE_ACCOUNT_RESOURCE} | jq -r .client_secret)

ACCESS_TOKEN=$(${DIR_NAME}/get_access_token.sh ${SA_CLIENT_ID} ${SA_CLIENT_SECRET})

if [ ${?} -ne 0 ] ; then
    echo "Failed to obtain an access token!"
    exit 1
fi

BOOTSTRAP_HOST=$(echo ${MK_SMOKE} | jq -r .bootstrap_server_host)
ADMIN_SERVER_HOST="admin-server-$(echo ${BOOTSTRAP_HOST} | cut -d':' -f 1)" # Remove the port
SMOKE_TOPIC="smoke_topic"

curl -sXPOST -H'Content-type: application/json' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  --data '{ "name":"'${SMOKE_TOPIC}'", "settings": { "numPartitions":3, "config": [] } }' \
  "http://${ADMIN_SERVER_HOST}/rest/topics"

MSG_FILE=$(mktemp)
SMOKE_MESSAGE="Smoke message from $(date)"
echo "${SMOKE_MESSAGE}" > ${MSG_FILE}

docker run --rm --mount type=bind,source=${MSG_FILE},target=${MSG_FILE} --network=host edenhill/kafkacat:1.6.0 \
 -t "${SMOKE_TOPIC}" \
 -b "${BOOTSTRAP_HOST}" \
 -X security.protocol=SASL_SSL \
 -X sasl.mechanisms=PLAIN \
 -X sasl.username="${SA_CLIENT_ID}" \
 -X sasl.password="${SA_CLIENT_SECRET}" \
 -X enable.ssl.certificate.verification=false \
 -P -l ${MSG_FILE}

rm ${MSG_FILE}

SMOKE_MESSAGE_OUT=$(docker run --rm --network=host edenhill/kafkacat:1.6.0 \
 -t "${SMOKE_TOPIC}" \
 -b "${BOOTSTRAP_HOST}" \
 -X security.protocol=SASL_SSL \
 -X sasl.mechanisms=PLAIN \
 -X sasl.username="${SA_CLIENT_ID}" \
 -X sasl.password="${SA_CLIENT_SECRET}" \
 -X enable.ssl.certificate.verification=false \
 -C -c1)

${DIR_NAME}/service_account.sh --delete ${SA_ID}

MK_SMOKE_ID=$(echo ${MK_SMOKE} | jq -r .id)
${DIR_NAME}/managed_kafka.sh --delete ${MK_SMOKE_ID}

if [ "${SMOKE_MESSAGE_OUT}" = "${SMOKE_MESSAGE}" ] ; then
    echo "Smoke test successful"
else
    echo "Failed smoke test: '${SMOKE_MESSAGE_OUT}'"
fi
