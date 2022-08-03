CLUSTER_NAME=$1

CLUSTER=`./managed_kafka.sh --list | jq -r '.items[] | select(.name == "'${CLUSTER_NAME}'")'`

CLUSTER_ID=`echo ${CLUSTER} | jq -r '.id'`

./managed_kafka.sh --certgen ${CLUSTER_ID}

SERVICE_ACCT=`grep -oP '(?<='username=\"')[^\"]*' app-services.properties`

ADMIN_API_SERVER_URL=`echo ${CLUSTER} | jq -r '.admin_api_server_url'`

TOKEN=`./get_access_token.sh --owner`

curl -vs   -H"Authorization: Bearer ${TOKEN}   ${ADMIN_API_SERVER_URL}/api/v1/acls   -XPOST   -H'Content-type: application/json'   --data '{"resourceType":"GROUP", "resourceName":"*", "patternType":"LITERAL", "principal":"User:'${SERVICE_ACCT}'", "operation":"ALL", "permission":"ALLOW"}'

curl -vs   -H"Authorization: Bearer ${TOKEN}   ${ADMIN_API_SERVER_URL}/api/v1/acls   -XPOST   -H'Content-type: application/json'   --data '{"resourceType":"TOPIC", "resourceName":"*", "patternType":"LITERAL", "principal":"User:'${SERVICE_ACCT}'", "operation":"ALL", "permission":"ALLOW"}'

echo 'Bootstrap Server Host:'
echo ${CLUSTER} | jq -r '.bootstrap_server_host'
