# install pull secret
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

wait_status() {
    local RESOURCE_TYPE=${1}
    local RESOURCE_NAME=${2}

    while [ "$($OC get ${RESOURCE_TYPE} ${RESOURCE_NAME} -n $NAMESPACE -o go-template={{.status.ready}})" != "true" ] ; do
      echo "${RESOURCE_TYPE} ${RESOURCE_NAME} is not ready. Waiting 3s..."
      sleep 5
    done

    echo "${RESOURCE_TYPE} ${RESOURCE_NAME} is ready."
}

NAMESPACE=mas-sso

$OC create ns ${NAMESPACE}
$OC project ${NAMESPACE}

$OC create secret docker-registry rhoas-pull-docker  \
    --docker-server=quay.io \
    --docker-username=${DOCKER_USER_NAME} \
    --docker-password=${DOCKER_PASSWORD} \
    --docker-email=example@example.com

# link the pull secret to default service account

$OC secrets link default rhoas-pull-docker --for=pull

#create the operator
> mas-sso/sso-template-params.env

if [ -n "${MAS_SSO_OPERATOR_SUBSCRIPTION_CONFIG:-}" ] ; then
    echo "OPERATOR_SUBSCRIPTION_CONFIG=${MAS_SSO_OPERATOR_SUBSCRIPTION_CONFIG}" >> mas-sso/sso-template-params.env
fi

$OC process -f mas-sso/sso-template.yaml --param-file=mas-sso/sso-template-params.env \
 -p NAMESPACE=${NAMESPACE} \
 -p IMAGE=${MAS_SSO_OLM_INDEX_IMAGE} \
 -p IMAGE_TAG=${MAS_SSO_OLM_INDEX_IMAGE_TAG} \
 | $OC create -f -

wait_condition 'deployment' 'rhsso-operator' ${NAMESPACE} 'available' '90s'

#wait for the CRD
while [ $($OC get crd | grep keycloaks.keycloak.org | wc -l) != 1 ]
do
  sleep 1
  echo "waiting for keycloak CRD to be present"
done

#apply admin role to service account temp work around for a route host perm missing
#   - routes/custom-host

$OC adm policy add-role-to-user admin -z mas-sso-operator

> mas-sso/sso-keycloak-params.env

if [ -n "${MAS_SSO_KEYCLOAK_RESOURCES:-}" ] ; then
    echo "RESOURCES='${MAS_SSO_KEYCLOAK_RESOURCES}'" >> mas-sso/sso-keycloak-params.env
fi

${OC} process -f mas-sso/keycloak.yaml --param-file=mas-sso/sso-keycloak-params.env | ${OC} create -f - -n ${NAMESPACE}

wait_condition 'deployment' 'keycloak-postgresql' ${NAMESPACE} 'available' '90s'
echo "Waiting for statefulset/keycloak to be ready"
${OC} rollout status --watch --timeout=600s statefulset/keycloak -n ${NAMESPACE}
wait_status 'keycloak' 'mas-sso'

echo "MAS SSO is ready: $($OC get route keycloak -n $NAMESPACE -o go-template={{.spec.host}})"

$OC create -f mas-sso/realms/realm-rhoas.yaml
$OC create -f mas-sso/realms/realm-rhoas-kafka-sre.yaml

$OC create -f mas-sso/clients/strimzi-ui.yaml
$OC create -f mas-sso/clients/rhoas-cli.yaml
$OC create -f mas-sso/clients/kas-installer.yaml

if [ -n "${RH_USERNAME}" ] && [ -n "${RH_USER_ID}" ] && [ -n "${RH_ORG_ID}" ] ; then
    echo "Creating KAS cluster owner account"
    ${OC} process -f mas-sso/clients/owner-template.yaml -pRH_USERNAME=${RH_USERNAME} -pRH_USER_ID=${RH_USER_ID} -pRH_ORG_ID=${RH_ORG_ID} | oc create -f - -n ${NAMESPACE}
fi

wait_status 'keycloakrealm' 'rhoas'
wait_status 'keycloakrealm' 'rhoas-kafka-sre'

wait_status 'keycloakclient' 'strimzi-ui'
wait_status 'keycloakclient' 'rhoas-cli'
wait_status 'keycloakclient' 'kas-installer-client'

sh ./mas-sso/kas.sh
sh ./mas-sso/kas-sre.sh
sh ./mas-sso/role-admin.sh
sh ./mas-sso/role-agent.sh
