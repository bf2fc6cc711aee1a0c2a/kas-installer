#!/bin/bash

set -euo pipefail

DIR_NAME="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

source "${DIR_NAME}/utils/common.sh"

KAS_INSTALLER_DEFAULTS_ENV_FILE="kas-installer-defaults.env"
KAS_INSTALLER_ENV_FILE="kas-installer.env"

COS_FLEET_MANAGER_DIR="cos-fleet-manager"
KAS_FLEET_MANAGER_DIR="kas-fleet-manager"
KAS_INSTALLER_RUNTIME_ENV_FILE="${DIR_NAME}/kas-installer-runtime.env"

read_kas_installer_env_file() {
  if [ ! -e "${KAS_INSTALLER_ENV_FILE}" ]; then
    echo "Required KAS Installer .env file '${KAS_INSTALLER_ENV_FILE}' does not exist"
    exit 1
  fi

  . ${KAS_INSTALLER_ENV_FILE}
  . ${KAS_INSTALLER_DEFAULTS_ENV_FILE}

  if ! cluster_domain_check "${K8S_CLUSTER_DOMAIN}" "install"; then
    echo "Exiting ${0}"
    exit 1
  fi

  if [ "${ENTERPRISE_ENABLED}" = "true" ] ; then
    if [ -z "${OCM_SERVICE_TOKEN}" ] ; then
      echo "OCM token is required when ENTERPRISE_ENABLED = true"
      exit 1
    fi
  fi
}

template_param_script() {
    local SCRIPT_NAME="${1}"

    if [ -f "${DIR_NAME}/${SCRIPT_NAME}" ] ; then
        echo "${DIR_NAME}/${SCRIPT_NAME}"
    else
        echo ""
    fi
}

generate_runtime_env_config() {
  echo "Generating kas-installer runtime env file '${KAS_INSTALLER_RUNTIME_ENV_FILE} ...'"
  # Make sure KAS Fleet Manager env file is empty
  > ${KAS_INSTALLER_RUNTIME_ENV_FILE}

  echo "OBSERVABILITY_CONFIG_REPO=${OBSERVABILITY_CONFIG_REPO}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "OBSERVABILITY_CONFIG_TAG=${OBSERVABILITY_CONFIG_TAG}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "OBSERVABILITY_CR_MERGE_PATCH_CONTENT='${OBSERVABILITY_CR_MERGE_PATCH_CONTENT}'" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}

  echo "STRIMZI_OPERATOR_NAMESPACE=${STRIMZI_OPERATOR_NAMESPACE}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "STRIMZI_OLM_INDEX_IMAGE=${STRIMZI_OLM_INDEX_IMAGE}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}

  echo "KAS_FLEETSHARD_OPERATOR_NAMESPACE=${KAS_FLEETSHARD_OPERATOR_NAMESPACE}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "KAS_FLEETSHARD_OLM_INDEX_IMAGE=${KAS_FLEETSHARD_OLM_INDEX_IMAGE}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}

  echo "SSO_PROVIDER_TYPE='${SSO_PROVIDER_TYPE}'" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  REDHAT_SSO_BASE_URL=https://${REDHAT_SSO_HOSTNAME}
  echo "REDHAT_SSO_BASE_URL=${REDHAT_SSO_BASE_URL}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}

  if [ "${SSO_PROVIDER_TYPE}" = "mas_sso" ] ; then
    MAS_SSO_BASE_URL=https://${MAS_SSO_ROUTE}
    MAS_SSO_REALM='rhoas'

    echo "JWKS_URL=${MAS_SSO_BASE_URL}/auth/realms/${MAS_SSO_REALM}/protocol/openid-connect/certs" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
    echo "SSO_REALM_URL=${MAS_SSO_BASE_URL}/auth/realms/${MAS_SSO_REALM}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  else
    MAS_SSO_BASE_URL=https://${MAS_SSO_BASE_URL:-${MAS_SSO_ROUTE}}
    MAS_SSO_REALM=${MAS_SSO_REALM:-"rhoas"}

    echo "REDHAT_SSO_CLIENT_ID='${REDHAT_SSO_CLIENT_ID}'" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
    echo "REDHAT_SSO_CLIENT_SECRET='${REDHAT_SSO_CLIENT_SECRET}'" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
    export MAS_SSO_CERTS=$(echo "" | ${OPENSSL} s_client -servername ${REDHAT_SSO_HOSTNAME} -connect ${REDHAT_SSO_HOSTNAME}:443 -prexit 2>/dev/null | $OPENSSL x509)
    echo "JWKS_URL=${REDHAT_SSO_BASE_URL}/auth/realms/${REDHAT_SSO_REALM}/protocol/openid-connect/certs" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
    echo "SSO_REALM_URL=${REDHAT_SSO_BASE_URL}/auth/realms/${REDHAT_SSO_REALM}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  fi

  echo "SSO_TRUSTED_CA='${SSO_TRUSTED_CA-${MAS_SSO_CERTS}}'" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "MAS_SSO_BASE_URL=${MAS_SSO_BASE_URL}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "MAS_SSO_REALM=${MAS_SSO_REALM}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "MAS_SSO_CLIENT_ID=kas-fleet-manager" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "MAS_SSO_CLIENT_SECRET=kas-fleet-manager" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "OSD_IDP_MAS_SSO_REALM=rhoas-kafka-sre" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}

  echo "ADMIN_API_SSO_BASE_URL=${ADMIN_API_SSO_BASE_URL:-${MAS_SSO_BASE_URL}}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "ADMIN_API_SSO_REALM=${ADMIN_API_SSO_REALM}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "ADMIN_API_SSO_ENDPOINT_URI=${ADMIN_API_SSO_ENDPOINT_URI}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}

  echo "KAFKA_TLS_CERT='${KAFKA_TLS_CERT:-dummyvalue}'" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "KAFKA_TLS_KEY='${KAFKA_TLS_KEY:-dummyvalue}'" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "ACME_ISSUER_ACCOUNT_KEY='${ACME_ISSUER_ACCOUNT_KEY}'" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}

  echo "KAS_FLEET_MANAGER_GIT_URL=${KAS_FLEET_MANAGER_GIT_URL}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "KAS_FLEET_MANAGER_GIT_REF=${KAS_FLEET_MANAGER_GIT_REF}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "KAS_FLEET_MANAGER_IMAGE_REGISTRY=${KAS_FLEET_MANAGER_IMAGE_REGISTRY}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "KAS_FLEET_MANAGER_IMAGE_REPOSITORY=${KAS_FLEET_MANAGER_IMAGE_REPOSITORY}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "KAS_FLEET_MANAGER_IMAGE_TAG=${KAS_FLEET_MANAGER_IMAGE_TAG}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "KAS_FLEET_MANAGER_IMAGE_BUILD=${KAS_FLEET_MANAGER_IMAGE_BUILD}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "KAS_FLEET_MANAGER_IMAGE_REPOSITORY_USERNAME=${KAS_FLEET_MANAGER_IMAGE_REPOSITORY_USERNAME}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "KAS_FLEET_MANAGER_IMAGE_REPOSITORY_PASSWORD=${KAS_FLEET_MANAGER_IMAGE_REPOSITORY_PASSWORD}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}

  echo "KAS_FLEET_MANAGER_SERVICE_TEMPLATE_PARAMS='$(template_param_script kas-fleet-manager-service-template-params)'" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "KAS_FLEET_MANAGER_SECRETS_TEMPLATE_PARAMS='$(template_param_script kas-fleet-manager-secrets-template-params)'" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}

  echo "COS_FLEET_MANAGER_GIT_URL=${COS_FLEET_MANAGER_GIT_URL}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "COS_FLEET_MANAGER_GIT_REF=${COS_FLEET_MANAGER_GIT_REF}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "COS_FLEET_MANAGER_IMAGE_REGISTRY=${COS_FLEET_MANAGER_IMAGE_REGISTRY}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "COS_FLEET_MANAGER_IMAGE_REPOSITORY=${COS_FLEET_MANAGER_IMAGE_REPOSITORY}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "COS_FLEET_MANAGER_IMAGE_TAG=${COS_FLEET_MANAGER_IMAGE_TAG}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "COS_FLEET_MANAGER_IMAGE_BUILD=${COS_FLEET_MANAGER_IMAGE_BUILD}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "COS_FLEET_MANAGER_IMAGE_REPOSITORY_USERNAME=${COS_FLEET_MANAGER_IMAGE_REPOSITORY_USERNAME}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "COS_FLEET_MANAGER_IMAGE_REPOSITORY_PASSWORD=${COS_FLEET_MANAGER_IMAGE_REPOSITORY_PASSWORD}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}

  echo "COS_FLEET_MANAGER_SERVICE_TEMPLATE_PARAMS='$(template_param_script cos-fleet-manager-service-template-params)'" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "COS_FLEET_MANAGER_SECRETS_TEMPLATE_PARAMS='$(template_param_script cos-fleet-manager-secrets-template-params)'" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}

  echo "OCM_SERVICE_TOKEN=${OCM_SERVICE_TOKEN}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}

  echo "KAS_FLEET_MANAGER_NAMESPACE=mas-fleet-manager-${USER}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "COS_FLEET_MANAGER_NAMESPACE=mas-fleet-manager-${USER}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}

  echo "K8S_CLUSTER_DOMAIN=${K8S_CLUSTER_DOMAIN}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "MAS_FLEET_MANAGEMENT_DOMAIN=mas-fleet-management.apps.${K8S_CLUSTER_DOMAIN}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}

  echo "DATA_PLANE_CLUSTER_CLUSTER_ID=${OCM_CLUSTER_ID}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "DATA_PLANE_CLOUD_PROVIDER=${CLOUD_PROVIDER}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "DATA_PLANE_CLUSTER_REGION=${REGION}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
  echo "DATA_PLANE_CLUSTER_DNS_NAME=apps.${K8S_CLUSTER_DOMAIN}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}

  echo "ENTERPRISE_ENABLED=${ENTERPRISE_ENABLED}" >> ${KAS_INSTALLER_RUNTIME_ENV_FILE}
}

deploy_kas_fleet_manager() {
  echo "Deploying KAS Fleet Manager ..."
  ${DIR_NAME}/${KAS_FLEET_MANAGER_DIR}/deploy-kas-fleet-manager.sh
  echo "KAS Fleet Manager deployed"
}

deploy_cos_fleet_manager() {
  echo "Deploying COS Fleet Manager ..."
  ${DIR_NAME}/${COS_FLEET_MANAGER_DIR}/deploy-cos-fleet-manager.sh
  echo "COS Fleet Manager deployed"
}

install_mas_sso() {
  export DOCKER_USER_NAME=${IMAGE_REPOSITORY_USERNAME}
  export DOCKER_PASSWORD=${IMAGE_REPOSITORY_PASSWORD}
  export MAS_SSO_NAMESPACE=mas-sso
  export RH_USERNAME RH_USER_ID RH_ORG_ID MAS_SSO_OLM_INDEX_IMAGE MAS_SSO_OLM_INDEX_IMAGE_TAG

  if [ -n "${MAS_SSO_OPERATOR_SUBSCRIPTION_CONFIG:-}" ] ; then
      export MAS_SSO_OPERATOR_SUBSCRIPTION_CONFIG
  fi

  if [ -n "${MAS_SSO_KEYCLOAK_RESOURCES:-}" ] ; then
      export MAS_SSO_KEYCLOAK_RESOURCES
  fi

  MAS_SSO_ROUTE=$($OC get route -l app=keycloak -n ${MAS_SSO_NAMESPACE} -o json | jq -r '.items[].spec.host' 2>/dev/null)

  if [ "${SKIP_SSO:-"n"}" = "n" ] || [ "${MAS_SSO_ROUTE}" = "" ] ; then
    echo "MAS SSO route not found or SKIP_SSO not configured, installing MAS SSO ..."
    ${DIR_NAME}/mas-sso/mas-sso-installer.sh
    echo "MAS SSO deployed"
  else
    echo "Skipping MAS SSO installation"
  fi

  export MAS_SSO_ROUTE=$($OC get route -l app=keycloak -n ${MAS_SSO_NAMESPACE} -o json | jq -r '.items[].spec.host')
  export MAS_SSO_CERTS=$(echo "" | $OPENSSL s_client -servername $MAS_SSO_ROUTE -connect $MAS_SSO_ROUTE:443 -prexit 2>/dev/null | $OPENSSL x509)
}

deploy_observatorium() {
  echo "Deploying Observatorium ..."
  ${DIR_NAME}/observatorium/install-observatorium.sh && \
  echo "Observatorium deployed" || \
  echo "Observatorium deployment failed"
}

# Main body of the script starts here

read_kas_installer_env_file

# Deploy and configure MAS SSO
if [ "${SSO_PROVIDER_TYPE}" = "mas_sso" ] || [ -z "${MAS_SSO_BASE_URL:-}" ] ; then
    install_mas_sso
fi

# Deploy and configure Observatorium
if [ "${INSTALL_OBSERVATORIUM:-"n"}" = "y" ] || [ "${SKIP_OBSERVATORIUM:-"n"}" = "n" ]; then
    deploy_observatorium
fi

# Deploy and configure KAS Fleet Manager and its
# dependencies (Observability Operator, Sharded NLB, manual
# terraforming steps ...)
generate_runtime_env_config

deploy_kas_fleet_manager
deploy_cos_fleet_manager
