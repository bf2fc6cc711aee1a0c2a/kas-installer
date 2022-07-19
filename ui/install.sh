#!/bin/bash

set -euo pipefail

DIR_NAME="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
KI_CONFIG="${DIR_NAME}/../kas-installer.env"
source ${KI_CONFIG}
source "${DIR_NAME}/../utils/common.sh"
source "${DIR_NAME}/ui-common.sh"

if [ "${SSO_PROVIDER_TYPE}" != "redhat_sso" ] || [ "${REDHAT_SSO_HOSTNAME:-}" != "sso.redhat.com" ] ; then
    echo "UI installation only supported for SSO_PROVIDER_TYPE = 'redhat_sso' and REDHAT_SSO_HOSTNAME = 'sso.redhat.com'"
    echo "Current settings:"
    echo "- SSO_PROVIDER_TYPE:   '${SSO_PROVIDER_TYPE}'"
    echo "- REDHAT_SSO_HOSTNAME: '${REDHAT_SSO_HOSTNAME}'"
    exit 1
fi

REPO=kas-installer
MAS_SSO_SERVER_URL="https://$(${OC} get route keycloak -n mas-sso --template='{{ .spec.host }}')/auth"
KAS_API_BASE_PATH="https://kas-fleet-manager-kas-fleet-manager-${USER}.apps.${K8S_CLUSTER_DOMAIN}"
GIT=$(which git)

mkdir -p ${DIR_NAME}/workspace

####################

clone() {
    URL=${1}
    REF=${2}
    DIR=${3}

    if [ -d "${DIR}" ]; then
        CONFIGURED_GIT="${URL}:${REF}"
        CURRENT_GIT=$(cd "${DIR}" && echo "$(${GIT} remote get-url origin):$(${GIT} rev-parse HEAD)")

        if [ "${CURRENT_GIT}" != "${CONFIGURED_GIT}" ] ; then
            echo "Refreshing code directory ${DIR} (current ${CURRENT_GIT} != configured ${CONFIGURED_GIT})"
            # Checkout the configured git ref and pull only if not in detached HEAD state (rc of symbolic-ref == 0)
            (cd ${DIR} && \
                ${GIT} remote set-url origin ${URL}
                ${GIT} fetch origin && \
                ${GIT} checkout ${REF} && \
                ${GIT} symbolic-ref -q HEAD && \
                ${GIT} pull --ff-only || echo "Skipping 'pull' for detached HEAD")
        else
            echo "Code directory ${DIR} is current, not refreshing"
        fi
    else
        echo "Code directory ${DIR} does not exist. Cloning it..."
        ${GIT} clone "${URL}" ${DIR}
        (cd ${DIR} && ${GIT} checkout ${REF})
  fi
}

####################

APP_SERVICES_UI_GIT_URL=${APP_SERVICES_UI_GIT_URL:-"https://github.com/redhat-developer/app-services-ui.git"}
APP_SERVICES_UI_GIT_REF=${APP_SERVICES_UI_GIT_REF:-"e9a44bbbeff347814d8338cac3b1a36b8151aafa"}

APP_SERVICES_UI_GIT_DIR="${DIR_NAME}/workspace/app-services-ui"
clone "${APP_SERVICES_UI_GIT_URL}" "${APP_SERVICES_UI_GIT_REF}" "${APP_SERVICES_UI_GIT_DIR}"

(cd ${APP_SERVICES_UI_GIT_DIR} && \
    cat ./config/config.json | \
      jq --arg kasApiBasePath "${KAS_API_BASE_PATH}" --arg masSsoAuthServerUrl "${MAS_SSO_SERVER_URL}" '
        (.config[] | select (.hostnames[] == "prod.foo.redhat.com")).config.kas.apiBasePath |= $kasApiBasePath |
        (.config[] | select (.hostnames[] == "prod.foo.redhat.com")).config.masSso.authServerUrl |= $masSsoAuthServerUrl' \
      > ./config/config-new.json && \
    mv ./config/config-new.json ./config/config.json)

${CONTAINER_CLI} build \
  -t ${REPO}/app-services-ui:latest \
  -f ${DIR_NAME}/app-services-ui.Dockerfile

####################

KAS_UI_GIT_URL=${KAS_UI_GIT_URL:-"https://github.com/bf2fc6cc711aee1a0c2a/kas-ui.git"}
KAS_UI_GIT_REF=${KAS_UI_GIT_REF:-"83496eb73f67b7c1e093cf3c33bca8507c6c977e"}
KAS_UI_GIT_DIR="${DIR_NAME}/workspace/kas-ui"
clone "${KAS_UI_GIT_URL}" "${KAS_UI_GIT_REF}" "${KAS_UI_GIT_DIR}"

${CONTAINER_CLI} build \
  -t ${REPO}/kas-ui:latest \
  -f ${DIR_NAME}/kas-ui.Dockerfile

####################

KAFKA_UI_GIT_URL=${KAFKA_UI_GIT_URL:-"https://github.com/bf2fc6cc711aee1a0c2a/kafka-ui.git"}
KAFKA_UI_GIT_REF=${KAFKA_UI_GIT_REF:-"6aa583ec9bfc26ddf30757a982302d1c2b2f12a6"}
KAFKA_UI_GIT_DIR="${DIR_NAME}/workspace/kafka-ui"
clone "${KAFKA_UI_GIT_URL}" "${KAFKA_UI_GIT_REF}" "${KAFKA_UI_GIT_DIR}"

${CONTAINER_CLI} build \
  -t ${REPO}/kafka-ui:latest \
  -f ${DIR_NAME}/kafka-ui.Dockerfile

####################

${DIR_NAME}/uninstall.sh

####################

if [[ ${CONTAINER_CLI} == *docker ]] ; then
    EXTRA_APP_SERVICES_UI="--network host"
    EXTRA_KAS_UI="--network host"
    EXTRA_KAFKA_UI="--network host"
else
    ${CONTAINER_CLI} pod create -p1337:1337 --name kas-installer-ui
    EXTRA_APP_SERVICES_UI="--pod kas-installer-ui"
    EXTRA_KAS_UI="--pod kas-installer-ui"
    EXTRA_KAFKA_UI="--pod kas-installer-ui"
fi

WEBPACK_EXTRA=''
CERTS="${DIR_NAME}/../certs"

if [ -f ${CERTS}/server-cert.pem ] ; then
    EXTRA_APP_SERVICES_UI="${EXTRA_APP_SERVICES_UI} -v "$(realpath ${DIR_NAME}/../certs)":/certs -eTLS_CA=/certs/ca-cert.pem -eTLS_KEY=/certs/server-key.pem -eTLS_CERT=/certs/server-cert.pem"
fi

${CONTAINER_CLI} run -d -eHOST=0.0.0.0 -ePORT=1337 -ePROTOCOL=https ${EXTRA_APP_SERVICES_UI} --name kas-installer-app-services-ui ${REPO}/app-services-ui:latest
${CONTAINER_CLI} run -d -eHOST=0.0.0.0 -ePORT=9000 -ePROTOCOL=http  ${EXTRA_KAS_UI} --name kas-installer-kas-ui ${REPO}/kas-ui:latest
${CONTAINER_CLI} run -d -eHOST=0.0.0.0 -ePORT=8080 -ePROTOCOL=http  ${EXTRA_KAFKA_UI} --name kas-installer-kafka-ui ${REPO}/kafka-ui:latest

echo "UI now started at: https://prod.foo.redhat.com:1337/beta/application-services/"
