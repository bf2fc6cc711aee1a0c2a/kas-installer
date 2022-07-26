#!/usr/bin/env bash
#
# Generates OLM bundle using existing CRDs
#
set -euo pipefail

DIR_NAME="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
KI_CONFIG="${DIR_NAME}/../kas-installer.env"

source ${KI_CONFIG}

KAS_FLEETSHARD_GIT_URL=
KAS_FLEETSHARD_GIT_REF='main'
KAS_FLEETSHARD_IMAGE_REGISTRY="quay.io"
KAS_FLEETSHARD_IMAGE_ORG="${USER}"
KAS_FLEETSHARD_OLM_BUNDLE_REPO="kas-fleetshard-operator-index"
KAS_FLEETSHARD_OLM_BUNDLE_VERSION=
UPDATE_KAS_INSTALLER_ENV='false'

function usage() {
    echo "
    Usage: generate-kas-fleetshard-olm-bundle.sh [<options>]

    Options:
    --bundle-version    Required: OLM bundle version
    --git-url           Required: URL or directory path to a kas-fleetshard source code repository. When not a directory
                        the repository will be cloned locally.
    --git-ref           git branch, tag, or commit. Used when '--git-url' is not a directory path.
                        Default: ${KAS_FLEETSHARD_GIT_REF}
    --image-registry    Image registry to push the generated kas-fleetshard images.
                        Default: ${KAS_FLEETSHARD_IMAGE_REGISTRY}
    --image-group       Image group/organization to push the generated kas-fleetshard images.
                        Default: ${KAS_FLEETSHARD_IMAGE_ORG}
    --bundle-repo       Image repository name for the for the generated OLM bundle index image
                        Default: ${KAS_FLEETSHARD_OLM_BUNDLE_REPO}
    --update-config     When set, the kas-installer.env file will be updated to use the generated OLM bundle index image
    --help              Display this help text
    "
}

while [[ ${#} -gt 0 ]]; do
    key="$1"
    case $key in
    "--git-url" )
        KAS_FLEETSHARD_GIT_URL="${2}"
        shift
        shift
        ;;
    "--git-ref" )
        KAS_FLEETSHARD_GIT_REF="${2}"
        shift
        shift
        ;;
    "--image-registry" )
        KAS_FLEETSHARD_IMAGE_REGISTRY="${2}"
        shift
        shift
        ;;
    "--image-group" )
        KAS_FLEETSHARD_IMAGE_ORG="${2}"
        shift
        shift
        ;;
    "--bundle-repo" )
        KAS_FLEETSHARD_OLM_BUNDLE_REPO="${2}"
        shift
        shift
        ;;
    "--bundle-version" )
        KAS_FLEETSHARD_OLM_BUNDLE_VERSION="${2}"
        shift
        shift
        ;;
    "--update-config" )
        UPDATE_KAS_INSTALLER_ENV="true"
        shift
        ;;
    "--help" )
        usage
        exit 0
        ;;
    *)
        echo "Unknown argument '${1}'";
        exit 1
        ;;
    esac
done

if [ $(uname -s) = "Darwin" ] ; then
    # MacOS GNU versions which can be installed through Homebrew
    CP=gcp
    SED=gsed
    GREP=ggrep
    WC=gwc
    UNIQ=guniq
    SORT=gsort
    HEAD=ghead
    TEE=gtee
else
    #Linux versions
    CP=cp
    SED=sed
    GREP=grep
    WC=wc
    UNIQ=uniq
    SORT=sort
    HEAD=head
    TEE=tee
fi

GIT="$(which git)"

main() {
    setup_environment
    initialize_inputs
    generate_olm_bundle 'kas-fleetshard-operator'
}

setup_environment() {
    YQ=$(which yq)
    mkdir -p "${DIR_NAME}/tmp"
    # Temporary directory for the tool binaries
    TMPDIR=$(mktemp --directory --tmpdir=${DIR_NAME}/tmp fsobundle.XXX)
}

initialize_inputs() {
    if [ -d "${KAS_FLEETSHARD_GIT_URL}" ] ; then
        KAS_FLEETSHARD_CODE_DIR=${KAS_FLEETSHARD_GIT_URL}
    else
        KAS_FLEETSHARD_CODE_DIR="${TMPDIR}/kas-fleetshard-source"

        if [ -d "${KAS_FLEETSHARD_CODE_DIR}" ]; then
          CONFIGURED_GIT="${KAS_FLEETSHARD_GIT_URL}:${KAS_FLEETSHARD_GIT_REF}"
          CURRENT_GIT=$(cd "${KAS_FLEETSHARD_CODE_DIR}" && echo "$(${GIT} remote get-url origin):$(${GIT} rev-parse HEAD)")

          if [ "${CURRENT_GIT}" != "${CONFIGURED_GIT}" ] ; then
            echo "Refreshing KAS Fleetshard code directory (current ${CURRENT_GIT} != configured ${CONFIGURED_GIT})"
            # Checkout the configured git ref and pull only if not in detached HEAD state (rc of symbolic-ref == 0)
            (cd ${KAS_FLEETSHARD_CODE_DIR} && \
              ${GIT} remote set-url origin ${KAS_FLEETSHARD_GIT_URL}
              ${GIT} fetch origin && \
              ${GIT} checkout ${KAS_FLEETSHARD_GIT_REF} && \
              ${GIT} symbolic-ref -q HEAD && \
              ${GIT} pull --ff-only || echo "Skipping 'pull' for detached HEAD")
          else
            echo "KAS Fleetshard code directory is current, not refreshing"
          fi
        else
          echo "KAS Fleetshard code directory does not exist. Cloning it..."
          ${GIT} clone "${KAS_FLEETSHARD_GIT_URL}" ${KAS_FLEETSHARD_CODE_DIR}
          (cd ${KAS_FLEETSHARD_CODE_DIR} && ${GIT} checkout ${KAS_FLEETSHARD_GIT_REF})
        fi
    fi

    (cd ${KAS_FLEETSHARD_CODE_DIR} && \
        mvn clean package -Pquickly && \
        mvn package \
            -pl operator,sync \
            -am \
            -Prelease-perform \
            --no-transfer-progress \
            -DskipTests='true' \
            -Dquarkus.jib.base-jvm-image='registry.access.redhat.com/ubi8/openjdk-11-runtime' \
            -Dquarkus.container-image.registry=${KAS_FLEETSHARD_IMAGE_REGISTRY} \
            -Dquarkus.container-image.group=${KAS_FLEETSHARD_IMAGE_ORG} \
            -Dquarkus.container-image.tag='latest' \
            -Dquarkus.container-image.insecure='true' \
            -Dquarkus.container-image.username="${IMAGE_REPOSITORY_USERNAME}" \
            -Dquarkus.container-image.password="${IMAGE_REPOSITORY_PASSWORD}" \
            -Dquarkus.kubernetes.image-pull-policy='Always' \
            -Dquarkus.profile='prod')

    OPERATOR_YAML=${KAS_FLEETSHARD_CODE_DIR}/operator/target/kubernetes/kubernetes.yml
    SYNC_YAML=${KAS_FLEETSHARD_CODE_DIR}/sync/target/kubernetes/kubernetes.yml

    PACKAGE_NAME=kas-fleetshard-operator
    CHANNELS=latest

    CRD_DIR="${TMPDIR}/crds"
    rm -rf ${CRD_DIR} && mkdir ${CRD_DIR}

    # Extract Operator cluster role (from source) and deployment (from generated output) to input directory
    ${YQ} e '. | select(.kind == "ClusterRole")'   ${OPERATOR_YAML} > ${CRD_DIR}/operator-clusterrole.yml
    ${YQ} e '. | select(.kind == "Deployment")'    ${OPERATOR_YAML} > ${CRD_DIR}/operator-deployment.yml
    ${YQ} e '. | select(.kind == "PriorityClass")' ${OPERATOR_YAML} > ${CRD_DIR}/operator-reservation-priorityclass.yml

    # Extract Sync cluster role (from source), role (from generat (from generated output) to input directory
    ${YQ} e '. | select(.kind == "ClusterRole")'   ${SYNC_YAML} > ${CRD_DIR}/sync-clusterrole.yml
    ${YQ} e '. | select(.kind == "Role")'          ${SYNC_YAML} > ${CRD_DIR}/sync-role.yml
    ${YQ} e '. | select(.kind == "Deployment")'    ${SYNC_YAML} > ${CRD_DIR}/sync-deployment.yml
}

generate_olm_bundle() {
    ADDON_NAME=$1
    BUNDLE="${TMPDIR}/addons/${ADDON_NAME}/main/${KAS_FLEETSHARD_OLM_BUNDLE_VERSION}"
    rm -rvf ${BUNDLE}
    MANIFESTS=${BUNDLE}/manifests
    mkdir -vp ${MANIFESTS}
    mkdir -vp ${BUNDLE}/metadata

    # Copy CRD files to manifests directory
    ${CP} -v ${KAS_FLEETSHARD_CODE_DIR}/operator/target/kubernetes/*-v1.yml ${MANIFESTS}
    # Copy the priority class for reserved deployments if the file is not empty
    [ -s "${CRD_DIR}/operator-reservation-priorityclass.yml" ] && \
      ${CP} -v ${CRD_DIR}/operator-reservation-priorityclass.yml ${MANIFESTS}

    CSV_FILE="${MANIFESTS}/${PACKAGE_NAME}.clusterserviceversion.yaml"
    echo "${CSV_BASE}" > ${CSV_FILE}

    cat <<-EOF > ${BUNDLE}/Dockerfile
	FROM scratch

	# We are pushing an operator-registry bundle
	# that has both metadata and manifests.
	LABEL operators.operatorframework.io.bundle.mediatype.v1=registry+v1
	LABEL operators.operatorframework.io.bundle.manifests.v1=manifests/
	LABEL operators.operatorframework.io.bundle.metadata.v1=metadata/
	LABEL operators.operatorframework.io.bundle.package.v1=kas-fleetshard-operator
	LABEL operators.operatorframework.io.bundle.channels.v1=stable
	LABEL operators.operatorframework.io.bundle.channel.default.v1=stable

	ADD /manifests /manifests
	ADD /metadata /metadata
	EOF

    cat <<-EOF > ${MANIFESTS}/${PACKAGE_NAME}.priorityclass.yaml
	apiVersion: scheduling.k8s.io/v1
	kind: PriorityClass
	metadata:
	  name: kas-fleetshard-high
	value: 1000000
	globalDefault: false
	description: "Priority Class for kas-fleetshard operator/sync"
	EOF

    cat <<-EOF > ${BUNDLE}/metadata/annotations.yaml
	annotations:
	  # Core bundle annotations.
	  operators.operatorframework.io.bundle.mediatype.v1: registry+v1
	  operators.operatorframework.io.bundle.manifests.v1: manifests/
	  operators.operatorframework.io.bundle.metadata.v1: metadata/
	  operators.operatorframework.io.bundle.package.v1: ${ADDON_NAME}
	  operators.operatorframework.io.bundle.channels.v1: alpha
	  operators.operatorframework.io.bundle.channel.default.v1: alpha
	EOF

    # Change the copied CRD names to the names traditionally used for OperatorHub
    for file in "${MANIFESTS}"/*; do
        name=$(${YQ} ea '.metadata.name' "${file}")
        kind=$(${YQ} ea '.kind' "${file}")

        if [ "$kind" = "CustomResourceDefinition" ] \
        || [ "$kind" = "ConfigMap" ] \
        || [ "$kind" = "ClusterRole" ] \
        || [ "$kind" = "PriorityClass" ] \
        || [ "$kind" = "Role" ]
        then
            if [ "$kind" = "CustomResourceDefinition" ]; then
                kind="crd"
            else
                name=$(echo "$name" | $SED 's/-//g')
                kind=$(echo "$kind" | tr '[:upper:]' '[:lower:]')
            fi

            dest="${MANIFESTS}/${name}.${kind}.yaml"

            if [ "$file" != "$dest" ]; then
                echo "Update CRD filename $(basename "$file") -> $(basename "$dest")"
                mv "$file" "$dest"
            fi
        fi
    done

    # Update name and version being replaced
    ${YQ} ea -i ".metadata.name = \"${ADDON_NAME}.v${KAS_FLEETSHARD_OLM_BUNDLE_VERSION}\" | .metadata.name style=\"\"" "${CSV_FILE}"
    ${YQ} ea -i ".metadata.annotations.\"olm.skipRange\" = \">=0.0.1 <${KAS_FLEETSHARD_OLM_BUNDLE_VERSION}\"" "${CSV_FILE}"
    ${YQ} ea -i ".spec.version = \"${KAS_FLEETSHARD_OLM_BUNDLE_VERSION}\" | .spec.version style=\"\"" "${CSV_FILE}"

    ${YQ} ea -i 'select(fi==0).spec.install.spec.clusterPermissions[0].rules = select(fi==1).rules | select(fi==0)' \
      "${CSV_FILE}" "${CRD_DIR}/operator-clusterrole.yml"

    ${YQ} ea -i 'select(fi==0).spec.install.spec.clusterPermissions[1].rules = select(fi==1).rules | select(fi==0)' \
      "${CSV_FILE}" "${CRD_DIR}/sync-clusterrole.yml"

    ${YQ} ea -i 'select(fi==0).spec.install.spec.permissions[0].rules = select(fi==1).rules | select(fi==0)' \
     "${CSV_FILE}" "${CRD_DIR}/sync-role.yml"

    # Set deployment specs
    ${YQ} ea -i "select(fi==0).spec.install.spec.deployments[0].spec = select(fi==1).spec | select(fi==0)" \
      "${CSV_FILE}" \
      "${CRD_DIR}/operator-deployment.yml"
    ${YQ} ea -i "select(fi==0).spec.install.spec.deployments[1].spec = select(fi==1).spec | select(fi==0)" \
      "${CSV_FILE}" \
      "${CRD_DIR}/sync-deployment.yml"

    # Add imagePullSecrets
    ${YQ} ea -i '.spec.install.spec.deployments[].spec.template.spec.imagePullSecrets = [
      {
        "name": "rhoas-image-pull-secret"
      }
    ]' "${CSV_FILE}"

    ${YQ} ea -i '.spec.install.spec.deployments[0].spec.selector.matchLabels = { "name": "kas-fleetshard-operator" }' "${CSV_FILE}"
    ${YQ} ea -i '.spec.install.spec.deployments[0].spec.template.metadata.labels = { "name": "kas-fleetshard-operator" }' "${CSV_FILE}"

    ${YQ} ea -i '.spec.install.spec.deployments[1].spec.selector.matchLabels = { "name": "kas-fleetshard-sync" }' "${CSV_FILE}"
    ${YQ} ea -i '.spec.install.spec.deployments[1].spec.template.metadata.labels = { "name": "kas-fleetshard-sync" }' "${CSV_FILE}"

    # Update image references
    OPERATOR_IMAGE_PULL_URL="${KAS_FLEETSHARD_IMAGE_REGISTRY}/${KAS_FLEETSHARD_IMAGE_ORG}/kas-fleetshard-operator:latest"
    SYNC_IMAGE_PULL_URL="${KAS_FLEETSHARD_IMAGE_REGISTRY}/${KAS_FLEETSHARD_IMAGE_ORG}/kas-fleetshard-sync:latest"

    ${YQ} ea -i '.spec.install.spec.deployments[0].spec.template.spec.containers[0].image = "'${OPERATOR_IMAGE_PULL_URL}'"' "${CSV_FILE}"
    ${YQ} ea -i '.spec.install.spec.deployments[1].spec.template.spec.containers[0].image = "'${SYNC_IMAGE_PULL_URL}'"' "${CSV_FILE}"

    ${YQ} ea -i '.spec.install.spec.deployments[].spec.template.spec.priorityClassName = "kas-fleetshard-high"' "${CSV_FILE}"

    # Remove unnecessary annotations
    ${YQ} ea -i "del(.spec.install.spec.deployments[].spec.template.metadata.annotations)" "${CSV_FILE}"
    ${YQ} ea -i 'del(.. | select(has("app.kubernetes.io/name"))."app.kubernetes.io/name")' "${CSV_FILE}"
    ${YQ} ea -i 'del(.. | select(has("app.kubernetes.io/version"))."app.kubernetes.io/version")' "${CSV_FILE}"
    # Remove KUBERNETES_NAMESPACE env from all deployments
    ${YQ} ea -i 'del(.spec.install.spec.deployments[].spec.template.spec.containers[].env[] | select(.name == "KUBERNETES_NAMESPACE"))' "${CSV_FILE}"

    validate_olm_bundle ${BUNDLE}

    (cd ${BUNDLE} && build_bundle_images)
}

validate_olm_bundle() {
    local BUNDLE=${1}
    OPERATOR_SDK=$(which operator-sdk)
    if [ -n "${OPERATOR_SDK}" ] ; then
        ${OPERATOR_SDK} bundle validate "${BUNDLE}" --select-optional name=operatorhub
    else
        echo "operator-sdk not found, skipping bundle validation"
    fi
}

build_bundle_images() {
    # Function assumes working directory of the bundle root
    BUNDLE_IMAGE="${KAS_FLEETSHARD_IMAGE_REGISTRY}/${KAS_FLEETSHARD_IMAGE_ORG}/kas-fleetshard-operator-bundle:${KAS_FLEETSHARD_OLM_BUNDLE_VERSION}"
    INDEX_IMAGE="${KAS_FLEETSHARD_IMAGE_REGISTRY}/${KAS_FLEETSHARD_IMAGE_ORG}/${KAS_FLEETSHARD_OLM_BUNDLE_REPO}:${KAS_FLEETSHARD_OLM_BUNDLE_VERSION}"

    docker login -u ${IMAGE_REPOSITORY_USERNAME} -p ${IMAGE_REPOSITORY_PASSWORD} ${KAS_FLEETSHARD_IMAGE_REGISTRY}
    docker build -t "${BUNDLE_IMAGE}" .
    docker push "${BUNDLE_IMAGE}"
    opm index add --bundles "${BUNDLE_IMAGE}" --tag "${INDEX_IMAGE}" -u docker
    docker push "${INDEX_IMAGE}"

    if [ "${UPDATE_KAS_INSTALLER_ENV}" = "true" ]; then
        if grep '^KAS_FLEETSHARD_OLM_INDEX_IMAGE=' ${KI_CONFIG} > /dev/null ; then
            echo "Updating kas-installer.env variable KAS_FLEETSHARD_OLM_INDEX_IMAGE to '${INDEX_IMAGE}'"
            sed -i "s,^KAS_FLEETSHARD_OLM_INDEX_IMAGE=.*,KAS_FLEETSHARD_OLM_INDEX_IMAGE='${INDEX_IMAGE}',g" ${KI_CONFIG}
        else
            echo "Adding kas-installer.env variable KAS_FLEETSHARD_OLM_INDEX_IMAGE='${INDEX_IMAGE}'"
            echo "KAS_FLEETSHARD_OLM_INDEX_IMAGE='${INDEX_IMAGE}'" >> ${KI_CONFIG}
        fi
    else
        echo '*****'
        echo
        echo "Pushed kas-fleetshard-operator OLM bundle index image to ${INDEX_IMAGE}"
        echo "Configuration value KAS_FLEETSHARD_OLM_INDEX_IMAGE not modified."
        echo
        echo '*****'
    fi
}

CSV_BASE=$(cat <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: ClusterServiceVersion
metadata:
  annotations:
    alm-examples: '[]'
    capabilities: Basic Install
  name: PLACEHOLDER
spec:
  apiservicedefinitions: {}
  customresourcedefinitions:
    owned:
    - name: managedkafkas.managedkafka.bf2.org
      kind: ManagedKafka
      version: v1alpha1
    - name: managedkafkaagents.managedkafka.bf2.org
      kind: ManagedKafkaAgent
      version: v1alpha1
  installModes:
  - supported: false
    type: OwnNamespace
  - supported: false
    type: SingleNamespace
  - supported: false
    type: MultiNamespace
  - supported: true
    type: AllNamespaces
  install:
    strategy: deployment
    spec:
      clusterPermissions:
      - serviceAccountName: "kas-fleetshard-operator"
        rules: null
      - serviceAccountName: "kas-fleetshard-sync"
        rules: null
      permissions:
      - serviceAccountName: "kas-fleetshard-sync"
        rules: null
      deployments:
      - name: kas-fleetshard-operator
      - name: kas-fleetshard-sync
  displayName: KaaS Fleetshard Operator
  description: Operator That Manages Kafka Instances
  MinKubeVersion: 1.21.0
  keywords:
  - managed
  - kafka
  maintainers:
  - email: help@redhat.com
    name: RedHat
  maturity: alpha
  provider:
    name: Red Hat
    url: https://github.com/bf2fc6cc711aee1a0c2a/kas-fleetshard
  version: 0.0.0
EOF
)

main
