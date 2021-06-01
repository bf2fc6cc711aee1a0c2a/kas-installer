# install pull secret

NAMESPACE=mas-sso

oc create ns ${NAMESPACE}

oc project ${NAMESPACE}

oc create secret docker-registry rhoas-pull-docker  \
    --docker-server=quay.io \
    --docker-username=${DOCKER_USER_NAME} \
    --docker-password=${DOCKER_PASSWORD} \
    --docker-email=example@example.com

# link the pull secret to default service account

oc secrets link default rhoas-pull-docker --for=pull


#create the operator

oc process -f sso-template.yaml -p NAMESPACE=${NAMESPACE} | oc create -f -


#wait for the CRD
while [ $(oc get crd | grep keycloaks.keycloak.org | wc -l) != 1 ]
do
  sleep 1
  echo "waiting for keycloak CRD to be present"
done

#apply admin role to service account temp work around for a route host perm missing
#   - routes/custom-host

oc adm policy add-role-to-user admin -z mas-sso-operator

oc create -f keycloak.yaml 

while [ "$(oc get keycloak mas-sso -o go-template={{.status.ready}})" != "true" ]
do
  sleep 3
  echo "MAS SSO is not ready. Current mas sso status nessage:"
  oc get keycloak mas-sso -o go-template={{.status.message}}
done

echo "MAS SSO is ready $(oc get route keycloak -o go-template={{.spec.host}})"

export KEYCLOAK_ROUTE=https://$(oc get route keycloak --template='{{ .spec.host }}')

oc create -f realms/realm-rhoas.yaml
oc create -f realms/realm-rhoas-kafka-sre.yaml

oc create -f clients/kas-fleet-manager.yaml
oc create -f clients/kas-fleet-manager-kafka-sre.yaml
oc create -f clients/kas-fleetshard-agent.yaml
oc create -f clients/strimzi-ui.yaml
oc create -f clients/rhoas-cli.yaml

sh ./kas.sh
sh ./kas-sre.sh
