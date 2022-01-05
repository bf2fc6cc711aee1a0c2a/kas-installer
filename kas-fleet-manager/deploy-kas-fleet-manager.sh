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
else
  # for Linux and Windows
  SED=$(which sed)
  DATE=$(which date)
fi

ORIGINAL_DIR=$(pwd)

DIR_NAME="$(dirname $0)"

KAS_FLEET_MANAGER_CODE_DIR="${DIR_NAME}/kas-fleet-manager-source"
KAS_FLEET_MANAGER_DEPLOY_ENV_FILE="${DIR_NAME}/kas-fleet-manager-deploy.env"

OBSERVABILITY_OPERATOR_K8S_NAMESPACE="managed-application-services-observability"
OBSERVABILITY_OPERATOR_DEPLOYMENT_NAME="observability-operator-controller-manager"

clone_kasfleetmanager_code_repository() {

  if [ -d "${KAS_FLEET_MANAGER_CODE_DIR}" ]; then
    CURRENT_HASH=$(cd "${KAS_FLEET_MANAGER_CODE_DIR}" && ${GIT} rev-parse HEAD)
    if [ "${CURRENT_HASH}" != "${KAS_FLEET_MANAGER_BF2_REF}" ]; then
      echo "KAS Fleet Manager code directory was stale ${CURRENT_HASH} != ${KAS_FLEET_MANAGER_BF2_REF}. Updating it..."
      # Checkout the configured git ref and pull only if not in detached HEAD state (rc of symbolic-ref == 0)
      (cd ${KAS_FLEET_MANAGER_CODE_DIR} && \
        ${GIT} fetch && \
        ${GIT} checkout ${KAS_FLEET_MANAGER_BF2_REF} && \
        ${GIT} symbolic-ref -q HEAD && \
        ${GIT} pull --ff-only || echo "Skipping 'pull' for detached HEAD")
    fi
  else
    echo "KAS Fleet Manager code directory does not exist. Cloning it..."
    ${GIT} clone "https://${OBSERVABILITY_CONFIG_ACCESS_TOKEN}@github.com/bf2fc6cc711aee1a0c2a/kas-fleet-manager.git" ${KAS_FLEET_MANAGER_CODE_DIR}
    (cd ${KAS_FLEET_MANAGER_CODE_DIR} && ${GIT} checkout ${KAS_FLEET_MANAGER_BF2_REF})
  fi
}

create_kasfleetmanager_service_account() {
  KAS_FLEET_MANAGER_DEPLOYMENT_K8S_SERVICEACCOUNT="kas-fleet-manager"

  KAS_FLEET_MANAGER_SA_YAML=$(cat << EOF
---
kind: ServiceAccount
apiVersion: v1
metadata:
  name: ${KAS_FLEET_MANAGER_DEPLOYMENT_K8S_SERVICEACCOUNT}
  labels:
    app: ${KAS_FLEET_MANAGER_DEPLOYMENT_K8S_SERVICEACCOUNT}
EOF
)

  if [ -z "$(kubectl get sa ${KAS_FLEET_MANAGER_DEPLOYMENT_K8S_SERVICEACCOUNT} --ignore-not-found -o jsonpath=\"{.metadata.name}\" -n ${KAS_FLEET_MANAGER_NAMESPACE})" ]; then
    echo "KAS Fleet Manager service account does not exist. Creating it..."
    echo -n "${KAS_FLEET_MANAGER_SA_YAML}" | ${OC} apply -f - -n ${KAS_FLEET_MANAGER_NAMESPACE}
  fi
}


create_kasfleetmanager_pull_credentials() {
  KAS_FLEET_MANAGER_IMAGE_PULL_SECRET_NAME="kas-fleet-manager-image-pull-secret"
  if [ -z "$(kubectl get secret ${KAS_FLEET_MANAGER_IMAGE_PULL_SECRET_NAME} --ignore-not-found -o jsonpath=\"{.metadata.name}\" -n ${KAS_FLEET_MANAGER_NAMESPACE})" ]; then
    echo "KAS Fleet Manager image pull secret does not exist. Creating it..."
    ${OC} create secret docker-registry ${KAS_FLEET_MANAGER_IMAGE_PULL_SECRET_NAME} \
      --docker-server=${IMAGE_REGISTRY} \
      --docker-username=${IMAGE_REPOSITORY_USERNAME} \
      --docker-password=${IMAGE_REPOSITORY_PASSWORD}

    KAS_FLEET_MANAGER_DEPLOYMENT_K8S_SERVICEACCOUNT="kas-fleet-manager"
    ${OC} secrets link ${KAS_FLEET_MANAGER_DEPLOYMENT_K8S_SERVICEACCOUNT} ${KAS_FLEET_MANAGER_IMAGE_PULL_SECRET_NAME} --for=pull
  fi
}

deploy_kasfleetmanager() {
  create_kas_fleet_manager_namespace

  echo "Deploying KAS Fleet Manager Database..."
  ${OC} process -f ${KAS_FLEET_MANAGER_CODE_DIR}/templates/db-template.yml | ${OC} apply -f - -n ${KAS_FLEET_MANAGER_NAMESPACE}
  echo "Waiting until KAS Fleet Manager Database is ready..."
  time timeout --foreground 3m bash -c "until ${OC} get pods -n ${KAS_FLEET_MANAGER_NAMESPACE}| grep kas-fleet-manager-db | grep -v deploy | grep -q Running; do echo 'database is not ready yet'; sleep 10; done"

  create_kasfleetmanager_service_account
  create_kasfleetmanager_pull_credentials

  echo "Deploying KAS Fleet Manager K8s Secrets..."
  ${OC} process -f ${KAS_FLEET_MANAGER_CODE_DIR}/templates/secrets-template.yml \
    -p OCM_SERVICE_CLIENT_ID="" \
    -p OCM_SERVICE_CLIENT_SECRET="" \
    -p OCM_SERVICE_TOKEN="${OCM_SERVICE_TOKEN}" \
    -p OBSERVABILITY_CONFIG_ACCESS_TOKEN="${OBSERVABILITY_CONFIG_ACCESS_TOKEN}" \
    -p MAS_SSO_CLIENT_ID="${MAS_SSO_CLIENT_ID}" \
    -p MAS_SSO_CLIENT_SECRET="${MAS_SSO_CLIENT_SECRET}" \
    -p OSD_IDP_MAS_SSO_CLIENT_ID="${MAS_SSO_CLIENT_ID}" \
    -p OSD_IDP_MAS_SSO_CLIENT_SECRET="${MAS_SSO_CLIENT_SECRET}" \
    -p MAS_SSO_CRT="${MAS_SSO_CRT}" \
    -p KAFKA_TLS_CERT="${KAFKA_TLS_CERT}" \
    -p KAFKA_TLS_KEY="${KAFKA_TLS_KEY}" \
    -p DATABASE_HOST="$(${KUBECTL} get service/kas-fleet-manager-db -o jsonpath="{.spec.clusterIP}")" \
    -p KUBE_CONFIG="$(${OC} config view --minify --raw | base64 -w0)" \
    -p IMAGE_PULL_DOCKER_CONFIG=$(${OC} get secret ${KAS_FLEET_MANAGER_IMAGE_PULL_SECRET_NAME} -n ${KAS_FLEET_MANAGER_NAMESPACE} -o jsonpath="{.data.\.dockerconfigjson}") \
    | ${OC} apply -f - -n ${KAS_FLEET_MANAGER_NAMESPACE}

  echo "Deploying KAS Fleet Manager Envoy ConfigMap..."
  ${OC} apply -f ${KAS_FLEET_MANAGER_CODE_DIR}/templates/envoy-config-configmap.yml -n ${KAS_FLEET_MANAGER_NAMESPACE}

  echo "Deploying KAS Fleet Manager..."
  OCM_ENV="development"

  SERVICE_PARAMS=${DIR_NAME}/kas-fleet-manager-params.env

  if [ -n "${OCM_SERVICE_TOKEN}" ] ; then
      PROVIDER_TYPE="ocm"
      CLUSTER_STATUS="cluster_provisioned"
      ENABLE_READY_DATA_PLANE_CLUSTERS_RECONCILE="true"

      if [ -n "${STRIMZI_OPERATOR_SUBSCRIPTION_CONFIG}" ] ; then
          echo "WARN: Strimzi operator subscription config will not be used with the 'ocm' cluster provider type"
      fi

      if [ -n "${KAS_FLEETSHARD_OPERATOR_SUBSCRIPTION_CONFIG}" ] ; then
          echo "WARN: Fleetshard operator subscription config will not be used with the 'ocm' cluster provider type"
      fi
  else
      PROVIDER_TYPE="standalone"
      CLUSTER_STATUS="ready"
      ENABLE_READY_DATA_PLANE_CLUSTERS_RECONCILE="false"
  fi

  > ${SERVICE_PARAMS}

  if [ -n "${KAS_FLEET_MANAGER_SERVICE_TEMPLATE_PARAMS:-}" ] ; then
      echo "${KAS_FLEET_MANAGER_SERVICE_TEMPLATE_PARAMS}" >> ${SERVICE_PARAMS}
  fi

  if [ -n "${SUPPORTED_INSTANCE_TYPES:-}" ] ; then
      echo "SUPPORTED_INSTANCE_TYPES='${SUPPORTED_INSTANCE_TYPES}'" >> ${SERVICE_PARAMS}
  fi

  ${OC} process -f ${KAS_FLEET_MANAGER_CODE_DIR}/templates/service-template.yml \
    --param-file=${SERVICE_PARAMS} \
    -p ENVIRONMENT="${OCM_ENV}" \
    -p OCM_URL="https://api.stage.openshift.com" \
    -p IMAGE_REGISTRY=${IMAGE_REGISTRY} \
    -p IMAGE_REPOSITORY=${IMAGE_REPOSITORY} \
    -p IMAGE_TAG=${IMAGE_TAG} \
    -p IMAGE_PULL_POLICY="Always" \
    -p JWKS_URL="${JWKS_URL}" \
    -p MAS_SSO_BASE_URL="${MAS_SSO_BASE_URL}" \
    -p MAS_SSO_REALM="${MAS_SSO_REALM}" \
    -p OSD_IDP_MAS_SSO_REALM="${OSD_IDP_MAS_SSO_REALM}" \
    -p ENABLE_READY_DATA_PLANE_CLUSTERS_RECONCILE="${ENABLE_READY_DATA_PLANE_CLUSTERS_RECONCILE}" \
    -p SERVICE_PUBLIC_HOST_URL="https://kas-fleet-manager-${KAS_FLEET_MANAGER_NAMESPACE}.apps.${K8S_CLUSTER_DOMAIN}" \
    -p DATAPLANE_CLUSTER_SCALING_TYPE="manual" \
    -p CLUSTER_LIST='
- "name": "'$(${OC} config view --minify --raw | yq e '.contexts[0].name' -)'"
  "provider_type": "'${PROVIDER_TYPE}'"
  "cluster_id": "'${DATA_PLANE_CLUSTER_CLUSTER_ID}'"
  "cloud_provider": "aws"
  "region": "'${DATA_PLANE_CLUSTER_REGION}'"
  "multi_az": true
  "schedulable": true
  "kafka_instance_limit": 5
  "supported_instance_type": "standard,developer"
  "status": "'${CLUSTER_STATUS}'"
  "cluster_dns": "'${DATA_PLANE_CLUSTER_DNS_NAME}'"
' \
    -p SUPPORTED_CLOUD_PROVIDERS='
- "name": "aws"
  "default": true
  "regions":
    - "name": "'${DATA_PLANE_CLUSTER_REGION}'"
      "default": true
      "supported_instance_type":
        "standard": {}
        "developer": {}
' \
    -p STRIMZI_OPERATOR_SUBSCRIPTION_CONFIG="${STRIMZI_OPERATOR_SUBSCRIPTION_CONFIG}" \
    -p KAS_FLEETSHARD_OPERATOR_SUBSCRIPTION_CONFIG="${KAS_FLEETSHARD_OPERATOR_SUBSCRIPTION_CONFIG}" \
    -p REPLICAS=1 \
    -p DEX_URL="http://dex-dex.apps.${K8S_CLUSTER_DOMAIN}" \
    -p TOKEN_ISSUER_URL="$(${KUBECTL} get route -n mas-sso keycloak -o jsonpath='https://{.status.ingress[0].host}/auth/realms/rhoas')" \
    -p ENABLE_OCM_MOCK=true \
    -p OBSERVABILITY_CONFIG_REPO="${OBSERVABILITY_CONFIG_REPO}" \
    -p OBSERVABILITY_CONFIG_TAG="${OBSERVABILITY_CONFIG_TAG}" \
    -p STRIMZI_OLM_INDEX_IMAGE="${STRIMZI_OLM_INDEX_IMAGE}" \
    -p STRIMZI_OLM_PACKAGE_NAME='kas-strimzi-bundle' \
    -p KAS_FLEETSHARD_OLM_INDEX_IMAGE="${KAS_FLEETSHARD_OLM_INDEX_IMAGE}" \
    -p KAS_FLEETSHARD_OLM_PACKAGE_NAME='kas-fleetshard-operator' \
    | ${OC} apply -f - -n ${KAS_FLEET_MANAGER_NAMESPACE}

  echo "Waiting until KAS Fleet Manager Deployment is available..."
  ${KUBECTL} wait --timeout=90s --for=condition=available deployment/kas-fleet-manager --namespace=${KAS_FLEET_MANAGER_NAMESPACE}

  echo "Deploying KAS Fleet Manager OCP Route..."
  ${OC} process -f ${KAS_FLEET_MANAGER_CODE_DIR}/templates/route-template.yml | ${OC} apply -f - -n ${KAS_FLEET_MANAGER_NAMESPACE}
}

read_kasfleetmanager_env_file() {
  if [ ! -e "${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}" ]; then
    echo "Required KAS Fleet Manager deployment .env file '${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}' does not exist"
    exit 1
  fi

  . ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
}

wait_for_observability_operator_deployment_availability() {
  echo "Waiting until Observability operator deployment is created..."
  while [ -z "$(kubectl get deployment ${OBSERVABILITY_OPERATOR_DEPLOYMENT_NAME} --ignore-not-found -o jsonpath=\"{.metadata.name}\" -n ${OBSERVABILITY_OPERATOR_K8S_NAMESPACE})" ]; do
    echo "Deployment ${OBSERVABILITY_OPERATOR_DEPLOYMENT_NAME} still not created. Waiting..."
    sleep 10
  done

  echo "Waiting until Observability operator deployment is available..."
  ${KUBECTL} wait --timeout=120s --for=condition=available deployment/${OBSERVABILITY_OPERATOR_DEPLOYMENT_NAME} --namespace=${OBSERVABILITY_OPERATOR_K8S_NAMESPACE}
}

disable_observability_operator_extras() {
  wait_for_observability_operator_deployment_availability
  echo "Waiting until Observability CR is created..."
  OBSERVABILITY_CR_NAME="observability-stack"
  while [ -z "$(kubectl get Observability ${OBSERVABILITY_CR_NAME} --ignore-not-found -o jsonpath=\"{.metadata.name}\" -n ${OBSERVABILITY_OPERATOR_K8S_NAMESPACE})" ]; do
    echo "Observability CR ${OBSERVABILITY_CR_NAME} still not created. Waiting..."
    sleep 3
  done

  echo "Patching Observability CR to disable Observatorium, PagerDuty and DeadmanSnitch functionality"
  OBSERVABILITY_MERGE_PATCH_CONTENT=$(cat << EOF
{
  "spec": {
    "selfContained": {
      "disablePagerDuty": true,
      "disableObservatorium": true,
      "disableDeadmansSnitch": true
    }
  }
}
EOF
)
  ${KUBECTL} patch Observability observability-stack --type=merge --patch "${OBSERVABILITY_MERGE_PATCH_CONTENT}" -n ${OBSERVABILITY_OPERATOR_K8S_NAMESPACE}
}

create_namespace() {
    INPUT_NAMESPACE="$1"
    if [ -z "$(${OC} get project/${INPUT_NAMESPACE} -o jsonpath="{.metadata.name}" --ignore-not-found)" ]; then
      echo "K8s namespace ${INPUT_NAMESPACE} does not exist. Creating it..."
      ${OC} new-project ${INPUT_NAMESPACE}
    fi
}

delete_namespace() {
    INPUT_NAMESPACE="$1"
    if [ ! -z "$(${OC} get project/${INPUT_NAMESPACE} -o jsonpath="{.metadata.name}" --ignore-not-found)" ]; then
      echo "Deleting K8s namespace ${INPUT_NAMESPACE} ..."
      ${OC} delete project ${INPUT_NAMESPACE}
    fi
}

create_kas_fleet_manager_namespace() {
  KAS_FLEET_MANAGER_NAMESPACE=${KAS_FLEET_MANAGER_NAMESPACE}
    create_namespace ${KAS_FLEET_MANAGER_NAMESPACE}
}

## Main body of the script starts here

read_kasfleetmanager_env_file
clone_kasfleetmanager_code_repository
deploy_kasfleetmanager
disable_observability_operator_extras

cd ${ORIGINAL_DIR}

exit 0
