#!/bin/bash

export KEYCLOAK_ROUTE=https://$(oc get route keycloak --template='{{ .spec.host }}')
export KEYCLOAK_ADMIN_PASS=$(oc get secret credential-mas-sso -o go-template --template="{{.data.ADMIN_PASSWORD|base64decode}}")
echo $KEYCLOAK_ROUTE

KEYCLOAK_URL=$KEYCLOAK_ROUTE
REALM=rhoas-kafka-sre
TOKEN_PATH="/auth/realms/master/protocol/openid-connect/token"
CLIENT_ID=admin-cli
USERNAME=admin
PASS=$KEYCLOAK_ADMIN_PASS
FLEET_OPERATOR_ROLE=kas_fleetshard_operator

# Obtain admin user access token
ACCESS_TOKEN=$(curl -sk --data "grant_type=password&client_id=$CLIENT_ID&username=$USERNAME&password=$PASS" $KEYCLOAK_URL$TOKEN_PATH | jq -r '.access_token')

# Create "kas-fleet-manager-admin-full" role
curl -sk --data-raw '{"name": "kas-fleet-manager-admin-full"}' --header "Content-Type: application/json" --header "Authorization: Bearer $ACCESS_TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/roles
ADMIN_FULL_ROLE_ID=$(curl -sk --header "Content-Type: application/json" --header "Authorization: Bearer $ACCESS_TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/roles | jq -c '.[] | select( .name | contains("kas-fleet-manager-admin-full")).id')

ADMIN_CLIENT_ID=$(curl -sk --header "Content-Type: application/json" --header "Authorization: Bearer $ACCESS_TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/clients?clientId=kafka-admin | jq -r '.[].id')
ADMIN_SERVICE_ACCOUNT_ID=$(curl -sk --header "Content-Type: application/json" --header "Authorization: Bearer $ACCESS_TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/clients/$ADMIN_CLIENT_ID/service-account-user | jq -r .id)

FINAL=$(curl -sk --data-raw '[{"id": '$ADMIN_FULL_ROLE_ID',"name": "kas-fleet-manager-admin-full"}]' --header "Content-Type: application/json" --header "Authorization: Bearer $ACCESS_TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/users/$ADMIN_SERVICE_ACCOUNT_ID/role-mappings/realm)
echo $FINAL
