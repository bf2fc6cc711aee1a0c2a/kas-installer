#!/bin/bash


OC=$(which oc)
export MAS_SSO_NAMESPACE=mas-sso
export KEYCLOAK_ROUTE=https://$(${OC} get route keycloak -n $MAS_SSO_NAMESPACE --template='{{ .spec.host }}')
export KEYCLOAK_ADMIN_PASS=$(${OC} get secret credential-mas-sso -n $MAS_SSO_NAMESPACE  -o go-template --template="{{.data.ADMIN_PASSWORD|base64decode}}")

echo $KEYCLOAK_ROUTE

KEYCLOAK_URL=$KEYCLOAK_ROUTE
TOKEN_PATH="/auth/realms/master/protocol/openid-connect/token"
REALM=rhoas

CLIENT_ID=admin-cli
USERNAME=admin
PASS=$KEYCLOAK_ADMIN_PASS

RESULT=`curl -sk --data "grant_type=password&client_id=$CLIENT_ID&username=$USERNAME&password=$PASS" $KEYCLOAK_URL$TOKEN_PATH`
TOKEN=$(jq -r '.access_token' <<< $RESULT)
echo $TOKEN


$OC get ManagedKafkas --all-namespaces -o json | jq -r '.items[].spec.serviceAccounts[] | [ .principal, .password ] | @csv' | tr -d '"' | \
  while IFS=, read -r user pass ; do
    echo "$user = $pass"
    CREATE=`curl -sk --data-raw '{
   "authorizationServicesEnabled": false,
   "clientId": "'$user'",
   "description": "kas-fleet-manager",
   "name": "kas-fleet-manager",
   "secret":"'$pass'",
    "directAccessGrantsEnabled": false,
    "serviceAccountsEnabled": true,
    "publicClient": false,
    "protocol": "openid-connect"
}' --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/clients`
echo $CREATE
  done
