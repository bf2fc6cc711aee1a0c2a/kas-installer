# utils/common.sh

OS=$(uname)

GIT=$(which git)
OC=$(which oc)
OCM=$(which ocm)
KUBECTL=$(which kubectl)
MAKE=$(which make)

if [ "$OS" = 'Darwin' ]; then
  # for MacOS
  SED=$(which gsed)
  AWK=$(which gawk)
  BASE64=$(which gbase64)
  OPENSSL=$(brew --prefix openssl)/bin/openssl
  DATE=$(which gdate)
else
  # for Linux and Windows
  SED=$(which sed)
  AWK=$(which awk)
  BASE64=$(which base64)
  OPENSSL=$(which openssl)
  DATE=$(which date)
fi

function cluster_domain_check() {
  K8S_CLUSTER_DOMAIN="${1}"
  OP="${2:-install}"

  # Parse the domain reported by cluster-info to ensure a match with the user-configured k8s domain
  K8S_CLUSTER_REPORTED_DOMAIN=$(${OC} cluster-info | grep -o 'is running at .*https.*$' | cut -d '/' -f3 | cut -d ':' -f1 | cut -c5-)

  if [ "${K8S_CLUSTER_REPORTED_DOMAIN}" != "${K8S_CLUSTER_DOMAIN}" ] ; then
      echo "Configured k8s domain '${K8S_CLUSTER_DOMAIN}' is different from domain reported by 'oc cluster-info': '${K8S_CLUSTER_REPORTED_DOMAIN}'"
      echo -n "Proceed with ${OP} process? [yN]: "
      read -r proceed

      if [ "$(echo ${proceed} | tr [a-z] [A-Z])" != "Y" ] ; then
          return 1
      else
          echo "Ignoring k8s cluster domain difference..."
      fi
  fi
  return 0

}

function delete_dataplane_resources() {
    OCM_MODE=${1}
    DELETE_MACHINEPOOL=${2}
    CLUSTER_ID=${3}

    OCM_CLUSTER=$(${OCM} get /api/clusters_mgmt/v1/clusters/${CLUSTER_ID})
    VALID_OCM_CLUSTER='false'

    if [ "$(echo ${OCM_CLUSTER} | jq -r '.kind')" == 'Cluster' ] ; then
        VALID_OCM_CLUSTER='true'
        OCM_CLUSTER_CREDENTIALS=$(${OCM} get /api/clusters_mgmt/v1/clusters/${CLUSTER_ID}/credentials)
        OC_ORIGINAL_CONTEXT=$(${OC} config current-context)
        ${OC} login -u $(echo ${OCM_CLUSTER_CREDENTIALS} | jq -r .admin.user) -p $(echo ${OCM_CLUSTER_CREDENTIALS} | jq -r .admin.password) $(echo ${OCM_CLUSTER} | jq -r .api.url)
    else
        echo "CLUSTER_ID ${CLUSTER_ID} not found in OCM, assuming valid 'oc' session and skipping OCM interaction"
    fi

    if [ "${OCM_MODE}" == "true" ] ; then
        if [ "${VALID_OCM_CLUSTER}" == "true" ] ; then
            ${OCM} delete "/api/clusters_mgmt/v1/clusters/${CLUSTER_ID}/addons/kas-fleetshard-operator-qe" || true
            ${OCM} delete "/api/clusters_mgmt/v1/clusters/${CLUSTER_ID}/addons/managed-kafka-qe" || true
        fi
    else
        ${OC} delete namespace ${KAS_FLEETSHARD_OPERATOR_NAMESPACE} || true
        ${OC} delete namespace ${STRIMZI_OPERATOR_NAMESPACE} || true
    fi

    if [ "${VALID_OCM_CLUSTER}" == "true" ] && [ "${DELETE_MACHINEPOOL}" == "true" ] ; then
        MK_MACHINE_POOL=$(${OCM} get "/api/clusters_mgmt/v1/clusters/${CLUSTER_ID}/machine_pools" | jq -r '.items[] | select(.labels."bf2.org/kafkaInstanceProfileType" == "standard") | .id' || true)

        if [ -n "${MK_MACHINE_POOL}" ] && [ "${MK_MACHINE_POOL}" != "null" ] ; then
            ${OCM} delete "/api/clusters_mgmt/v1/clusters/${CLUSTER_ID}/machine_pools/${MK_MACHINE_POOL}"
        fi
    fi

    # remove all CRDs and custom ingress controllers
    ${OC} delete crd -l operators.coreos.com/kas-fleetshard-operator.${KAS_FLEETSHARD_OPERATOR_NAMESPACE}=''
    ${OC} delete crd -l app=strimzi
    ${OC} delete ingresscontroller -l app.kubernetes.io/managed-by='kas-fleetshard-operator' -n openshift-ingress-operator

    ${OC} delete priorityclass -l olm.owner.namespace=${KAS_FLEETSHARD_OPERATOR_NAMESPACE}
    ${OC} delete priorityclass -l olm.owner.namespace=${STRIMZI_OPERATOR_NAMESPACE}

    OBSERVABILITY_NS='managed-application-services-observability'

    ( ${OC} delete observability observability-stack -n ${OBSERVABILITY_NS} || true ) &

    while \
        [ -n "$(${KUBECTL} get Observability observability-stack --ignore-not-found -o jsonpath=\"{.metadata.name}\" -n ${OBSERVABILITY_NS})" ] && \
        [ "$(${OC} patch Observability observability-stack --type=merge --patch '{"metadata":{"finalizers":null}}' -n ${OBSERVABILITY_NS} || echo 'false')" = 'false' ] ; do
        echo "Failed to remove Observability CR finalizers, retrying"
        sleep 2
    done
    ${OC} delete namespace ${OBSERVABILITY_NS} || true
    ${OC} delete crd -l operators.coreos.com/observability-operator.managed-application-services-observabili=''
    ${OC} delete priorityclass -l olm.owner.namespace=${OBSERVABILITY_NS}

    # Final
    if [ "${VALID_OCM_CLUSTER}" == "true" ] ; then
        ${OC} config use-context "${OC_ORIGINAL_CONTEXT}"
    fi
}
