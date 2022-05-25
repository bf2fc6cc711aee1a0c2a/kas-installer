#!/bin/bash

set -euo pipefail

DIR_NAME="$(dirname $0)"

source "${DIR_NAME}/utils/common.sh"

KAS_INSTALLER_DEFAULTS_ENV_FILE="kas-installer-defaults.env"
KAS_INSTALLER_ENV_FILE="kas-installer.env"
KAS_FLEET_MANAGER_PARAM_GEN_SCRIPT="kas-fleet-manager-service-template-params"

KAS_FLEET_MANAGER_DIR="kas-fleet-manager"
KAS_FLEET_MANAGER_DEPLOY_ENV_FILE="${DIR_NAME}/${KAS_FLEET_MANAGER_DIR}/kas-fleet-manager-deploy.env"

read_kas_installer_env_file() {
  if [ ! -e "${KAS_INSTALLER_ENV_FILE}" ]; then
    echo "Required KAS Installer .env file '${KAS_INSTALLER_ENV_FILE}' does not exist"
    exit 1
  fi

  . ${KAS_INSTALLER_ENV_FILE}
  . ${KAS_INSTALLER_DEFAULTS_ENV_FILE}

  if [ -f "${DIR_NAME}/${KAS_FLEET_MANAGER_PARAM_GEN_SCRIPT}" ] ; then
    KAS_FLEET_MANAGER_SERVICE_TEMPLATE_PARAMS="${DIR_NAME}/${KAS_FLEET_MANAGER_PARAM_GEN_SCRIPT}"
  else
    KAS_FLEET_MANAGER_SERVICE_TEMPLATE_PARAMS=''
  fi

  if ! cluster_domain_check "${K8S_CLUSTER_DOMAIN}" "install"; then
    echo "Exiting ${0}"
    exit 1
  fi

  if [ -z "${KAS_FLEETSHARD_OPERATOR_NAMESPACE:-}" ] ; then
    if [ -n "${OCM_SERVICE_TOKEN}" ] ; then
      KAS_FLEETSHARD_OPERATOR_NAMESPACE='redhat-kas-fleetshard-operator-qe'
    else
      KAS_FLEETSHARD_OPERATOR_NAMESPACE='redhat-kas-fleetshard-operator'
    fi
  fi

  if [ -z "${STRIMZI_OPERATOR_NAMESPACE:-}" ] ; then
    if [ -n "${OCM_SERVICE_TOKEN}" ] ; then
      STRIMZI_OPERATOR_NAMESPACE='redhat-managed-kafka-operator-qe'
    else
      STRIMZI_OPERATOR_NAMESPACE='redhat-managed-kafka-operator'
    fi
  fi
}

generate_kas_fleet_manager_env_config() {
  echo "Generating KAS Fleet Manager configuration env file '${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE} ...'"
  # Make sure KAS Fleet Manager env file is empty
  > ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "OBSERVABILITY_CONFIG_ACCESS_TOKEN=${OBSERVABILITY_CONFIG_ACCESS_TOKEN}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "OBSERVABILITY_CONFIG_REPO=${OBSERVABILITY_CONFIG_REPO}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "OBSERVABILITY_CONFIG_TAG=${OBSERVABILITY_CONFIG_TAG}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "STRIMZI_OPERATOR_NAMESPACE=${STRIMZI_OPERATOR_NAMESPACE}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "STRIMZI_OLM_INDEX_IMAGE=${STRIMZI_OLM_INDEX_IMAGE}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "KAS_FLEETSHARD_OPERATOR_NAMESPACE=${KAS_FLEETSHARD_OPERATOR_NAMESPACE}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "KAS_FLEETSHARD_OLM_INDEX_IMAGE=${KAS_FLEETSHARD_OLM_INDEX_IMAGE}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "SSO_PROVIDER_TYPE='${SSO_PROVIDER_TYPE}'" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  if [ "${SSO_PROVIDER_TYPE}" = "mas_sso" ] ; then
    MAS_SSO_BASE_URL=https://${MAS_SSO_ROUTE}
    MAS_SSO_REALM='rhoas'

    echo "SSO_CLIENT_ID=kas-fleet-manager" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
    echo "SSO_CLIENT_SECRET=kas-fleet-manager" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
    echo "OSD_IDP_MAS_SSO_REALM=rhoas-kafka-sre" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  else
    MAS_SSO_BASE_URL=https://${MAS_SSO_BASE_URL}
    MAS_SSO_REALM=${MAS_SSO_REALM}
    REDHAT_SSO_BASE_URL=https://${REDHAT_SSO_BASE_URL}

    echo "REDHAT_SSO_CLIENT_ID='${REDHAT_SSO_CLIENT_ID}'" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
    echo "REDHAT_SSO_CLIENT_SECRET='${REDHAT_SSO_CLIENT_SECRET}'" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
    echo "SSO_CLIENT_ID=${SSO_CLIENT_ID}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
    echo "SSO_CLIENT_SECRET=${SSO_CLIENT_SECRET}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
    export MAS_SSO_CERTS=$(echo "" | ${OPENSSL} s_client -servername $REDHAT_SSO_BASE_URL -connect $REDHATT_SSO_BASE_URL:443 -prexit 2>/dev/null | $OPENSSL x509)
    echo "OSD_IDP_MAS_SSO_REALM=${OSD_MAS_SSO_REALM}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  fi

  if [ -n "${SSO_TRUSTED_CA:-}" ] ; then
    echo "SSO_TRUSTED_CA='${SSO_TRUSTED_CA}'" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  else
    echo "SSO_TRUSTED_CA='${MAS_SSO_CERTS}'" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  fi

  echo "MAS_SSO_BASE_URL=${MAS_SSO_BASE_URL}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "MAS_SSO_REALM=${MAS_SSO_REALM}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "REDHAT_SSO_BASE_URL=${REDHAT_SSO_BASE_URL}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "KAFKA_TLS_CERT=dummyvalue" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "KAFKA_TLS_KEY=dummyvalue" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "KAS_FLEET_MANAGER_GIT_URL=${KAS_FLEET_MANAGER_GIT_URL}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "KAS_FLEET_MANAGER_GIT_REF=${KAS_FLEET_MANAGER_GIT_REF}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "IMAGE_REGISTRY=${KAS_FLEET_MANAGER_IMAGE_REGISTRY}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "IMAGE_REPOSITORY=${KAS_FLEET_MANAGER_IMAGE_REPOSITORY}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "IMAGE_TAG=${KAS_FLEET_MANAGER_IMAGE_TAG}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "IMAGE_BUILD=${KAS_FLEET_MANAGER_IMAGE_BUILD}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "IMAGE_REPOSITORY_USERNAME=${KAS_FLEET_MANAGER_IMAGE_REPOSITORY_USERNAME}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "IMAGE_REPOSITORY_PASSWORD=${KAS_FLEET_MANAGER_IMAGE_REPOSITORY_PASSWORD}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "KAS_FLEET_MANAGER_SERVICE_TEMPLATE_PARAMS=${KAS_FLEET_MANAGER_SERVICE_TEMPLATE_PARAMS}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "OCM_SERVICE_TOKEN=${OCM_SERVICE_TOKEN}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "JWKS_URL=${REDHAT_SSO_BASE_URL}/auth/realms/${SSO_REALM=}/protocol/openid-connect/certs" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "ISSUER_URL=${REDHAT_SSO_BASE_URL}/auth/realms/${SSO_REALM}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "KAS_FLEET_MANAGER_NAMESPACE=kas-fleet-manager-${USER}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "K8S_CLUSTER_DOMAIN=${K8S_CLUSTER_DOMAIN}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "DATA_PLANE_CLUSTER_CLUSTER_ID=${OCM_CLUSTER_ID}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "DATA_PLANE_CLUSTER_REGION=${REGION}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "DATA_PLANE_CLUSTER_DNS_NAME=apps.${K8S_CLUSTER_DOMAIN}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
}

deploy_kas_fleet_manager() {
  echo "Deploying KAS Fleet Manager ..."
  ${DIR_NAME}/${KAS_FLEET_MANAGER_DIR}/deploy-kas-fleet-manager.sh
  echo "KAS Fleet Manager deployed"
}

install_mas_sso() {
  export DOCKER_USER_NAME=${IMAGE_REPOSITORY_USERNAME}
  export DOCKER_PASSWORD=${IMAGE_REPOSITORY_PASSWORD}
  export MAS_SSO_NAMESPACE=mas-sso
  export RH_USERNAME RH_USER_ID RH_ORG_ID MAS_SSO_OLM_INDEX_IMAGE MAS_SSO_OLM_INDEX_IMAGE_TAG

  if [ "${SKIP_SSO:-"n"}" = "n" ] || [ "$($OC get route keycloak -n $MAS_SSO_NAMESPACE --template='{{ .spec.host }}' 2>/dev/null)" = "" ] ; then
    echo "MAS SSO route not found or SKIP_SSO not configured, installing MAS SSO ..."
    ${DIR_NAME}/mas-sso/mas-sso-installer.sh
    echo "MAS SSO deployed"
  else
    echo "Skipping MAS SSO installation"
  fi

  export MAS_SSO_ROUTE=$($OC get route keycloak -n $MAS_SSO_NAMESPACE --template='{{ .spec.host }}')
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
if [ "${SSO_PROVIDER_TYPE}" = "mas_sso" ] ; then
    install_mas_sso
fi

# Deploy and configure Observatorium
if [ "${INSTALL_OBSERVATORIUM:-"n"}" = "y" ]; then
    deploy_observatorium
fi

# Deploy and configure KAS Fleet Manager and its
# dependencies (Observability Operator, Sharded NLB, manual
# terraforming steps ...)
generate_kas_fleet_manager_env_config
deploy_kas_fleet_manager
