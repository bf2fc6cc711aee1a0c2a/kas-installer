#!/usr/bin/env bash

# Inspired from: https://gist.github.com/b1zzu/ccd9ef553d546a2009eca21ab45db97a

set -eEu -o pipefail
# shellcheck disable=SC2154
trap 's=$?; echo "$0: error on $0:$LINENO"; exit $s' ERR

SCRIPT=$0
ROOT="$(dirname "${SCRIPT}")"

OC=$(which oc)

ENV_FILE="${ROOT}/mas-ui.env"
if [[ -f ${ENV_FILE} ]]; then
  # shellcheck source=mas-ui.env
  . "${ENV_FILE}"
fi

NAMESPACE=${NAMESPACE:-'mas-ui'}
PULL_SECRET_NAME=${PULL_SECRET_NAME:-'mas-ui-pull-secret'}
IMAGE_REGISTRY=${IMAGE_REGISTRY:-'quay.io'}
IMAGE_REPOSITORY=${IMAGE_REPOSITORY:-'rhoas'}
IMAGE_REPOSITORY_USERNAME=${IMAGE_REPOSITORY_USERNAME:-}
IMAGE_REPOSITORY_PASSWORD=${IMAGE_REPOSITORY_PASSWORD:-}
MAS_SSO_URL=${MAS_SSO_URL:-}
KAS_API_URL=${KAS_API_URL:-}

PROXY_NGINX_IMAGE=${PROXY_NGINX_IMAGE:-"quay.io/app-sre/ubi8-nginx-118"}
PROXY_OPENSHIFT_API_URL=${PROXY_OPENSHIFT_API_URL:-"https://api.openshift.com/"}

PROXY_VARNISH_IMAGE=${PROXY_VARNISH_IMAGE:-"varnish"}
PROXY_CONSOLE_UI_URL=${PROXY_CONSOLE_UI_URL:-"https://console.redhat.com/"}

APPLICATION_SERVICES_UI_IMAGE=${APPLICATION_SERVICES_UI_IMAGE:-'application-services-ui'}
APPLICATION_SERVICES_UI_TAG=${APPLICATION_SERVICES_TAG:-'latest'}
APPLICATION_SERVICES_UI_FULL_IMAGE=${APPLICATION_SERVICES_UI_FULL_IMAGE:-"${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/${APPLICATION_SERVICES_UI_IMAGE}:${APPLICATION_SERVICES_UI_TAG}"}

function info() {
  echo "${SCRIPT}: info: ${1}"
}

function error() {
  echo "${SCRIPT}: info: ${1}"
}

## Namespace
info "apply ${NAMESPACE} namespace"
if [[ -z "$(${OC} get "project/${NAMESPACE}" -o jsonpath="{.metadata.name}" --ignore-not-found)" ]]; then
  info "create ${NAMESPACE} namespace"
  ${OC} new-project "${NAMESPACE}"
  info "${NAMESPACE} namespace created"
else
  info "${NAMESPACE} namespace already exists"
fi

## Auto-discover
## Discover some of the config if not passed form the current log-in cluster

if [[ -z "${IMAGE_REPOSITORY_USERNAME}" ]]; then

  secret="$(${OC} get secret "${PULL_SECRET_NAME}" -o jsonpath="{.data.\.dockerconfigjson}" -n "${NAMESPACE}" | base64 -d || true)"
  if [[ -z "${secret}" ]]; then
    error "IMAGE_REPOSITORY_USERNAME and IMAGE_REPOSITORY_PASSWORD can't be discovered and hasn't been set"
    exit 1
  fi

  info "auto-discover IMAGE_REPOSITORY_USERNAME & IMAGE_REPOSITORY_PASSWORD"
  IMAGE_REPOSITORY_USERNAME="$(jq -r '.auths["quay.io/rhoas"].username' <<<"${secret}")"
  IMAGE_REPOSITORY_PASSWORD="$(jq -r '.auths["quay.io/rhoas"].password' <<<"${secret}")"
fi

if [[ -z "${MAS_SSO_URL}" ]]; then
  route="$(${OC} get route keycloak -n mas-sso --template='{{ .spec.host }}' || true)"
  if [[ -z "${route}" ]]; then
    error "MAS_SSO_URL can't be discovered and hasn't been set"
    exit 1
  fi
  MAS_SSO_URL="https://${route}"
fi

if [[ -z "${KAS_API_URL}" ]]; then
  route="$(${OC} get route kas-fleet-manager -n "kas-fleet-manager-${USER}" --template='{{ .spec.host }}' || true)"
  if [[ -z "${route}" ]]; then
    error "KAS_API_URL can't be discovered and hasn't been set"
    exit 1
  fi
  KAS_API_URL="https://${route}"
fi

## Pull Secret
info "apply ${PULL_SECRET_NAME} pull secret"
if [ -z "$(kubectl get secret "${PULL_SECRET_NAME}" --ignore-not-found -o jsonpath="{.metadata.name}" -n "${NAMESPACE}")" ]; then
  info "create ${PULL_SECRET_NAME} pull secret"
  ${OC} create secret docker-registry "${PULL_SECRET_NAME}" \
    --docker-server="${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}" \
    --docker-username="${IMAGE_REPOSITORY_USERNAME}" \
    --docker-password="${IMAGE_REPOSITORY_PASSWORD}"

  info "link ${PULL_SECRET_NAME} pull secret to default service account"
  ${OC} secrets link default "${PULL_SECRET_NAME}" --for=pull

  info "${PULL_SECRET_NAME} pull secret created"
else
  info "${PULL_SECRET_NAME} pull secret already exists"
fi

## Proxy API
info "deploy api proxy"
${OC} process -f "${ROOT}/proxy-openshift-api.yml" --local -p \
  NGINX_IMAGE="${PROXY_NGINX_IMAGE}" \
  OPENSHIFT_API_URL="${PROXY_OPENSHIFT_API_URL}" |
  ${OC} apply -f - -n "${NAMESPACE}"

PROXY_API_URL="https://$(${OC} get route api -n "${NAMESPACE}" --template='{{ .spec.host }}')"

## Varnish UI
info "deploy varnish cache proxy"
${OC} process -f "${ROOT}/varnish-ui.yml" --local -p \
  VARNISH_IMAGE="${PROXY_VARNISH_IMAGE}" |
  ${OC} apply -f - -n "${NAMESPACE}"

VARNISH_UI_HOST="$(${OC} get route ui -n "${NAMESPACE}" --template='{{ .spec.host }}')"
VARNISH_UI_URL="https://${VARNISH_UI_HOST}"

## Proxy SSO
#info "deploy sso proxy"
#${OC} process -f "${ROOT}/proxy-redhat-sso.yml" --local -p \
#  NGINX_IMAGE="${PROXY_NGINX_IMAGE}" \
#  REDIRECT_URL="${VARNISH_UI_URL}" |
#  ${OC} apply -f - -n "${NAMESPACE}"
#
#PROXY_SSO_URL="https://$(${OC} get route sso -n "${NAMESPACE}" --template='{{ .spec.host }}')"

## Application Services UI
info "deploy application-services-ui"
${OC} process -f "${ROOT}/application-services-ui.yml" --local -p \
  IMAGE="${APPLICATION_SERVICES_UI_FULL_IMAGE}" \
  MAS_SSO_URL="${MAS_SSO_URL}" \
  KAS_API_URL="${KAS_API_URL}" \
  AMS_API_URL="${PROXY_API_URL}" \
  SRS_API_URL="${PROXY_API_URL}" \
  UI_HOST="${VARNISH_UI_HOST}" |
  ${OC} apply -f - -n "${NAMESPACE}"

# Proxy UI
info "deploy ui proxy"
${OC} process -f "${ROOT}/proxy-console-ui.yml" --local -p \
  NGINX_IMAGE="${PROXY_NGINX_IMAGE}" \
  CONSOLE_UI_URL="${PROXY_CONSOLE_UI_URL}" \
  PROXY_SSO_URL="${MAS_SSO_URL}" |
  ${OC} apply -f - -n "${NAMESPACE}"

info "MAS UI ready at: ${VARNISH_UI_URL}"
