#!/bin/bash

set -euo pipefail

OS=$(uname)

GIT=$(which git)
OC=$(which oc)
KUBECTL=$(which kubectl)
MAKE=$(which make)

if [ "$OS" = 'Darwin' ]; then
  # for MacOS
  SED=$(which gsed)
  DATE=$(which gdate)
  BASE64=$(which gbase64)
else
  # for Linux and Windows
  SED=$(which sed)
  DATE=$(which date)
  BASE64=$(which base64)
fi

DIR_NAME="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
COS_FLEET_MANAGER_CODE_DIR="${DIR_NAME}/cos-fleet-manager-source"
KAS_INSTALLER_RUNTIME_ENV_FILE="${DIR_NAME}/../kas-installer-runtime.env"
SERVICE_PARAMS=${DIR_NAME}/cos-fleet-manager-params.env

OBSERVABILITY_OPERATOR_K8S_NAMESPACE="managed-application-services-observability"
OBSERVABILITY_OPERATOR_DEPLOYMENT_NAME="observability-operator-controller-manager"

clone_kasfleetmanager_code_repository() {
  if [ -d "${COS_FLEET_MANAGER_CODE_DIR}" ]; then
    CONFIGURED_GIT="${COS_FLEET_MANAGER_GIT_URL}:${COS_FLEET_MANAGER_GIT_REF}"
    CURRENT_GIT=$(cd "${COS_FLEET_MANAGER_CODE_DIR}" && echo "$(${GIT} remote get-url origin):$(${GIT} rev-parse HEAD)")

    if [ "${CURRENT_GIT}" != "${CONFIGURED_GIT}" ] ; then
      echo "Refreshing COS Fleet Manager code directory (current ${CURRENT_GIT} != configured ${CONFIGURED_GIT})"
      # Checkout the configured git ref and pull only if not in detached HEAD state (rc of symbolic-ref == 0)
      (cd ${COS_FLEET_MANAGER_CODE_DIR} && \
        ${GIT} remote set-url origin ${COS_FLEET_MANAGER_GIT_URL}
        ${GIT} fetch origin && \
        ${GIT} checkout ${COS_FLEET_MANAGER_GIT_REF} && \
        ${GIT} symbolic-ref -q HEAD && \
          ${GIT} reset --hard origin/${COS_FLEET_MANAGER_GIT_REF} || \
          echo "Skipping 'pull' for detached HEAD")
    else
      echo "COS Fleet Manager code directory is current, not refreshing"
    fi
  else
    echo "COS Fleet Manager code directory does not exist. Cloning it..."
    ${GIT} clone "${COS_FLEET_MANAGER_GIT_URL}" ${COS_FLEET_MANAGER_CODE_DIR}
    (cd ${COS_FLEET_MANAGER_CODE_DIR} && ${GIT} checkout ${COS_FLEET_MANAGER_GIT_REF})
  fi

  if [ "${COS_FLEET_MANAGER_IMAGE_BUILD}" = "true" ] ; then
      COS_FLEET_MANAGER_IMAGE_REGISTRY='image-registry.openshift-image-registry.svc:5000'
      COS_FLEET_MANAGER_IMAGE_REPOSITORY=${COS_FLEET_MANAGER_NAMESPACE}/cos-fleet-manager

      (cd ${COS_FLEET_MANAGER_CODE_DIR} && \
        make docker/login/internal && \
        make image/build/push/internal NAMESPACE=${COS_FLEET_MANAGER_NAMESPACE} IMAGE_TAG=${COS_FLEET_MANAGER_IMAGE_TAG} && \
        ${DOCKER:-docker} image rm -f "$(${OC} get route default-route -n openshift-image-registry -o jsonpath="{.spec.host}")/${COS_FLEET_MANAGER_IMAGE_REPOSITORY}:${COS_FLEET_MANAGER_IMAGE_TAG}")
  fi
}

create_kasfleetmanager_service_account() {
  COS_FLEET_MANAGER_DEPLOYMENT_K8S_SERVICEACCOUNT="cos-fleet-manager"

  COS_FLEET_MANAGER_SA_YAML=$(cat << EOF
---
kind: ServiceAccount
apiVersion: v1
metadata:
  name: ${COS_FLEET_MANAGER_DEPLOYMENT_K8S_SERVICEACCOUNT}
  labels:
    app: ${COS_FLEET_MANAGER_DEPLOYMENT_K8S_SERVICEACCOUNT}
EOF
)

  if [ -z "$(${KUBECTL} get sa ${COS_FLEET_MANAGER_DEPLOYMENT_K8S_SERVICEACCOUNT} --ignore-not-found -o jsonpath=\"{.metadata.name}\" -n ${COS_FLEET_MANAGER_NAMESPACE})" ]; then
    echo "COS Fleet Manager service account does not exist. Creating it..."
    echo -n "${COS_FLEET_MANAGER_SA_YAML}" | ${OC} apply -f - -n ${COS_FLEET_MANAGER_NAMESPACE}
  fi
}

create_kasfleetmanager_pull_credentials() {
  COS_FLEET_MANAGER_IMAGE_PULL_SECRET_NAME="cos-pull-secret"
  if [ -z "$(${KUBECTL} get secret ${COS_FLEET_MANAGER_IMAGE_PULL_SECRET_NAME} --ignore-not-found -o jsonpath=\"{.metadata.name}\" -n ${COS_FLEET_MANAGER_NAMESPACE})" ]; then
    echo "COS Fleet Manager image pull secret does not exist. Creating it..."
    ${OC} create secret docker-registry ${COS_FLEET_MANAGER_IMAGE_PULL_SECRET_NAME} \
      -n ${COS_FLEET_MANAGER_NAMESPACE} \
      --docker-server=${COS_FLEET_MANAGER_IMAGE_REGISTRY} \
      --docker-username=${COS_FLEET_MANAGER_IMAGE_REPOSITORY_USERNAME} \
      --docker-password=${COS_FLEET_MANAGER_IMAGE_REPOSITORY_PASSWORD}

    COS_FLEET_MANAGER_DEPLOYMENT_K8S_SERVICEACCOUNT="cos-fleet-manager"
    ${OC} secrets link ${COS_FLEET_MANAGER_DEPLOYMENT_K8S_SERVICEACCOUNT} ${COS_FLEET_MANAGER_IMAGE_PULL_SECRET_NAME} -n ${COS_FLEET_MANAGER_NAMESPACE} --for=pull
  fi
}

deploy_kasfleetmanager() {
  echo "Deploying COS Fleet Manager Database..."
  ${OC} process -f ${COS_FLEET_MANAGER_CODE_DIR}/templates/db-template.yml -n ${COS_FLEET_MANAGER_NAMESPACE} \
    | ${OC} apply -f - -n ${COS_FLEET_MANAGER_NAMESPACE}
  echo "Waiting until COS Fleet Manager Database is ready..."
  ${OC} wait DeploymentConfig/cos-fleet-manager-db -n ${COS_FLEET_MANAGER_NAMESPACE} --for=condition=available --timeout=180s

  create_kasfleetmanager_service_account
  create_kasfleetmanager_pull_credentials

  echo "Deploying COS Fleet Manager K8s Secrets..."
  SECRET_PARAMS=${DIR_NAME}/cos-fleet-manager-secrets.env
  > ${SECRET_PARAMS}

  if [ "${SSO_PROVIDER_TYPE}" = "redhat_sso" ] ; then
    echo "SSO_CLIENT_ID='${REDHAT_SSO_CLIENT_ID}'" >> ${SECRET_PARAMS}
    echo "SSO_CLIENT_SECRET='${REDHAT_SSO_CLIENT_SECRET}'" >> ${SECRET_PARAMS}
  else
    echo "MAS_SSO_CLIENT_ID='${MAS_SSO_CLIENT_ID}'" >> ${SECRET_PARAMS}
    echo "MAS_SSO_CLIENT_SECRET='${MAS_SSO_CLIENT_SECRET}'" >> ${SECRET_PARAMS}
  fi

  if [ -n "${COS_FLEET_MANAGER_SECRETS_TEMPLATE_PARAMS:-}" ] ; then
      if [ -x "${COS_FLEET_MANAGER_SECRETS_TEMPLATE_PARAMS}" ] ; then
          echo "Executing ${COS_FLEET_MANAGER_SECRETS_TEMPLATE_PARAMS} to generate user-supplied secrets-template.yml parameters"
          ${COS_FLEET_MANAGER_SECRETS_TEMPLATE_PARAMS} >> ${SECRET_PARAMS}
      else
          echo "Found ${COS_FLEET_MANAGER_SECRETS_TEMPLATE_PARAMS} script, but having no executable permission. Ignoring it."
      fi
  fi

  ${OC} process -f ${COS_FLEET_MANAGER_CODE_DIR}/templates/secrets-template.yml -n ${COS_FLEET_MANAGER_NAMESPACE} \
    --param-file=${SECRET_PARAMS} \
    -p OCM_SERVICE_CLIENT_ID="" \
    -p OCM_SERVICE_CLIENT_SECRET="" \
    -p OCM_SERVICE_TOKEN="${OCM_SERVICE_TOKEN}" \
    -p MAS_SSO_CRT="${SSO_TRUSTED_CA}" \
    | ${OC} apply -f - -n ${COS_FLEET_MANAGER_NAMESPACE}

  echo "Deploying COS Fleet Manager Envoy ConfigMap..."
  ${OC} apply -f ${COS_FLEET_MANAGER_CODE_DIR}/templates/envoy-config-configmap.yml -n ${COS_FLEET_MANAGER_NAMESPACE}

  echo "Deploying COS Fleet Manager..."
  OCM_ENV="development"
  CLUSTER_STATUS="cluster_provisioned"

  for template in cos-fleet-catalog-camel.yaml \
                  cos-fleet-catalog-debezium.yaml \
                  connector-metadata-camel-template.yaml \
                  connector-metadata-debezium-template.yaml \
                  connectors-quota-configuration.yml ;
  do
      ${OC} process -f ${COS_FLEET_MANAGER_CODE_DIR}/templates/${template} -n ${COS_FLEET_MANAGER_NAMESPACE} \
        | oc delete -f - -n ${COS_FLEET_MANAGER_NAMESPACE} >/dev/null 2>&1 || true

      ${OC} process -f ${COS_FLEET_MANAGER_CODE_DIR}/templates/${template} -n ${COS_FLEET_MANAGER_NAMESPACE} \
        | oc create -f - -n ${COS_FLEET_MANAGER_NAMESPACE}
  done

  > ${SERVICE_PARAMS}

  if [ -n "${OCM_SERVICE_TOKEN}" ] ; then
      ENABLE_OCM_MOCK="false"
      echo 'OCM_URL="https://api.stage.openshift.com"' >> ${SERVICE_PARAMS}
  else
      ENABLE_OCM_MOCK="true"
  fi

  if [ -n "${COS_FLEET_MANAGER_SERVICE_TEMPLATE_PARAMS:-}" ]; then
      if [ -x "${COS_FLEET_MANAGER_SERVICE_TEMPLATE_PARAMS}" ]; then
          echo "Executing ${COS_FLEET_MANAGER_SERVICE_TEMPLATE_PARAMS} to generate user-supplied service-template.yml parameters"
          ${COS_FLEET_MANAGER_SERVICE_TEMPLATE_PARAMS} >> ${SERVICE_PARAMS}
      else
          echo "Found ${COS_FLEET_MANAGER_SERVICE_TEMPLATE_PARAMS} script, but having no executable permission. Ignoring it."
      fi
  fi

  echo "REDHAT_SSO_BASE_URL='${REDHAT_SSO_BASE_URL}'" >> ${SERVICE_PARAMS}

  echo "Setting Admin API SSO configuration to ${ADMIN_API_SSO_BASE_URL} with realm ${ADMIN_API_SSO_REALM}"
  echo "ADMIN_API_SSO_BASE_URL=${ADMIN_API_SSO_BASE_URL}" >> ${SERVICE_PARAMS}
  echo "ADMIN_API_SSO_ENDPOINT_URI=${ADMIN_API_SSO_ENDPOINT_URI}" >> ${SERVICE_PARAMS}
  echo "ADMIN_API_SSO_REALM=${ADMIN_API_SSO_REALM}" >> ${SERVICE_PARAMS}

  if [ -n "$(${KUBECTL} get deployment cos-fleet-manager --ignore-not-found -o jsonpath=\"{.metadata.name}\" -n ${COS_FLEET_MANAGER_NAMESPACE})" ] ; then
      echo "Scaling down existing cos-fleet-manager deployment to apply changes"
      ${KUBECTL} scale deployment/cos-fleet-manager --replicas=0 -n ${COS_FLEET_MANAGER_NAMESPACE}
  fi

  ${OC} process -f ${COS_FLEET_MANAGER_CODE_DIR}/templates/service-template.yml -n ${COS_FLEET_MANAGER_NAMESPACE} \
    --param-file=${SERVICE_PARAMS} \
    -p ENVIRONMENT="${OCM_ENV}" \
    -p IMAGE_REGISTRY=${COS_FLEET_MANAGER_IMAGE_REGISTRY} \
    -p IMAGE_REPOSITORY=${COS_FLEET_MANAGER_IMAGE_REPOSITORY} \
    -p IMAGE_TAG=${COS_FLEET_MANAGER_IMAGE_TAG} \
    -p JWKS_URL="${JWKS_URL}" \
    -p SSO_PROVIDER_TYPE="${SSO_PROVIDER_TYPE}" \
    -p MAS_SSO_BASE_URL="${MAS_SSO_BASE_URL}" \
    -p MAS_SSO_REALM="${MAS_SSO_REALM}" \
    -p OSD_IDP_MAS_SSO_REALM="${OSD_IDP_MAS_SSO_REALM}" \
    -p SERVICE_PUBLIC_HOST_URL="https://${MAS_FLEET_MANAGEMENT_DOMAIN}" \
    -p REPLICAS=1 \
    -p TOKEN_ISSUER_URL="${SSO_REALM_URL}" \
    -p ENABLE_OCM_MOCK="${ENABLE_OCM_MOCK}" \
    -p OBSERVABILITY_CONFIG_REPO="${OBSERVABILITY_CONFIG_REPO}" \
    -p OBSERVABILITY_CONFIG_TAG="${OBSERVABILITY_CONFIG_TAG}" \
    -p CONNECTOR_EVAL_ORGANIZATIONS='[]' \
    | ${OC} apply -f - -n ${COS_FLEET_MANAGER_NAMESPACE}

  echo "Waiting until COS Fleet Manager Deployment is available..."
  ${KUBECTL} wait --timeout=120s --for=condition=available deployment/cos-fleet-manager --namespace=${COS_FLEET_MANAGER_NAMESPACE}

  echo "Deploying COS Fleet Manager OCP Route..."
  ${OC} process -f ${COS_FLEET_MANAGER_CODE_DIR}/templates/route-template.yml -n ${COS_FLEET_MANAGER_NAMESPACE} | \
    jq '.items[0].spec.host = "'"${MAS_FLEET_MANAGEMENT_DOMAIN}"'" | .items[0].spec.path = "/api/connector_mgmt"' | \
    ${OC} apply -f - -n ${COS_FLEET_MANAGER_NAMESPACE}
}

read_kasinstaller_env_file() {
  if [ ! -e "${KAS_INSTALLER_RUNTIME_ENV_FILE}" ]; then
    echo "Required kas-installer runtime .env file '${KAS_INSTALLER_RUNTIME_ENV_FILE}' does not exist"
    exit 1
  fi

  . ${KAS_INSTALLER_RUNTIME_ENV_FILE}
}

create_namespace() {
    INPUT_NAMESPACE="${1}"

    if [ -z "$(${OC} get namespace/${INPUT_NAMESPACE} -o jsonpath="{.metadata.name}" --ignore-not-found)" ]; then
        echo "K8s namespace ${INPUT_NAMESPACE} does not exist. Creating it..."
        ${OC} create namespace ${INPUT_NAMESPACE}
    fi
}

create_kas_fleet_manager_namespace() {
    create_namespace ${COS_FLEET_MANAGER_NAMESPACE}
}

## Main body of the script starts here

read_kasinstaller_env_file
create_kas_fleet_manager_namespace
clone_kasfleetmanager_code_repository
deploy_kasfleetmanager

exit 0
