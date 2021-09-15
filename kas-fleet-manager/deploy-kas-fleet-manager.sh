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

  # Generate Sharded NLB IngressController K8s file
  ${SED} \
  "s/#placeholder_domain#/${KAFKA_SHARDED_NLB_INGRESS_CONTROLLER_DOMAIN}/" \
    ${TERRAFORM_TEMPLATES_DIR}/002-sharded-nlb-ingresscontroller.yml.template > ${TERRAFORM_GENERATED_DIR}/002-sharded-nlb-ingresscontroller.yml

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
      (cd ${KAS_FLEET_MANAGER_CODE_DIR} && ${GIT} pull --ff-only && ${GIT} checkout ${KAS_FLEET_MANAGER_BF2_REF})
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
	time timeout --foreground 3m bash -c "until ${OC} get pods | grep kas-fleet-manager-db | grep -v deploy | grep -q Running; do echo 'database is not ready yet'; sleep 10; done"

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
    -p DATAPLANE_CLUSTER_SCALING_TYPE="none" \
    -p REPLICAS=1 \
    -p STRIMZI_OPERATOR_VERSION="${STRIMZI_OPERATOR_VERSION}" \
    -p KAFKA_CAPACITY_INGRESS_THROUGHPUT="${KAFKA_CAPACITY_INGRESS_THROUGHPUT}" \
    | ${OC} apply -f - -n ${KAS_FLEET_MANAGER_NAMESPACE}
  
  echo "${KAFKA_CAPACITY_INGRESS_THROUGHPUT}"
  echo "Waiting until KAS Fleet Manager Deployment is available..."
  ${KUBECTL} wait --timeout=90s --for=condition=available deployment/kas-fleet-manager --namespace=${KAS_FLEET_MANAGER_NAMESPACE}

  echo "Deploying KAS Fleet Manager OCP Route..."
  ${OC} process -f ${KAS_FLEET_MANAGER_CODE_DIR}/templates/route-template.yml | ${OC} apply -f - -n ${KAS_FLEET_MANAGER_NAMESPACE}
}

add_dataplane_cluster_to_kasfleetmanager_db() {
  curr_timestamp=$(${DATE} --utc +%Y-%m-%dT%T)
  INSERT_SQL_STATEMENT="INSERT INTO clusters (id, created_at, updated_at, cloud_provider, cluster_id, external_id, multi_az, region, status, cluster_dns) VALUES ('${DATA_PLANE_CLUSTER_CLUSTER_ID}', '${curr_timestamp}', '${curr_timestamp}', 'aws', '${DATA_PLANE_CLUSTER_CLUSTER_ID}', '${DATA_PLANE_CLUSTER_CLUSTER_ID}', 'true', '${DATA_PLANE_CLUSTER_REGION}', 'waiting_for_kas_fleetshard_operator', '${DATA_PLANE_CLUSTER_DNS_NAME}')"
  KAS_FLEET_MANAGER_DB_POD=$(${KUBECTL} get pod -n ${KAS_FLEET_MANAGER_NAMESPACE} -l deploymentconfig=kas-fleet-manager-db -o jsonpath="{.items[0].metadata.name}")
  echo "Adding data plane cluster '${DATA_PLANE_CLUSTER_CLUSTER_ID}' to KAS Fleet Manager database..."
  ${KUBECTL} exec -n ${KAS_FLEET_MANAGER_NAMESPACE} ${KAS_FLEET_MANAGER_DB_POD} -- psql -d kas-fleet-manager -c "${INSERT_SQL_STATEMENT}"
}

read_kasfleetmanager_env_file() {
  if [ ! -e "${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}" ]; then
    echo "Required KAS Fleet Manager deployment .env file '${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}' does not exist"
    exit 1
  fi

  . ${KAS_FLEET_MANAGER_DEPLOY_ENV_FILE}
}

wait_for_sharded_nlb_ingresscontroller_availability() {
  # When creating the sharded NLB IngressController a deployment named "router-<ingresscontrollername>"
  # is created in the openshift-ingress namespace.
  echo "Waiting until Sharded NLB deployment is available..."
  ${KUBECTL} wait --timeout=90s --for=condition=available deployment/router-sharded-nlb --namespace=openshift-ingress

  # TODO check some states of the IngressController status sections? related to DNS stuff? related to AWS LB stuff?
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
  OBSERVABILITY_OPERATOR_GRAFANA_DEPLOYMENT_NAME="grafana-deployment"

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

  echo "Waiting until Observability operator's Grafana deployment is created..."
  while [ -z "$(kubectl get deployment ${OBSERVABILITY_OPERATOR_GRAFANA_DEPLOYMENT_NAME} --ignore-not-found -o jsonpath=\"{.metadata.name}\" -n ${OBSERVABILITY_OPERATOR_K8S_NAMESPACE})" ]; do
    echo "Deployment ${OBSERVABILITY_OPERATOR_GRAFANA_DEPLOYMENT_NAME} still not created. Waiting..."
    sleep 10
  done

  echo "Waiting until Observability operator's Grafana deployment is available..."
  ${KUBECTL} wait --timeout=120s --for=condition=available deployment/${OBSERVABILITY_OPERATOR_GRAFANA_DEPLOYMENT_NAME} --namespace=${OBSERVABILITY_OPERATOR_K8S_NAMESPACE}

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
wait_for_sharded_nlb_ingresscontroller_availability
disable_observability_operator_extras
wait_for_observability_operator_availability
clone_kasfleetmanager_code_repository
deploy_kasfleetmanager
add_dataplane_cluster_to_kasfleetmanager_db

cd ${ORIGINAL_DIR}

exit 0
