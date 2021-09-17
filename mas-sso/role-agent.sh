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
FLEET_OPERATOR_ROLE=kas_fleetshard_operator

RESULT=`curl -sk --data "grant_type=password&client_id=$CLIENT_ID&username=$USERNAME&password=$PASS" $KEYCLOAK_URL$TOKEN_PATH`
TOKEN=$(jq -r '.access_token' <<< $RESULT)
echo $TOKEN

R=`curl -sk --data-raw '{"name": "'${FLEET_OPERATOR_ROLE}'"}' --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/roles`
echo $R

ROLES=`curl -sk --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/roles`
kasfleetroleid=$(jq -c '.[] | select( .name | contains("'${FLEET_OPERATOR_ROLE}'")).id' <<< $ROLES)
echo $kasfleetroleid

KAS=`curl -sk --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/clients?clientId=kas-fleetshard-agent`
kasClientId=$(jq -r '.[].id' <<< $KAS)


SVC=`curl -sk --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/clients/$kasClientId/service-account-user`
svcUserId=$(jq -r '.id' <<< $SVC)
echo $svcUserId

UPUSER=`curl -sk -X PUT --data-raw '{"attributes": {"kas-fleetshard-operator-cluster-id": ["dev-dataplane-cluster"]}}' --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/users/$svcUserId`
echo $UPUSER

FINAL=`curl -sk --data-raw '[{"id": '$kasfleetroleid',"name": "'${FLEET_OPERATOR_ROLE}'"}]' --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/users/$svcUserId/role-mappings/realm`
echo $FINAL

PROTO=`curl -sk --data-raw '{"protocol":"openid-connect","config":{"id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true","multivalued":"","aggregate.attrs":"","user.attribute":"kas-fleetshard-operator-cluster-id","claim.name":"kas-fleetshard-operator-cluster-id"},"name":"kas-fleetshard-operator-cluster-id","protocolMapper":"oidc-usermodel-attribute-mapper"}' --header "Content-Type: application/json" --header "Authorization: Bearer $TOKEN" $KEYCLOAK_URL/auth/admin/realms/$REALM/clients/$kasClientId/protocol-mappers/models`
echo $PROTO