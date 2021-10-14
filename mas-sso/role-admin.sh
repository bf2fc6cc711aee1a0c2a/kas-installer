#!/bin/bash

OC=$(which oc)

KEYCLOAK_URL=https://$(${OC} get route keycloak --template='{{ .spec.host }}' -n mas-sso)
KEYCLOAK_ADMIN_USER=admin
KEYCLOAK_ADMIN_PASS=$(${OC} get secret credential-mas-sso -o go-template --template="{{.data.ADMIN_PASSWORD|base64decode}}" -n mas-sso)
KEYCLOAK_ADMIN_CLIENT_ID=admin-cli
KEYCLOAK_ADMIN_CREDENTIALS="grant_type=password&client_id=${KEYCLOAK_ADMIN_CLIENT_ID}&username=${KEYCLOAK_ADMIN_USER}&password=${KEYCLOAK_ADMIN_PASS}"

REALM=rhoas-kafka-sre
REALM_URL="${KEYCLOAK_URL}/auth/admin/realms/${REALM}"
TOKEN_URL="${KEYCLOAK_URL}/auth/realms/master/protocol/openid-connect/token"

FLEETMANAGER_ADMIN_CLIENT=kafka-admin
FLEETMANAGER_ADMIN_ROLE=kas-fleet-manager-admin-full

# Obtain admin user access token
ACCESS_TOKEN=$(curl -sk --data "${KEYCLOAK_ADMIN_CREDENTIALS}" ${TOKEN_URL} | jq -r '.access_token')
AUTHN_HEADER="Authorization: Bearer ${ACCESS_TOKEN}"
JSON_CONTENT="Content-Type: application/json"

CLIENT_CREATE_RESPONSE=$(curl --fail --show-error -sk -H"${JSON_CONTENT}" -H"${AUTHN_HEADER}" ${REALM_URL}/clients --data-raw '{
  "clientId": "'${FLEETMANAGER_ADMIN_CLIENT}'",
  "secret":"'${FLEETMANAGER_ADMIN_CLIENT}'",
  "name": "'${FLEETMANAGER_ADMIN_CLIENT}'",
  "serviceAccountsEnabled": true,
  "protocol": "openid-connect",
  "publicClient": false,
  "clientAuthenticatorType": "client-secret"
}')

if [ $? -ne 0 ] ; then
    exit 1
fi

echo "Created client: ${FLEETMANAGER_ADMIN_CLIENT}"

ADMIN_CLIENT_ID=$(curl --fail --show-error -sk -H"${AUTHN_HEADER}" ${REALM_URL}/clients?clientId=${FLEETMANAGER_ADMIN_CLIENT} | jq -r '.[].id')

# Create "kas-fleet-manager-admin-full" role
ROLE_CREATE_RESPONSE=$(curl --fail --show-error -sk -H"${JSON_CONTENT}" -H"${AUTHN_HEADER}" ${REALM_URL}/roles --data-raw '{
  "name": "'${FLEETMANAGER_ADMIN_ROLE}'"
}')

if [ $? -ne 0 ] ; then
    exit 1
fi

echo "Created role: ${FLEETMANAGER_ADMIN_ROLE}"

ADMIN_FULL_ROLE_ID=$(curl --fail --show-error -sk -H"${AUTHN_HEADER}" ${REALM_URL}/roles |\
    jq -r -c '.[] | select( .name | contains("'${FLEETMANAGER_ADMIN_ROLE}'")).id')

if [ $? -ne 0 ] ; then
    exit 1
fi

ADMIN_SERVICE_ACCOUNT_ID=$(curl --fail --show-error -sk -H"${AUTHN_HEADER}" ${REALM_URL}/clients/${ADMIN_CLIENT_ID}/service-account-user | jq -r .id)

FINAL=$(curl --fail --show-error -sk -H"${JSON_CONTENT}" -H"${AUTHN_HEADER}" ${REALM_URL}/users/${ADMIN_SERVICE_ACCOUNT_ID}/role-mappings/realm --data-raw '[
  {
    "id": "'${ADMIN_FULL_ROLE_ID}'",
    "name": "'${FLEETMANAGER_ADMIN_ROLE}'"
  }]')
if [ $? -ne 0 ] ; then
    exit 1
fi

echo "Associated role ${FLEETMANAGER_ADMIN_ROLE}(${ADMIN_FULL_ROLE_ID}) with client ${FLEETMANAGER_ADMIN_CLIENT}(${ADMIN_CLIENT_ID}) service account"
