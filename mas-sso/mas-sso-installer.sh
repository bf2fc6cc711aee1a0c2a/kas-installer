# install pull secret
set -euo pipefail

DIR_NAME="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
KI_CONFIG="${DIR_NAME}/../kas-installer.env"

source ${KI_CONFIG}
source "${DIR_NAME}/../kas-installer-defaults.env"

OC=$(which oc)

wait_condition() {
    local WAIT_TYPE=${1}
    local WAIT_NAME=${2}
    local WAIT_NAMESPACE=${3}
    local WAIT_CONDITION=${4}
    local WAIT_TIMEOUT=${5}

    while [ -z "$(oc get ${WAIT_TYPE}/${WAIT_NAME} -n ${WAIT_NAMESPACE} --ignore-not-found -o jsonpath=\"{.metadata.name}\")" ]; do
      echo "${WAIT_TYPE} ${WAIT_NAME} still not created. Waiting 10s..."
      sleep 10
    done

    echo "Waiting up to ${WAIT_TIMEOUT} for ${WAIT_TYPE}/${WAIT_NAME} with condition ${WAIT_CONDITION}"
    oc wait ${WAIT_TYPE}/${WAIT_NAME} -n ${WAIT_NAMESPACE} --for=condition=${WAIT_CONDITION} --timeout=${WAIT_TIMEOUT}
    echo "${WAIT_TYPE} ${WAIT_NAME} condition ${WAIT_CONDITION} met"
}

NAMESPACE=mas-sso

if [ -z "$(${OC} get namespace/${NAMESPACE} -o jsonpath="{.metadata.name}" --ignore-not-found)" ]; then
  echo "K8s namespace ${NAMESPACE} does not exist. Creating it..."
  ${OC} create namespace ${NAMESPACE}
fi

${OC} project ${NAMESPACE}
${OC} process -f ${DIR_NAME}/resources/keycloak-operator.yaml -pNAMESPACE=${NAMESPACE} | ${OC} apply -f -
${OC} process -f ${DIR_NAME}/resources/keycloak-postgres.yaml | ${OC} apply -f -

#wait for the CRD
while [ $(${OC} get crd | grep keycloaks.k8s.keycloak.org | wc -l) != 1 ]; do
  echo "Waiting for keycloak CRD to be present"
  sleep 2
done

${OC} delete secret keycloak-db-secret -n ${NAMESPACE} 2>/dev/null || true
${OC} create secret generic keycloak-db-secret -n ${NAMESPACE} \
  --from-literal=username=postgres \
  --from-literal=password=postgrespass

${OC} process -f ${DIR_NAME}/resources/keycloak-instance.yaml -pHOSTNAME="sso-keycloak.apps.${K8S_CLUSTER_DOMAIN}" | ${OC} apply -f -

while [ -z "$(oc get statefulset/sso-keycloak -n ${NAMESPACE} --ignore-not-found -o jsonpath="{.metadata.name}")" ]; do
  echo "statefulset/sso-keycloak still not created. Waiting 3s..."
  sleep 3
done

echo "Waiting for statefulset/sso-keycloak to be ready"
${OC} rollout status --watch --timeout=600s statefulset/sso-keycloak -n ${NAMESPACE}

${OC} process -f ${DIR_NAME}/resources/keycloak-realms.yaml \
  -pRH_USERNAME=${RH_USERNAME} \
  -pRH_USER_ID=${RH_USER_ID} \
  -pRH_ORG_ID=${RH_ORG_ID} \
  | ${OC} apply -f -

wait_condition 'job' 'rhoas' ${NAMESPACE} 'Complete' '90s'
wait_condition 'job' 'rhoas-kafka-sre' ${NAMESPACE} 'Complete' '90s'

echo "Waiting for statefulset/sso-keycloak to be ready following realm imports"
${OC} rollout status --watch --timeout=600s statefulset/sso-keycloak -n ${NAMESPACE}

#${OC} apply -f ${DIR_NAME}/resources/keycloak-route-edge.yaml

echo "********************************************************************************"
echo "* Keycloak endpoint:   https://sso-keycloak.apps.${K8S_CLUSTER_DOMAIN}/auth"
echo "* Keycloak admin user: $(${OC} get secret sso-keycloak-initial-admin -o jsonpath='{.data.username}' | base64 --decode)"
echo "* Keycloak admin pass: $(${OC} get secret sso-keycloak-initial-admin -o jsonpath='{.data.password}' | base64 --decode)"
echo "********************************************************************************"
