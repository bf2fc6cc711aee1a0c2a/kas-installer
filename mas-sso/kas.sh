#!/bin/bash


export KEYCLOAK_ROUTE=https://$(oc get route keycloak --template='{{ .spec.host }}')
export KEYCLOAK_ADMIN_PASS=$(oc get secret credential-mas-sso -o go-template --template="{{.data.ADMIN_PASSWORD|base64decode}}")

echo $KEYCLOAK_ROUTE

KEYCLOAK_URL=$KEYCLOAK_ROUTE
TOKEN_PATH="/auth/realms/master/protocol/openid-connect/token"

CLIENT_ID=admin-cli
USERNAME=admin
PASS=$KEYCLOAK_ADMIN_PASS

RESULT=`curl -sk --data "grant_type=password&client_id=$CLIENT_ID&username=$USERNAME&password=$PASS" $KEYCLOAK_URL$TOKEN_PATH`
TOKEN=$(jq -r '.access_token' <<< $RESULT)
echo $TOKEN

CREATE=`curl -sk --data-raw '{
   "authorizationServicesEnabled": false,
   "clientId": "kas-fleet-manager",
   "description": "kas-fleet-manager",
   "name": "kas-fleet-manager",
   "secret":"kas-fleet-manager",
    "directAccessGrantsEnabled": false,
    "serviceAccountsEnabled": true,
    "publicClient": false,
    "protocol": "openid-connect"
}' --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/clients`
echo $CREATE

RE=`curl -sk --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/rhoas/clients?clientId=realm-management`
realmMgmtClientId=$(jq -r '.[].id' <<< $RE)
echo $realmMgmtClientId


ROLES=`curl -sk --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/rhoas/clients/$realmMgmtClientId/roles`
manageUser=$(jq -c '.[] | select( .name | contains("manage-users")).id' <<< $ROLES)
manageClients=$(jq -c '.[] | select( .name | contains("manage-clients")).id' <<< $ROLES)
manageRealm=$(jq -c '.[] | select( .name | contains("manage-realm")).id' <<< $ROLES)
echo $manageUser
echo $manageRealm
echo $manageClients


KAS=`curl -sk --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/rhoas/clients?clientId=kas-fleet-manager`
kasClientId=$(jq -r '.[].id' <<< $KAS)

#/auth/admin/realms/rhoas/clients/de121cf7-a6b2-4d39-a99c-8da787454a66/service-account-user
SVC=`curl -sk --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/rhoas/clients/$kasClientId/service-account-user`
svcUserId=$(jq -r '.id' <<< $SVC)
echo $svcUserId

FINAL=`curl -sk --data-raw '[{"id": '$manageUser',"name": "manage-users"},{"id": '$manageRealm',"name": "manage-realm"},{"id": '$manageClients',"name": "manage-clients"}]' --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/rhoas/users/$svcUserId/role-mappings/clients/$realmMgmtClientId`
echo $FINAL


