# kas-installer

KAS Installer allows the deployment and configuration of Managed Kafka Service
in a single K8s cluster.

## Prerequisites
* [jq][jq]
* [curl][curl]
* [OpenShift][openshift]. In the future there are plans to make it compatible
  with native K8s. Currently an OpenShift dedicated based environment is needed
* [git][git_tool]
* oc
* kubectl
* openssl CLI tool
* A user with administrative privileges in the OpenShift cluster

## Description

KAS Installer deploys and configures the following components that are part of
Managed Kafka Service:
* MAS SSO
* Observability Operator
* sharded-nlb IngressController
* KAS Fleet Manager
* KAS Fleet Shard and Strimzi Operators

It deploys and configures the components to the cluster set in
the user's kubeconfig file.

Additionally, a single Data Plane cluster is configured ready to be used, in the
same cluster set in the user's kubeconfig file.

## Usage

To deploy Managed Kafka Service:
1. Create and fill the KAS installer configuration file `kas-installer.env`. An
   example of the needed values can be found in the `kas-installer.env.example`
   file
1. Run the KAS installer `kas-installer.sh` to deploy and configure Managed
   Kafka Service

[git_tool]:https://git-scm.com/downloads
[jq]:https://stedolan.github.io/jq/
[openshift]:https://www.openshift.com/
[curl]:https://curl.se/
