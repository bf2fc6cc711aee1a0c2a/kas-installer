#!/bin/bash

export KEYCLOAK_ROUTE=https://$(oc get route keycloak --template='{{ .spec.host }}')
export KEYCLOAK_ADMIN_PASS=$(oc get secret credential-mas-sso -o go-template --template="{{.data.ADMIN_PASSWORD|base64decode}}")
echo $KEYCLOAK_ROUTE

KEYCLOAK_URL=$KEYCLOAK_ROUTE
REALM=rhoas
TOKEN_PATH="/auth/realms/master/protocol/openid-connect/token"
CLIENT_ID=admin-cli
USERNAME=admin
PASS=$KEYCLOAK_ADMIN_PASS

RESULT=`curl -k --data "grant_type=password&client_id=$CLIENT_ID&username=$USERNAME&password=$PASS" $KEYCLOAK_URL$TOKEN_PATH`
TOKEN=$(jq -r '.access_token' <<< $RESULT)
echo $TOKEN

R=`curl -k --data-raw '{"name": "kas-fleet-operator"}' --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/roles`
echo $R

ROLES=`curl -k --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/roles`
kasfleetroleid=$(jq -c '.[] | select( .name | contains("kas-fleet-operator")).id' <<< $ROLES)
echo $kasfleetroleid

KAS=`curl -k --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/clients?clientId=kas-fleetshard-agent`
kasClientId=$(jq -r '.[].id' <<< $KAS)


SVC=`curl -k --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/clients/$kasClientId/service-account-user`
svcUserId=$(jq -r '.id' <<< $SVC)
echo $svcUserId

FINAL=`curl -k --data-raw '[{"id": '$kasfleetroleid',"name": "kas-fleet-operator"}]' --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/users/$svcUserId/role-mappings/realm`
echo $FINAL
