#!/bin/bash
KEYCLOAK_URL="https://sso.stage.redhat.com"
echo $KEYCLOAK_URL
TOKEN_PATH="/auth/realms/redhat-external/protocol/openid-connect/token"
REALM="redhat-external"

REDHAT_CLIENT_ID=<set sso client>
REDHAT_CLIENT_SECRET=<set sso secret>

RESULT=`curl -sk --data "grant_type=client_credentials&client_id=$REDHAT_CLIENT_ID&client_secret=$REDHAT_CLIENT_SECRET" $KEYCLOAK_URL$TOKEN_PATH`
TOKEN=$(jq -r '.access_token' <<< $RESULT)
echo $TOKEN

R=`curl -sk --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/realms/redhat-external/apis/service_accounts/v1/`
#echo $R |  jq -r '.[].id'
echo $R
listsa=$(jq -r '.[].id' <<< $R)

for i in $listsa
  do
    echo $i
    D=`curl -sk -X DELETE --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/realms/redhat-external/apis/service_accounts/v1/$i`
  done