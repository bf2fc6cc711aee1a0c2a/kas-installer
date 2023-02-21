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
BUILD_ENGINE='docker'

function usage() {
    echo "
    Usage: generate-kas-fleetshard-olm-bundle.sh [<options>]

    Options:
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
    --bundle-version    OLM bundle version
                        Default: kas-fleetshard POM version
    --update-config     When set, the kas-installer.env file will be updated to use the generated OLM bundle index image
                        Default: unset
    --build-engine      Tool for build container images. Examples: buildah, docker, podman.
                        Default: ${BUILD_ENGINE}
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
    "--build-engine" )
        BUILD_ENGINE="${2}"
        shift
        shift
        ;;
    "--help" )
        usage
        exit 0
        ;;
    *)
        echo "Unknown argument '${1}'";
        usage
        exit 1
        ;;
    esac
done

GIT="$(which git)"
YQ=$(which yq)

main() {
    initialize_inputs
    generate_olm_bundle
}

initialize_inputs() {
    if [ -d "${KAS_FLEETSHARD_GIT_URL}" ] ; then
        KAS_FLEETSHARD_CODE_DIR=${KAS_FLEETSHARD_GIT_URL}
    else
        mkdir -p "${DIR_NAME}/tmp"
        # Temporary directory for the tool binaries
        TMPDIR=$(mktemp --directory --tmpdir=${DIR_NAME}/tmp fsobundle.XXX 2>/dev/null || mktemp -d -t 'fsobundle.XXX')
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
}

generate_olm_bundle() {
    BUILDDT="$(date -u +%Y.%-m%d.%-H%M)"
    PROJECT_VERSION="$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout -f ${KAS_FLEETSHARD_CODE_DIR}/pom.xml | tr '[:upper:]' '[:lower:]')"
    KAS_FLEETSHARD_OLM_BUNDLE_VERSION=${KAS_FLEETSHARD_OLM_BUNDLE_VERSION:-"${BUILDDT}-${PROJECT_VERSION}"}

    (cd ${KAS_FLEETSHARD_CODE_DIR} && \
        mvn clean package -Pquickly && \
        mvn package \
            -pl operator,sync,bundle \
            -am \
            -Pquickly,generate-bundle \
            --no-transfer-progress \
            -Dquarkus.container-image.build='true' \
            -Dquarkus.container-image.push='true' \
            -Dquarkus.container-image.registry=${KAS_FLEETSHARD_IMAGE_REGISTRY} \
            -Dquarkus.container-image.group=${KAS_FLEETSHARD_IMAGE_ORG} \
            -Dquarkus.container-image.tag="${PROJECT_VERSION}" \
            -Dquarkus.container-image.insecure='true' \
            -Dquarkus.container-image.username="${IMAGE_REPOSITORY_USERNAME}" \
            -Dquarkus.container-image.password="${IMAGE_REPOSITORY_PASSWORD}" \
            -Dquarkus.kubernetes.image-pull-policy='Always' \
            -Dquarkus.profile='prod' \
            -Dkas.bundle.version="${KAS_FLEETSHARD_OLM_BUNDLE_VERSION}" \
            -Dkas.bundle.patch='[{
                "op": "add",
                "path": "/spec/install/spec/deployments/0/spec/template/spec/imagePullSecrets",
                "value": [{ "name": "rhoas-image-pull-secret" }]
              }, {
                "op": "add",
                "path": "/spec/install/spec/deployments/1/spec/template/spec/imagePullSecrets",
                "value": [{ "name": "rhoas-image-pull-secret" }]
              }]' \
            -Dkas.bundle.image="${KAS_FLEETSHARD_IMAGE_REGISTRY}/${KAS_FLEETSHARD_IMAGE_ORG}/kas-fleetshard-operator-bundle:${KAS_FLEETSHARD_OLM_BUNDLE_VERSION}" \
            -Dkas.index.image-registry="${KAS_FLEETSHARD_IMAGE_REGISTRY}" \
            -Dkas.index.image-group="${KAS_FLEETSHARD_IMAGE_ORG}" \
            -Dkas.index.image="${KAS_FLEETSHARD_OLM_BUNDLE_REPO}" \
            -Dkas.index.build-engine="${BUILD_ENGINE}")

    validate_olm_bundle ${KAS_FLEETSHARD_CODE_DIR}/bundle/target/bundle
    INDEX_IMAGE="${KAS_FLEETSHARD_IMAGE_REGISTRY}/${KAS_FLEETSHARD_IMAGE_ORG}/${KAS_FLEETSHARD_OLM_BUNDLE_REPO}:${KAS_FLEETSHARD_OLM_BUNDLE_VERSION}"

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

validate_olm_bundle() {
    local BUNDLE=${1}
    OPERATOR_SDK=$(which operator-sdk || true)

    if [ -n "${OPERATOR_SDK}" ] ; then
        ${OPERATOR_SDK} bundle validate "${BUNDLE}" --select-optional name=operatorhub
    else
        echo "operator-sdk not found, skipping bundle validation"
    fi
}

main
