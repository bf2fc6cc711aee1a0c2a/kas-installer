#!/bin/bash

# Creates canary service accounts in a developer's MAS-SSO instance based on the credentials stored in any existing `ManagedKafka` resources.
# Assumes the existing deployments are utilizing RH SSO.
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
   "protocolMappers":[
            {
                        "name": "rh-org-id",
                        "protocol": "openid-connect",
                        "protocolMapper": "oidc-usermodel-attribute-mapper",
                        "consentRequired": false,
                        "config": {
                            "userinfo.token.claim": "true",
                            "user.attribute": "rh-org-id",
                            "id.token.claim": "true",
                            "access.token.claim": "true",
                            "claim.name": "rh-org-id",
                            "jsonType.label": "String"
                        }
                    }
        ],
    "directAccessGrantsEnabled": false,
    "serviceAccountsEnabled": true,
    "publicClient": false,
    "protocol": "openid-connect"
}' --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/clients`
echo $CREATE
R=`curl -k --data "grant_type=client_credentials&client_id=$user&client_secret=$pass" https://sso.stage.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token`
SSOTOKEN=$(jq -r '.access_token' <<< $R)
decodejwt=$(jq -R 'split(".") | .[1] | @base64d | fromjson' <<< $SSOTOKEN )
orgId=$(jq -r '."rh-org-id"' <<< $decodejwt)
echo $orgId
KAS=`curl -sk --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/clients?clientId=$user`
kasClientId=$(jq -r '.[].id' <<< $KAS)
SVC=`curl -sk --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/rhoas/clients/$kasClientId/service-account-user`
svcUserId=$(jq -r '.id' <<< $SVC)
echo $svcUserId
UPUSER=`curl -sk -X PUT --data-raw '{"attributes": {"rh-org-id": ["'$orgId'"]}}' --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/users/$svcUserId`
echo $UPUSER
  done


