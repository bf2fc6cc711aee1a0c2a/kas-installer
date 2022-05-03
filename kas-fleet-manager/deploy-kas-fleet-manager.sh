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

TERRAFORM_FILES_BASE_DIR="terraforming"
TERRAFORM_TEMPLATES_DIR="${DIR_NAME}/${TERRAFORM_FILES_BASE_DIR}/terraforming-k8s-resources-templates"
TERRAFORM_GENERATED_DIR="${DIR_NAME}/${TERRAFORM_FILES_BASE_DIR}/terraforming-generated-k8s-resources"

KAS_FLEET_MANAGER_DEPLOY_ENV_FILE="${DIR_NAME}/kas-fleet-manager-deploy.env"

OBSERVABILITY_OPERATOR_K8S_NAMESPACE="managed-application-services-observability"
OBSERVABILITY_OPERATOR_DEPLOYMENT_NAME="observability-operator-controller-manager"

generate_kasfleetmanager_manual_terraforming_k8s_resources() {
  ## Generate KAS Fleet Manager manual terraforming resources from template files

  if [ -d "${TERRAFORM_GENERATED_DIR}" ]; then
      # Clean up old generated resources
      rm -rvf ${TERRAFORM_GENERATED_DIR}
  fi

  mkdir -p ${TERRAFORM_GENERATED_DIR}

  # Generate KAS Fleet Shard Operator Addon parameters secret K8s file
  CONTROL_PLANE_API_HOSTNAME="kas-fleet-manager-${KAS_FLEET_MANAGER_NAMESPACE}.apps.${K8S_CLUSTER_DOMAIN}"
  ${SED} \
  "s|#placeholder_data_plane_cluster_id#|${DATA_PLANE_CLUSTER_CLUSTER_ID}| ; \
    s|#placeholder_control_plane_url#|https://${CONTROL_PLANE_API_HOSTNAME}| ; \
    s|#placeholder_sso_auth_server_url#|${MAS_SSO_BASE_URL}/auth/realms/${MAS_SSO_DATA_PLANE_CLUSTER_REALM}| ; \
    s|#placeholder_sso_client_id#|${MAS_SSO_DATA_PLANE_CLUSTER_CLIENT_ID}| ; \
    s|#placeholder_sso_secret#|${MAS_SSO_DATA_PLANE_CLUSTER_CLIENT_SECRET}|" \
    ${TERRAFORM_TEMPLATES_DIR}/009-addon-kas-fleetshard-operator-parameters.yml.template > ${TERRAFORM_GENERATED_DIR}/009-addon-kas-fleetshard-operator-parameters.yml

  # Generate Strimzi Operator Image Pull Secret K8s file
  ${SED} \
  "s/#placeholder_strimzi_imagepull_secret_dockercfg#/${STRIMZI_OPERATOR_IMAGEPULL_SECRET}/" \
    ${TERRAFORM_TEMPLATES_DIR}/010-strimzi-operator-imagepull-secret.yml.template > ${TERRAFORM_GENERATED_DIR}/010-strimzi-operator-imagepull-secret.yml

  # Generate KAS FleetShard Operator Image Pull Secret K8s file
  ${SED} \
  "s/#placeholder_kas_fleetshard_operator_imagepull_secret_dockercfg#/${KAS_FLEETSHARD_OPERATOR_IMAGEPULL_SECRET}/" \
    ${TERRAFORM_TEMPLATES_DIR}/011-kas-fleetshard-operator-imagepull-secret.yml.template > ${TERRAFORM_GENERATED_DIR}/011-kas-fleetshard-operator-imagepull-secret.yml

  # Copy rest of the template files as there are no parameters to replace
  cp -a ${TERRAFORM_TEMPLATES_DIR}/001-mk-storageclass.yml.template ${TERRAFORM_GENERATED_DIR}/001-mk-storageclass.yml
  cp -a ${TERRAFORM_TEMPLATES_DIR}/003-observability-operator-project.yml.template ${TERRAFORM_GENERATED_DIR}/003-observability-operator-project.yml
  cp -a ${TERRAFORM_TEMPLATES_DIR}/005-observability-operator-catalogsource.yml.template ${TERRAFORM_GENERATED_DIR}/005-observability-operator-catalogsource.yml
  cp -a ${TERRAFORM_TEMPLATES_DIR}/006-observability-operator-operatorgroup.yml.template ${TERRAFORM_GENERATED_DIR}/006-observability-operator-operatorgroup.yml
  cp -a ${TERRAFORM_TEMPLATES_DIR}/007-observability-operator-subscription.yml.template ${TERRAFORM_GENERATED_DIR}/007-observability-operator-subscription.yml
}

deploy_kasfleetmanager_manual_terraforming_k8s_resources() {
  create_strimzi_operator_namespace
  create_kas_fleetshard_operator_namespace

  for i in $(find ${TERRAFORM_GENERATED_DIR} -type f | sort); do
    echo "Deploying K8s resource ${i} ..."
    ${OC} apply -f ${i}
  done
}

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
        ${GIT} pull --ff-only)
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
      --docker-server=${IMAGE_REGISTRY}/${IMAGE_REPOSITORY} \
      --docker-username=${IMAGE_REPOSITORY_USERNAME} \
      --docker-password=${IMAGE_REPOSITORY_PASSWORD}

    KAS_FLEET_MANAGER_DEPLOYMENT_K8S_SERVICEACCOUNT="kas-fleet-manager"
    ${OC} secrets link ${KAS_FLEET_MANAGER_DEPLOYMENT_K8S_SERVICEACCOUNT} ${KAS_FLEET_MANAGER_IMAGE_PULL_SECRET_NAME} --for=pull
  fi
}

deploy_kasfleetmanager() {
  create_kas_fleet_manager_namespace

  echo "Deploying KAS Fleet Manager Database..."
  ${OC} process -f ${KAS_FLEET_MANAGER_CODE_DIR}/templates/db-template.yml | oc apply -f - -n ${KAS_FLEET_MANAGER_NAMESPACE}
  echo "Waiting until KAS Fleet Manager Database is ready..."
  time timeout --foreground 3m bash -c "until ${OC} get pods -n ${KAS_FLEET_MANAGER_NAMESPACE}| grep kas-fleet-manager-db | grep -v deploy | grep -q Running; do echo 'database is not ready yet'; sleep 10; done"

  echo "Deploying KAS Fleet Manager K8s Secrets..."
  ${OC} process -f ${KAS_FLEET_MANAGER_CODE_DIR}/templates/secrets-template.yml \
    -p OCM_SERVICE_CLIENT_ID="dummyclient" \
    -p OCM_SERVICE_CLIENT_SECRET="dummysecret" \
    -p OBSERVABILITY_CONFIG_ACCESS_TOKEN="${OBSERVABILITY_CONFIG_ACCESS_TOKEN}" \
    -p MAS_SSO_CLIENT_ID="${MAS_SSO_CLIENT_ID}" \
    -p MAS_SSO_CLIENT_SECRET="${MAS_SSO_CLIENT_SECRET}" \
    -p MAS_SSO_CRT="${MAS_SSO_CRT}" \
    -p KAFKA_TLS_CERT="${KAFKA_TLS_CERT}" \
    -p KAFKA_TLS_KEY="${KAFKA_TLS_KEY}" \
    -p DATABASE_HOST="$(${KUBECTL} get service/kas-fleet-manager-db -o jsonpath="{.spec.clusterIP}")" \
    | ${OC} apply -f - -n ${KAS_FLEET_MANAGER_NAMESPACE}

  echo "Deploying KAS Fleet Manager Envoy ConfigMap..."
  ${OC} apply -f ${KAS_FLEET_MANAGER_CODE_DIR}/templates/envoy-config-configmap.yml -n ${KAS_FLEET_MANAGER_NAMESPACE}

  create_kasfleetmanager_service_account
  create_kasfleetmanager_pull_credentials

  echo "Deploying KAS Fleet Manager..."
  OCM_ENV="development"

  ${OC} process -f ${KAS_FLEET_MANAGER_CODE_DIR}/templates/service-template.yml \
    -p ENVIRONMENT="${OCM_ENV}" \
    -p OCM_URL="https://nonexistingdummyhosttest.com" \
    -p IMAGE_REGISTRY=${IMAGE_REGISTRY} \
    -p IMAGE_REPOSITORY=${IMAGE_REPOSITORY} \
    -p IMAGE_TAG=${IMAGE_TAG} \
    -p IMAGE_PULL_POLICY="Always" \
    -p JWKS_URL="${JWKS_URL}" \
    -p MAS_SSO_BASE_URL="${MAS_SSO_BASE_URL}" \
    -p MAS_SSO_REALM="${MAS_SSO_REALM}" \
    -p OSD_IDP_MAS_SSO_REALM="${OSD_IDP_MAS_SSO_REALM}" \
    -p ENABLE_READY_DATA_PLANE_CLUSTERS_RECONCILE="false" \
    -p DATAPLANE_CLUSTER_SCALING_TYPE="manual" \
    -p CLUSTER_LIST='
- "name": "'${DATA_PLANE_CLUSTER_CLUSTER_ID}'"
  "cluster_id": "'${DATA_PLANE_CLUSTER_CLUSTER_ID}'"
  "client_id": "'${MAS_SSO_DATA_PLANE_CLUSTER_CLIENT_ID}'"
  "cloud_provider": "aws"
  "region": "'${DATA_PLANE_CLUSTER_REGION}'"
  "multi_az": true
  "schedulable": true
  "kafka_instance_limit": 5
  "supported_instance_type": "standard,eval"
  "status": "ready"
  "cluster_dns": "'${DATA_PLANE_CLUSTER_DNS_NAME}'"
' \
    -p SUPPORTED_INSTANCE_TYPES='
- "id": "standard"
  "display_name": "Standard"
  "sizes":
  - "id": "x1"
    "ingressThroughputPerSec": '"${KAFKA_CAPACITY_INGRESS_THROUGHPUT}"'
    "egressThroughputPerSec": '"${KAFKA_CAPACITY_EGRESS_THROUGHPUT}"'
    "totalMaxConnections": '${KAFKA_CAPACITY_TOTAL_MAX_CONNECTIONS}'
    "maxConnectionAttemptsPerSec": '${KAFKA_CAPACITY_MAX_CONNECTION_ATTEMPTS_PER_SEC}'
    "maxDataRetentionSize": '"${KAFKA_CAPACITY_MAX_DATA_RETENTION_SIZE}"'
    "maxDataRetentionPeriod": '"${KAFKA_CAPACITY_MAX_DATA_RETENTION_PERIOD}"'
    "maxPartitions": '${KAFKA_CAPACITY_MAX_PARTITIONS}'
    "quotaConsumed": 1
    "quotaType": "RHOSAK"
    "capacityConsumed": 1
' \
    -p SUPPORTED_CLOUD_PROVIDERS='
- "name": "aws"
  "default": true
  "regions":
    - "name": "'${DATA_PLANE_CLUSTER_REGION}'"
      "default": true
      "supported_instance_type":
        "standard": {}
        "eval": {} 
' \
    -p REPLICAS=1 \
    -p DEX_URL="http://dex-dex.apps.${K8S_CLUSTER_DOMAIN}" \
    -p TOKEN_ISSUER_URL="$(${KUBECTL} get route -n mas-sso keycloak -o jsonpath='https://{.status.ingress[0].host}/auth/realms/rhoas')" \
    -p ENABLE_OCM_MOCK=true \
    -p OBSERVABILITY_CONFIG_REPO="${OBSERVABILITY_CONFIG_REPO}" \
    -p OBSERVABILITY_CONFIG_TAG="${OBSERVABILITY_CONFIG_TAG}" \
    | ${OC} apply -f - -n ${KAS_FLEET_MANAGER_NAMESPACE}

  echo "Waiting until KAS Fleet Manager Deployment is available..."
  ${KUBECTL} wait --timeout=90s --for=condition=available deployment/kas-fleet-manager --namespace=${KAS_FLEET_MANAGER_NAMESPACE}

  echo "Deploying KAS Fleet Manager OCP Route..."
  ${OC} process -f ${KAS_FLEET_MANAGER_CODE_DIR}/templates/route-template.yml | ${OC} apply -f - -n ${KAS_FLEET_MANAGER_NAMESPACE}
}

set_dataplane_cluster_client_id() {
  curr_timestamp=$(${DATE} --utc +%Y-%m-%dT%T)
  UPDATE_SQL_STATEMENT="UPDATE clusters SET client_id = '${MAS_SSO_DATA_PLANE_CLUSTER_CLIENT_ID}' WHERE cluster_id = '${DATA_PLANE_CLUSTER_CLUSTER_ID}'"
  KAS_FLEET_MANAGER_DB_POD=$(${KUBECTL} get pod -n ${KAS_FLEET_MANAGER_NAMESPACE} -l deploymentconfig=kas-fleet-manager-db -o jsonpath="{.items[0].metadata.name}")
  echo "Setting client_id for data plane cluster '${DATA_PLANE_CLUSTER_CLUSTER_ID}' in KAS Fleet Manager database..."
  ${KUBECTL} exec -n ${KAS_FLEET_MANAGER_NAMESPACE} ${KAS_FLEET_MANAGER_DB_POD} -- psql -d kas-fleet-manager -c "${UPDATE_SQL_STATEMENT}"
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

wait_for_observability_operator_availability() {
  OBSERVABILITY_OPERATOR_PROMETHEUS_OPERATOR_DEPLOYMENT_NAME="prometheus-operator"
  OBSERVABILITY_OPERATOR_GRAFANA_OPERATOR_DEPLOYMENT_NAME="grafana-operator"

  wait_for_observability_operator_deployment_availability

  echo "Waiting until Observability operator's Prometheus operator deployment is created..."
  while [ -z "$(kubectl get deployment ${OBSERVABILITY_OPERATOR_PROMETHEUS_OPERATOR_DEPLOYMENT_NAME} --ignore-not-found -o jsonpath=\"{.metadata.name}\" -n ${OBSERVABILITY_OPERATOR_K8S_NAMESPACE})" ]; do
    echo "Deployment ${OBSERVABILITY_OPERATOR_PROMETHEUS_OPERATOR_DEPLOYMENT_NAME} still not created. Waiting..."
    sleep 10
  done

  echo "Waiting until Observability operator's Prometheus operator deployment is available..."
  ${KUBECTL} wait --timeout=120s --for=condition=available deployment/${OBSERVABILITY_OPERATOR_PROMETHEUS_OPERATOR_DEPLOYMENT_NAME} --namespace=${OBSERVABILITY_OPERATOR_K8S_NAMESPACE}

  echo "Waiting until Observability operator's Grafana operator deployment is created..."
  while [ -z "$(kubectl get deployment ${OBSERVABILITY_OPERATOR_GRAFANA_OPERATOR_DEPLOYMENT_NAME} --ignore-not-found -o jsonpath=\"{.metadata.name}\" -n ${OBSERVABILITY_OPERATOR_K8S_NAMESPACE})" ]; do
    echo "Deployment ${OBSERVABILITY_OPERATOR_GRAFANA_OPERATOR_DEPLOYMENT_NAME} still not created. Waiting..."
    sleep 10
  done

  echo "Waiting until Observability operator's Grafana operator deployment is available..."
  ${KUBECTL} wait --timeout=120s --for=condition=available deployment/${OBSERVABILITY_OPERATOR_GRAFANA_OPERATOR_DEPLOYMENT_NAME} --namespace=${OBSERVABILITY_OPERATOR_K8S_NAMESPACE}

  echo "Waiting until Observability CR is in configuration success stage..."
  OBSERVABILITY_CR_CONFIG_READY=0

  while [ ${OBSERVABILITY_CR_CONFIG_READY} -eq 0 ]; do
    OBSERVABILITY_CR_STATUS="$(${KUBECTL} get -n ${OBSERVABILITY_OPERATOR_K8S_NAMESPACE} observability observability-stack -o jsonpath="{.status.stage};{.status.stageStatus}")"
    OBSERVABILITY_CR_STAGE=$(echo -n ${OBSERVABILITY_CR_STATUS} | cut -d';' -f1)
    OBSERVABILITY_CR_STAGE_STATUS=$(echo -n ${OBSERVABILITY_CR_STATUS} | cut -d';' -f2)

    if [ "${OBSERVABILITY_CR_STAGE}" = "configuration" ] && [[ "${OBSERVABILITY_CR_STAGE_STATUS}" =~ (in progress|success) ]]; then
      OBSERVABILITY_CR_CONFIG_READY=1
    else
      echo "Observability CR still not ready. Stage: '${OBSERVABILITY_CR_STAGE}, Stage status: '${OBSERVABILITY_CR_STAGE_STATUS}'"
    fi
  done
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

create_strimzi_operator_namespace() {
  STRIMZI_OPERATOR_NAMESPACE=${STRIMZI_OPERATOR_NAMESPACE}
  create_namespace ${STRIMZI_OPERATOR_NAMESPACE}
}

create_kas_fleetshard_operator_namespace() {
  KAS_FLEETSHARD_OPERATOR_NAMESPACE=${KAS_FLEETSHARD_OPERATOR_NAMESPACE}
  create_namespace ${KAS_FLEETSHARD_OPERATOR_NAMESPACE}
}

create_kas_fleet_manager_namespace() {
  KAS_FLEET_MANAGER_NAMESPACE=${KAS_FLEET_MANAGER_NAMESPACE}
    create_namespace ${KAS_FLEET_MANAGER_NAMESPACE}
}

## Main body of the script starts here

read_kasfleetmanager_env_file
generate_kasfleetmanager_manual_terraforming_k8s_resources
deploy_kasfleetmanager_manual_terraforming_k8s_resources
disable_observability_operator_extras
wait_for_observability_operator_availability
clone_kasfleetmanager_code_repository
deploy_kasfleetmanager
set_dataplane_cluster_client_id

cd ${ORIGINAL_DIR}

exit 0
