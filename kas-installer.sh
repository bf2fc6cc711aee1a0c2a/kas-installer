#!/bin/bash

set -euo pipefail

OS=$(uname)

GIT=$(which git)
OC=$(which oc)
KUBECTL=$(which kubectl)
MAKE=$(which make)
OPENSSL=$(which openssl)

if [ "$OS" = 'Darwin' ]; then
  # for MacOS
  SED=$(which gsed)
else
  # for Linux and Windows
  SED=$(which sed)
fi

DIR_NAME="$(dirname $0)"

KAS_INSTALLER_ENV_FILE="kas-installer.env"

KAS_FLEET_MANAGER_DIR="kas-fleet-manager"
KAS_FLEET_MANAGER_DEPLOY_ENV_FILE="${DIR_NAME}/${KAS_FLEET_MANAGER_DIR}/kas-fleet-manager-deploy.env"

read_kas_installer_env_file() {
  if [ ! -e "${KAS_INSTALLER_ENV_FILE}" ]; then
    echo "Required KAS Installer .env file '${KAS_INSTALLER_ENV_FILE}' does not exist"
    exit 1
  fi

  . ${KAS_INSTALLER_ENV_FILE}

  # Parse the domain reported by cluster-info to ensure a match with the user-configured k8s domain
  K8S_CLUSTER_REPORTED_DOMAIN=$(${OC} cluster-info | grep -o 'is running at .*https.*$' | cut -d '/' -f3 | cut -d ':' -f1 | cut -c5-)

  if [ "${K8S_CLUSTER_REPORTED_DOMAIN}" != "${K8S_CLUSTER_DOMAIN}" ] ; then
      echo "Configured k8s domain '${K8S_CLUSTER_DOMAIN}' is different from domain reported by 'oc cluster-info': '${K8S_CLUSTER_REPORTED_DOMAIN}'"
      echo -n "Proceed with install process? [yN]: "
      read -r proceed

      if [ "$(echo ${proceed} | tr [a-z] [A-Z])" != "Y" ] ; then
          echo "Exiting ${0}"
          exit 1
      else
          echo "Ignoring k8s cluster domain difference..."
      fi
  fi

  # Apply Default values for the optional .env variables
  KAS_FLEET_MANAGER_IMAGE_REGISTRY=${KAS_FLEET_MANAGER_IMAGE_REGISTRY:-quay.io}
  KAS_FLEET_MANAGER_IMAGE_REPOSITORY=${KAS_FLEET_MANAGER_IMAGE_REPOSITORY:-bf2fc6cc711aee1a0c2a82e312df7f2e6b37baa12bd9b1f2fd752e260d93a6f8144ac730947f25caa2bfe6ad0f410da360940ee6d28d6c1688d3822c4055650e/kas-fleet-manager}
  # TODO update this to a 'main' tag by default when it is available
  KAS_FLEET_MANAGER_IMAGE_TAG=${KAS_FLEET_MANAGER_IMAGE_TAG:-main}
  KAS_FLEET_MANAGER_IMAGE_REPOSITORY_USERNAME=${KAS_FLEET_MANAGER_IMAGE_REPOSITORY_USERNAME:-${IMAGE_REPOSITORY_USERNAME}}
  KAS_FLEET_MANAGER_IMAGE_REPOSITORY_PASSWORD=${KAS_FLEET_MANAGER_IMAGE_REPOSITORY_PASSWORD:-${IMAGE_REPOSITORY_PASSWORD}}
  # TODO update this to a 'main' when we have 'main' container image available
  KAS_FLEET_MANAGER_BF2_REF=${KAS_FLEET_MANAGER_BF2_REF:-main}
}

generate_kas_fleet_manager_env_config() {
  echo "Generating KAS Fleet Manager configuration env file '${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE} ...'"
  # Make sure KAS Fleet Manager env file is empty
  > ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "OBSERVABILITY_CONFIG_ACCESS_TOKEN=${OBSERVABILITY_CONFIG_ACCESS_TOKEN}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  # For now image pull secrets for kas fleetshard operator
  # and strimzi operator are not used so we base64 encode
  # an empty json '{}'
  echo "STRIMZI_OPERATOR_IMAGEPULL_SECRET=e30="  >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "KAS_FLEETSHARD_OPERATOR_IMAGEPULL_SECRET=e30=" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "STRIMZI_OPERATOR_NAMESPACE=redhat-managed-kafka-operator" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "KAS_FLEETSHARD_OPERATOR_NAMESPACE=redhat-kas-fleetshard-operator" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "MAS_SSO_BASE_URL=https://$MAS_SSO_ROUTE" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "MAS_SSO_CLIENT_ID=kas-fleet-manager" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "MAS_SSO_CLIENT_SECRET=kas-fleet-manager" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "MAS_SSO_CRT='$MAS_SSO_CERTS'" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "MAS_SSO_REALM=rhoas" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "MAS_SSO_DATA_PLANE_CLUSTER_REALM=rhoas" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "MAS_SSO_DATA_PLANE_CLUSTER_CLIENT_ID=kas-fleetshard-agent" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "MAS_SSO_DATA_PLANE_CLUSTER_CLIENT_SECRET=kas-fleetshard-agent" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "OSD_IDP_MAS_SSO_REALM=rhoas-kafka-sre" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "KAFKA_TLS_CERT=dummyvalue" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "KAFKA_TLS_KEY=dummyvalue" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "IMAGE_REGISTRY=${KAS_FLEET_MANAGER_IMAGE_REGISTRY}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "IMAGE_REPOSITORY=${KAS_FLEET_MANAGER_IMAGE_REPOSITORY}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "IMAGE_TAG=${KAS_FLEET_MANAGER_IMAGE_TAG}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "IMAGE_REPOSITORY_USERNAME=${KAS_FLEET_MANAGER_IMAGE_REPOSITORY_USERNAME}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "IMAGE_REPOSITORY_PASSWORD=${KAS_FLEET_MANAGER_IMAGE_REPOSITORY_PASSWORD}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "KAS_FLEET_MANAGER_BF2_REF=${KAS_FLEET_MANAGER_BF2_REF}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "STRIMZI_OPERATOR_VERSION=${KAS_FLEET_MANAGER_STRIMZI_OPERATOR_VERSION:-\"\"}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "JWKS_URL=https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/certs" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "KAS_FLEET_MANAGER_NAMESPACE=kas-fleet-manager-${USER}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "DATA_PLANE_CLUSTER_CLUSTER_ID=dev-dataplane-cluster" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "DATA_PLANE_CLUSTER_REGION=us-east-1" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "K8S_CLUSTER_DOMAIN=${K8S_CLUSTER_DOMAIN}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "DATA_PLANE_CLUSTER_DNS_NAME=apps.${K8S_CLUSTER_DOMAIN}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "KAFKA_SHARDED_NLB_INGRESS_CONTROLLER_DOMAIN=mk.${K8S_CLUSTER_DOMAIN}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
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

  if [ "${SKIP_SSO:-""}n" = "n" ] || [ "$($OC get route keycloak -n $MAS_SSO_NAMESPACE --template='{{ .spec.host }}' 2>/dev/null)" = "" ] ; then
    echo "MAS SSO route not found or SKIP_SSO not configured, installing MAS SSO ..."
    ${DIR_NAME}/mas-sso/mas-sso-installer.sh
    echo "MAS SSO deployed"
  else
    echo "Skipping MAS SSO installation"
  fi

  export MAS_SSO_ROUTE=$($OC get route keycloak -n $MAS_SSO_NAMESPACE --template='{{ .spec.host }}')
  export MAS_SSO_CERTS=$(echo "" | $OPENSSL s_client -servername $MAS_SSO_ROUTE -connect $MAS_SSO_ROUTE:443 -prexit 2>/dev/null | $OPENSSL x509)
}

deploy_kas_fleetshard() {
  echo "Deploying KAS Fleet Shard ..."
  (cd ${DIR_NAME}/operators && ./install-all.sh) && \
  echo "KAS Fleet Shard deployed" || \
  echo "KAS Fleet Shard failed to deploy"
}

## Main body of the script starts here

read_kas_installer_env_file

# Deploy and configure MAS SSO
install_mas_sso

# Deploy and configure KAS Fleet Manager and its
# dependencies (Observability Operator, Sharded NLB, manual
# terraforming steps ...)
generate_kas_fleet_manager_env_config
deploy_kas_fleet_manager

# Deploy and configure KAS Fleet Shard Operator
if [ "${SKIP_KAS_FLEETSHARD:-""}n" = "n" ]; then
    deploy_kas_fleetshard
fi
