#!/bin/bash

DIR_NAME="$(dirname $0)"
OC=$(which oc)

source ${DIR_NAME}/kas-installer.env
source ${DIR_NAME}/kas-fleet-manager/kas-fleet-manager-deploy.env

SECONDARY_USERNAME=$(${OC} get KeyCloakUser kas-user-11111111 -n mas-sso --template='{{ .spec.user.username }}' 2>/dev/null)

if [ -z "${SECONDARY_USERNAME}" ] ; then
    SECONDARY_USERNAME=secondary-user

    ${OC} process -f ${DIR_NAME}/mas-sso/clients/owner-template.yaml \
      -pRH_USERNAME=${SECONDARY_USERNAME} \
      -pRH_USER_ID=11111111 \
      -pRH_ORG_ID=${RH_ORG_ID} \
        | oc create -f - -n mas-sso 1>&2
fi

ALIEN_USERNAME=$(${OC} get KeyCloakUser kas-user-00000000 -n mas-sso --template='{{ .spec.user.username }}' 2>/dev/null)

if [ -z "${ALIEN_USERNAME}" ] ; then
    ALIEN_USERNAME=alien-user

    ${OC} process -f ${DIR_NAME}/mas-sso/clients/owner-template.yaml \
      -pRH_USERNAME=${ALIEN_USERNAME} \
      -pRH_USER_ID=00000000 \
      -pRH_ORG_ID=00000000 \
        | oc create -f - -n mas-sso 1>&2
fi

cat <<EOF
{
  "LAUNCH_KEY": "${USER}",
  "GITHUB_TOKEN": "${OBSERVABILITY_CONFIG_ACCESS_TOKEN}",
  "SKIP_KAFKA_TEARDOWN": "false",

  "PRIMARY_USERNAME": "${RH_USERNAME}",
  "PRIMARY_PASSWORD": "${RH_USERNAME}",

  "SECONDARY_USERNAME": "${SECONDARY_USERNAME}",
  "SECONDARY_PASSWORD": "${SECONDARY_USERNAME}",

  "ALIEN_USERNAME": "${ALIEN_USERNAME}",
  "ALIEN_PASSWORD": "${ALIEN_USERNAME}",

  "REDHAT_SSO_URI": "https://keycloak-mas-sso.${DATA_PLANE_CLUSTER_DNS_NAME}",
  "REDHAT_SSO_REALM": "rhoas",
  "REDHAT_SSO_CLIENT_ID": "rhoas-cli-prod",
  "REDHAT_SSO_LOGIN_FORM_ID": "#kc-form-login",

  "OPENSHIFT_IDENTITY_URI": "https://keycloak-mas-sso.${DATA_PLANE_CLUSTER_DNS_NAME}",
  "OPENSHIFT_IDENTITY_REALM_ENV": "rhoas",
  "OPENSHIFT_IDENTITY_CLIENT_ID_ENV": "rhoas-cli-prod",
  "OPENSHIFT_IDENTITY_LOGIN_FORM_ID": "#kc-form-login",

  "KAFKA_INSECURE_TLS": "true",

  "OPENSHIFT_API_URI": "https://kas-fleet-manager-kas-fleet-manager-${USER}.${DATA_PLANE_CLUSTER_DNS_NAME}"
}
EOF
