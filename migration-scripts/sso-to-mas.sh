#!/bin/bash

# Creates a kas-fleetshard agent service account in a developer's MAS-SSO instance based on the credentials stored in the existing dataplane addon secret.
# Assumes the existing deployments are utilizing RH SSO.
OC=$(which oc)

NAMESPACE=redhat-kas-fleetshard-operator

#OC get secrets/addon-kas-fleetshard-operator-parameters -n $NAMESPACE --template={{.data.sso-client-id}} 
#$OC get secrets/addon-kas-fleetshard-operator-parameters -n $NAMESPACE --keys=sso-client-id
clientid=$($OC get secrets/addon-kas-fleetshard-operator-parameters -n $NAMESPACE --template='{{index .data "sso-client-id"}}'|base64 -d) 
secret=$($OC get secrets/addon-kas-fleetshard-operator-parameters -n $NAMESPACE --template='{{index .data "sso-secret"}}'|base64 -d) 

echo $clientid
echo $secret

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

CREATE=`curl -sk --data-raw '{
   "authorizationServicesEnabled": false,
   "clientId": "'$clientid'",
   "description": "kas-fleet-manager",
   "name": "kas-fleet-manager",
   "secret":"'$secret'",
    "directAccessGrantsEnabled": false,
    "serviceAccountsEnabled": true,
    "publicClient": false,
    "protocol": "openid-connect"
}' --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/clients`
echo $CREATE

