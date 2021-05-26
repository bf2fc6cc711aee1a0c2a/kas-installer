#!/bin/bash


for ns in mas-sso; 
do oc process -f foundation/resources/pull_secret.yaml NAMESPACE=${ns} DOCKER_CONFIG=${DOCKER_CONFIG} | oc apply -f -
done
