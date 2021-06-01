#!/bin/bash

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
KAS_FLEET_MANAGER_DEPLOY_ENV_FILE="kas-fleet-manager-deploy.env"

read_kas_installer_env_file() {
  if [ ! -e "${KAS_INSTALLER_ENV_FILE}" ]; then
    echo "Required KAS Installer .env file '${KAS_INSTALLER_ENV_FILE}' does not exist"
    exit 1
  fi

  . ${KAS_INSTALLER_ENV_FILE}
}

generate_kas_fleet_manager_env_config() {
  echo "Generating KAS Fleet Manager configuration env file '${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE} ...'"
  # Make sure KAS Fleet Manager env file is empty
  > ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "OBSERVABILITY_CONFIG_ACCESS_TOKEN=${OBSERVABILITY_CONFIG_ACCESS_TOKEN}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "STRIMZI_OPERATOR_IMAGEPULL_SECRET=dummydockercfgsecret"  >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "KAS_FLEETSHARD_OPERATOR_IMAGEPULL_SECRET=dummydockercfgsecret" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "MAS_SSO_BASE_URL=https://$MAS_SSO_ROUTE" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "MAS_SSO_CLIENT_ID=kas-fleet-manager" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "MAS_SSO_CLIENT_SECRET=kas-fleet-manager" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "MAS_SSO_CRT=$MAS_SSO_CERTS" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "MAS_SSO_REALM=rhoas" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "MAS_SSO_DATA_PLANE_CLUSTER_REALM=rhoas" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "MAS_SSO_DATA_PLANE_CLUSTER_CLIENT_ID=kas-fleetshard-agent" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "MAS_SSO_DATA_PLANE_CLUSTER_CLIENT_SECRET=kas-fleetshard-agent" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "OSD_IDP_MAS_SSO_REALM=rhoas-kafka-sre" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  
  echo "KAFKA_TLS_CERT=dummyvalue" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "KAFKA_TLS_KEY=dummyvalue" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "IMAGE_REGISTRY=quay.io" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "IMAGE_REPOSITORY=rhoas/kas-fleet-manager" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "IMAGE_TAG=087b478" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "IMAGE_REPOSITORY_USERNAME=${IMAGE_REPOSITORY_USERNAME}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "IMAGE_REPOSITORY_PASSWORD=${IMAGE_REPOSITORY_PASSWORD}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "KAS_FLEET_MANAGER_BF2_REF=e7df1ec6f408e8079f8bb462f416536788500f10" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}

  echo "JWKS_URL=https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/certs" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "KAS_FLEET_MANAGER_NAMESPACE=kas-fleet-manager-${USER}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "DATA_PLANE_CLUSTER_CLUSTER_ID=dev-dataplane-cluster" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "DATA_PLANE_CLUSTER_REGION=us-east-1" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "DATA_PLANE_CLUSTER_DNS_NAME=mk.${K8S_CLUSTER_DOMAIN}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
  echo "KAFKA_SHARDED_NLB_INGRESS_CONTROLLER_DOMAIN=mk.${K8S_CLUSTER_DOMAIN}" >> ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
}

deploy_kas_fleet_manager() {
  echo "Deploying KAS Fleet Manager ..."
  ${DIR_NAME}/deploy-kas-fleet-manager.sh
  echo "KAS Fleet Manager deployed"
}

install_mas_sso() {
  echo "Installing MAS SSO ... "
  export DOCKER_USER_NAME=${IMAGE_REPOSITORY_USERNAME}
  export DOCKER_PASSWORD=${IMAGE_REPOSITORY_PASSWORD}
  export MAS_SSO_NAMESPACE=mas-sso
  ./mas-sso-installer.sh
  export MAS_SSO_ROUTE=$($OC get route keycloak -n $MAS_SSO_NAMESPACE --template='{{ .spec.host }}')
  export MAS_SSO_CERTS=$(echo "" | $OPENSSL s_client -servername $MAS_SSO_ROUTE -connect $MAS_SSO_ROUTE:443 -prexit 2>/dev/null | $SED -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p')
  echo "MAS SSO deployed"
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

