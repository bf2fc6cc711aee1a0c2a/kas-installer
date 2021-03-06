#!/bin/bash

OC=$(which oc)

export KEYCLOAK_ROUTE=https://$(${OC} get route keycloak --template='{{ .spec.host }}')
export KEYCLOAK_ADMIN_PASS=$(${OC} get secret credential-mas-sso -o go-template --template="{{.data.ADMIN_PASSWORD|base64decode}}")

echo $KEYCLOAK_ROUTE

KEYCLOAK_URL=$KEYCLOAK_ROUTE
TOKEN_PATH="/auth/realms/master/protocol/openid-connect/token"

CLIENT_ID=admin-cli
USERNAME=admin
PASS=$KEYCLOAK_ADMIN_PASS

RESULT=`curl -sk --data "grant_type=password&client_id=$CLIENT_ID&username=$USERNAME&password=$PASS" $KEYCLOAK_URL$TOKEN_PATH`
TOKEN=$(jq -r '.access_token' <<< $RESULT)
echo $TOKEN

RE=`curl -sk --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/rhoas-kafka-sre/clients?clientId=realm-management`
realmMgmtClientId=$(jq -r '.[].id' <<< $RE)
echo $realmMgmtClientId


ROLES=`curl -sk --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/rhoas-kafka-sre/clients/$realmMgmtClientId/roles`
manageClients=$(jq -c '.[] | select( .name | contains("manage-clients")).id' <<< $ROLES)
echo $manageClients

CREATE=`curl -sk --data-raw '{ "authorizationServicesEnabled": false,"clientId": "kas-fleet-manager","name": "kas-fleet-manager","secret": "kas-fleet-manager","serviceAccountsEnabled": true,"standardFlowEnabled": false}' --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/rhoas-kafka-sre/clients`
echo $CREATE

KAS=`curl -sk --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/rhoas-kafka-sre/clients?clientId=kas-fleet-manager`
kasClientId=$(jq -r '.[].id' <<< $KAS)


SVC=`curl -sk --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/rhoas-kafka-sre/clients/$kasClientId/service-account-user`
svcUserId=$(jq -r '.id' <<< $SVC)
echo $svcUserId

FINAL=`curl -sk --data-raw '[{"id": '$manageClients',"name": "manage-clients"}]' --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/rhoas-kafka-sre/users/$svcUserId/role-mappings/clients/$realmMgmtClientId`
echo $FINAL
