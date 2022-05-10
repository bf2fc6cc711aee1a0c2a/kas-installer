#!/bin/sh
# make sure your OpenShift token has not expired
# open URL to login to OpenShift via oc as needed
# logs to rhoas

DIR_NAME="$(dirname $0)"
. ${DIR_NAME}/kas-installer.env
oc get route -n mas-sso keycloak > /dev/null 2>&1
status=$?
if [ $status -eq 1 ]; then
    oc login --server=https://api.${K8S_CLUSTER_DOMAIN}:6443
    open https://oauth-openshift.apps.${K8S_CLUSTER_DOMAIN}/oauth/token/request
    exit 1;
else
    ${DIR_NAME}/rhoas_login.sh
fi
