#!/usr/bin/env bash

# Inspired from: https://gist.github.com/b1zzu/ccd9ef553d546a2009eca21ab45db97a

set -eEu -o pipefail
# shellcheck disable=SC2154
trap 's=$?; echo "$0: error on $0:$LINENO"; exit $s' ERR

SCRIPT=$0
ROOT="$(dirname "${SCRIPT}")"

# Defaults
# ---

NAMESPACE='mas-sso'

# Help
# ---

function usage() {
  echo
  echo "Usage: ${SCRIPT} COMMAND"
  echo
  echo "Commands:"
  echo "  create        create a MAS SSO user"
}

function create_usage() {
  echo
  echo "Usage: ${SCRIPT} create [OPTIONS]"
  echo
  echo "Options:"
  echo "  --red-hat-user string       the Red Hat user name to add to MAS SSO (by default ocm will be used to try to find it)"
  echo "  --red-hat-user-id string    the Red Hat user id of the red-hat-user"
  echo "  --red-hat-org-id string     the Red Hat organization id to which the red-hat-user belongs"
}

# Utils
# ---

function fatal() {
  echo "$SCRIPT: error: $1" >&2
  return 1
}

function info() {
  echo "$SCRIPT: info: $1" >&2
}

# Commands
# ---

function create_command() {

  # Optional Arguments
  RED_HAT_USERNAME=
  RED_HAT_USER_ID=
  RED_HAT_ORG_ID=

  # Parse Command Arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
      demo_usage
      return 0
      ;;
    --red-hat-user)
      RED_HAT_USERNAME="$2"
      shift
      shift
      ;;
    --red-hat-user-id)
      RED_HAT_USER_ID="$2"
      shift
      shift
      ;;
    --red-hat-org-id)
      RED_HAT_ORG_ID="$2"
      shift
      shift
      ;;
    --* | -* | *)
      demo_usage
      echo
      fatal "unknown option '$1'"
      ;;
    esac
  done

  # Command

  if [[ -n "${RED_HAT_USERNAME}" ]]; then

    if [[ -z "${RED_HAT_USER_ID}" ]]; then
      fatal "--red-hat-user-id is required"
    fi
    if [[ -z "${RED_HAT_ORG_ID}" ]]; then
      fatal "--red-hat-org-id is required"
    fi
  else
    info "try to discover the Red Hat user using OCM"
    if [[ -n "${RED_HAT_USER_ID}" ]]; then
      info "ignore --red-hat-user-id"
    fi
    if [[ -n "${RED_HAT_ORG_ID}" ]]; then
      info "ignore --red-hat-org-id"
    fi

    RED_HAT_USERNAME="$(ocm whoami | jq -r ".username")"
    info "using --red-hat-user=${RED_HAT_USERNAME}"

    RED_HAT_USER_ID="$(ocm whoami | jq -r ".username")"
    info "using --red-hat-user-id=${RED_HAT_USER_ID}"

    RED_HAT_ORG_ID="$(ocm whoami | jq -r ".organization.external_id")"
    info "using --red-hat-org-id=${RED_HAT_ORG_ID}"
  fi

  info "create user: ${RED_HAT_USERNAME}"
  oc process -f "${ROOT}/user.yml" --local -p \
    RED_HAT_USERNAME="${RED_HAT_USERNAME}" \
    RED_HAT_USER_ID="${RED_HAT_USER_ID}" \
    RED_HAT_ORG_ID="${RED_HAT_ORG_ID}" |
    oc apply -f - -n "${NAMESPACE}"

  return 0
}

# Parse arguments
# ---
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  create)
    shift
    create_command "$@"
    exit 0
    ;;
  --* | -*)
    usage
    echo
    fatal "unknown option '$1'"
    ;;
  *)
    usage
    echo
    fatal "unknown command '$1'"
    ;;
  esac
done

usage
echo
fatal "command not specified"
