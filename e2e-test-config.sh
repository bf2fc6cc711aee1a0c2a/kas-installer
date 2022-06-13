#!/bin/bash

DIR_NAME="$(dirname $0)"
OC=$(which oc)

source ${DIR_NAME}/kas-installer.env
source ${DIR_NAME}/kas-installer-defaults.env
USER_CONFIG=""

append_user_config() {
    VARNAME="${1}"
    VARVALUE="${2}"
    USER_CONFIG="$(printf '%s\n  "%s": "%s",\n' "${USER_CONFIG}" "${VARNAME}" "${VARVALUE}")"
}

create_mas_sso_user() {
    USERNAME=${1}
    USERID=${2}
    USERORG=${3}
    VARALIAS=${4}

    EXISTING_USERNAME=$(${OC} get KeyCloakUser kas-user-${USERID} -n mas-sso --template='{{ .spec.user.username }}' 2>/dev/null)

    if [ -z "${EXISTING_USERNAME}" ] ; then
        echo "Creating test user ${USERNAME} with rh-user-id ${USERID}" > /dev/stderr
        ${OC} process -f ${DIR_NAME}/mas-sso/clients/owner-template.yaml \
          -pRH_USERNAME=${USERNAME} \
          -pRH_USER_ID=${USERID} \
          -pRH_ORG_ID=${USERORG} \
            | oc create -f - -n mas-sso 1>&2
    fi

    append_user_config "${VARALIAS}_USERNAME" "${USERNAME}"
    # Password = username
    append_user_config "${VARALIAS}_PASSWORD" "${USERNAME}"
}

if [ "${SSO_PROVIDER_TYPE}" = "mas_sso" ] ; then
    REDHAT_SSO_URI=$(${OC} get route keycloak -n mas-sso --template='{{ .spec.host }}')
    REDHAT_SSO_REALM='rhoas'
    REDHAT_SSO_CLIENT_ID='rhoas-cli-prod'
    REDHAT_SSO_LOGIN_FORM_ID='#kc-form-login'

    append_user_config "ADMIN_USERNAME" "${RH_USERNAME}"
    append_user_config "ADMIN_PASSWORD" "${RH_USERNAME}"

    create_mas_sso_user 'primary-user' '11111111' "${RH_ORG_ID}" 'PRIMARY'
    create_mas_sso_user 'secondary-user' '22222222' "${RH_ORG_ID}" 'SECONDARY'
    create_mas_sso_user 'alien-user' '00000000' "00000000" 'ALIEN'
else
    REDHAT_SSO_URI=${REDHAT_SSO_HOSTNAME}
    REDHAT_SSO_REALM=${REDHAT_SSO_REALM}
    REDHAT_SSO_REDIRECT_URI='https://console.stage.redhat.com'
    REDHAT_SSO_CLIENT_ID='cloud-services'
    REDHAT_SSO_LOGIN_FORM_ID='#rh-password-verification-form'
    OPENSHIFT_IDENTITY_REDIRECT_URI_ENV='https://console.stage.redhat.com/beta/application-services'

    for var in $(compgen -ve); do
        if [[ ${var} == E2E_USER_* ]]; then
            echo "Using provided test user configuration: ${var:9}" > /dev/stderr
            append_user_config "${var:9}" "${!var}"
        fi
    done
fi

cat <<EOF
{
  "LAUNCH_KEY": "${USER}",
  "GITHUB_TOKEN": "${OBSERVABILITY_CONFIG_ACCESS_TOKEN}",
  "SKIP_KAFKA_TEARDOWN": "false",
  ${USER_CONFIG}

  "REDHAT_SSO_URI": "https://${REDHAT_SSO_URI}",
  "REDHAT_SSO_REALM": "${REDHAT_SSO_REALM}",
  "REDHAT_SSO_REDIRECT_URI": "${REDHAT_SSO_REDIRECT_URI}",
  "REDHAT_SSO_CLIENT_ID": "${REDHAT_SSO_CLIENT_ID}",
  "REDHAT_SSO_LOGIN_FORM_ID": "${REDHAT_SSO_LOGIN_FORM_ID}",

  "OPENSHIFT_IDENTITY_URI": "https://${REDHAT_SSO_URI}",
  "OPENSHIFT_IDENTITY_REALM_ENV": "${REDHAT_SSO_REALM}",
  "OPENSHIFT_IDENTITY_REDIRECT_URI_ENV": "${OPENSHIFT_IDENTITY_REDIRECT_URI_ENV}",
  "OPENSHIFT_IDENTITY_CLIENT_ID_ENV": "${REDHAT_SSO_CLIENT_ID}",
  "OPENSHIFT_IDENTITY_LOGIN_FORM_ID": "${REDHAT_SSO_LOGIN_FORM_ID}",

  "KAFKA_INSECURE_TLS": "true",

  "OPENSHIFT_API_URI": "https://$(${OC} get route kas-fleet-manager -n kas-fleet-manager-${USER} --template='{{ .spec.host }}')"
}
EOF
