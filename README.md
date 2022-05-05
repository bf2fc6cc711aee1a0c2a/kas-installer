# kas-installer

KAS Installer allows the deployment and configuration of Managed Kafka Service
in a single K8s cluster.

## Contents
- [Prerequisites](#prerequisites)
- [Description](#description)
- [Usage](#usage)
- [Installation Modes](#installation-modes)
  - [Standalone Mode](#standalone)
  - [OCM Mode](#ocm)
- [Fleet Manager Parameter Customization](#fleet-manager-parameter-customization)
  - [Instance Types](#instance-types)
- [Using rhoas CLI](#using-rhoas-cli)
- [Legacy Scripts](#legacy-scripts)
- [Running E2E Test Suite (experimental)](#running-e2e-test-suite-experimental)

## Prerequisites
* [jq][jq]
* [curl][curl]
* gsed for macOS e.g. via `brew install gsed`
* [OpenShift][openshift]. In the future there are plans to make it compatible
  with native K8s. Currently an OpenShift dedicated based environment is needed
  (Currently needs to be a multi-zone cluster if you want to create a Kafka
  instance through the fleet manager by using `managed_kafka.sh`).
* [git][git_tool]
* oc
* kubectl
* openssl CLI tool
* rhoas CLI (https://github.com/redhat-developer/app-services-cli)
* A user with administrative privileges in the OpenShift cluster and is logged in using `oc` or `kubectl`
* brew coreutils (Mac only)
* OSD Cluster with the following specs:
   * 3 compute nodes
   * Size: m5.4xlarge
   * MultiAz: True


## Description

KAS Installer deploys and configures the following components that are part of
Managed Kafka Service:
* MAS SSO
* KAS Fleet Manager
* Observability Operator (via KAS Fleet Manager)
* sharded-nlb IngressController
* KAS Fleet Shard and Strimzi Operators (via KAS Fleet Manager)

It deploys and configures the components to the cluster set in
the user's kubeconfig file.

Additionally, a single Data Plane cluster is configured ready to be used, in the
same cluster set in the user's kubeconfig file.

## Usage

### Deploy Managed Kafka Service
1. Create and fill the KAS installer configuration file `kas-installer.env`. An
   example of the needed values can be found in the `kas-installer.env.example`
   file
1. make sure you have run `oc login --server=<api cluster url|https://api.xxx.openshiftapps.com:6443>` to your target OSD cluster. You will be asked a password or a token
1. Run the KAS installer `kas-installer.sh` to deploy and configure Managed
   Kafka Service
1. Run `uninstall.sh` to remove KAS from the cluster.  You should remove any deployed Kafkas before runnig this script.

**Troubleshooting:** If the installer crashed due to configuration error in `kas-installer.env`, you often can rerun the installer after fixing the config issue.
It is not necessary to run uninstall before retrying.

## Installation Modes

### Standalone

Deploying a cluster with kas-fleet-manager in `standalone` is the default for kas-installer (when `OCM_SERVICE_TOKEN` is not defined).
In this mode, the fleet manager deploys the data plane components from OLM bundles.

**NOTE:**
In standalone mode, predefined bundles are used for Strimzi and KAS Fleetshard operators. To use a different bundle
you'll need to build a dev bundle and set either `STRIMZI_OLM_INDEX_IMAGE` or `KAS_FLEETSHARD_OLM_INDEX_IMAGE` environment variables.

### OCM

Installation with OCM mode allows kas-fleet-manager to deploy the data plane components as OCM addons. This mode can be
used by setting `OCM_SERVICE_TOKEN` to your [OCM offline token](https://console.redhat.com/openshift/token) and also setting
`OCM_CLUSTER_ID` to the idenfier for the OSD cluster used in deployment.

**NOTE:**
In OCM mode, it may take up to 10 minutes after the `kas-installer.sh` completes before the addon installations are ready. Until ready,
the fleet-manager API will reject new Kafka requests.

## Fleet Manager Parameter Customization

The `kas-installer.sh` process will check for the presence of an executable named `kas-fleet-manager-service-template-params` in
the project root. When available, it will be executed with the expection that key/value pairs will be output to stdout. The output
will used when processing the kas-fleet-manager's [service-template.yml](https://github.com/bf2fc6cc711aee1a0c2a/kas-fleet-manager/blob/main/templates/service-template.yml).
The name of the executable is intentially missing an extension to indicate that any language may be used that is known to the user
to be supported in their own environment.

Note that `oc process` requires that individual parameters are specified on a single line.

For example, to provide a custom `KAS_FLEETSHARD_OPERATOR_SUBSCRIPTION_CONFIG` parameter value to the fleet manager template,
something like the following may be used for a `kas-fleet-manager-service-template-params` executable:
```shell
#!/bin/bash

# Declare the subscription config using multi-line YAML
MY_CUSTOM_SUBSCRIPTION_CONFIG='---
resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "1Gi"
    cpu: "500m"
env:
- name: SSO_ENABLED
  value: "true"
- name: MANAGEDKAFKA_ADMINSERVER_EDGE_TLS_ENABLED
  value: "true"
- name: STANDARD_KAFKA_CONTAINER_CPU
  value: 500m
- name: STANDARD_KAFKA_CONTAINER_MEMORY
  value: 4Gi
- name: STANDARD_KAFKA_JVM_XMS
  value: 1G
- name: STANDARD_ZOOKEEPER_CONTAINER_CPU
  value: 500m
'

# Quota override for my organization
MY_CUSTOM_ORG_QUOTA='
- id: <YOUR ORG HERE>
  max_allowed_instances: 10
  any_user: true
  registered_users: []
'

# Serialize to a single line as JSON (subset of YAML) to standard output
echo "KAS_FLEETSHARD_OPERATOR_SUBSCRIPTION_CONFIG='$(echo "${MY_CUSTOM_SUBSCRIPTION_CONFIG}" | yq -o=json -I=0)'"

# Disable organization quotas (allows deployment of developer instances)
echo "REGISTERED_USERS_PER_ORGANISATION='[]'"
# Custom organization quota (allows deployment of standard instances), disabled/commented here
#echo "REGISTERED_USERS_PER_ORGANISATION='$(echo "${MY_CUSTOM_ORG_QUOTA}" | yq -o=json -I=0)'"

```
### Instance Types
The default kas-fleet-manager configuration enables the deployment of two instance types, `standard` and `developer`. Permission
to create an instance of a particular type depends on the organization's quota for the user creating the instance.

1. Creating a `developer` instance type requires that the user creating the instance does not have an instance quota. Use [parameter customization](#fleet-manager-parameter-customization) to set the `REGISTERED_USERS_PER_ORGANISATION` property to an empty array `[]`.
1. Creating a `standard` instance type requires that the user creating the instance _does_ have an instance quota. Use [parameter customization](#fleet-manager-parameter-customization) to set the `REGISTERED_USERS_PER_ORGANISATION` property to an array containing the user's org. See the `MY_CUSTOM_ORG_QUOTA` variable in the sample script for an example.

To create a `standard.x2` (or other non-default types) instance type, the `plan` must be provided to the Kafka create request. If using the `managed_kafka.sh` script, the `--plan` argument may be used:
```shell
managed_kafka.sh --create mykafka --plan standard.x2
```

## Using rhoas CLI

Use `./rhoas_login.sh` as a short cut to login to the CLI.  Login using the username you specified as RH_USERNAME in the env file.  The password is the same as the RH_USERNAME value.

There are a couple of things that are expected not to work when using the RHOAS CLI with a kas-installer installed instance.  These are noted below.

### Service Account Maintenace

1. To create an account, run `rhoas service-account create --short-description foo --file-format properties`.
1. To list existing service accounts, run `rhoas service-account list`.
1. To remove an existing service account, run `rhoas service-account delete --id=<ID of service account>`.

### Kafka Instance Maintenance

1. To create a cluster, run `rhoas kafka create --bypass-terms-check --provider aws --region us-east-1 --name <clustername>`.  Note that `--bypass-terms-check` is required as the T&Cs endpoint will not
   exist in your environment. The provider and region must be passed on the command line.
1. To list existing clusters, run `rhoas kafka list`
1. To remove an existing cluster, run `rhoas kafka delete --name <clustername>`.

#### Kafka topics / consumergroups / ACL

To use these cli featurs, you must set `MANAGEDKAFKA_ADMINSERVER_EDGE_TLS_ENABLED=true` in your `kas-installer.env` so that the admin-server will run over TLS (edge terminated).

1. To create a topic `rhoas kafka topic create --name=foo`
1. To grant access `rhoas kafka acl grant-access  --topic=foo --all-accounts --producer`
etc.

## Legacy scripts

Please favour using the rhoas command line.  These scripts will be remove at some point soon.

### Service Account Maintenance

The `service_account.sh` script supports creating, listing, and deleting service accounts.

1. To create an account, run `service_account.sh --create`. The new service account information will be printed to the console. Be sure to retain the `clientID` and `clientSecret` values to use when generating an access token or for connecting to Kafka directly.
1. To list existing service accounts, run `service_account.sh --list`.
1. To remove an existing service account, run `service_account.sh --delete <ID of service account>`.

### Generate an Access Token
1. Run `get_access_token.sh` using the `clientID` and `clientSecret` as the first and second arguments. The generated access token and its expiration date and time will be printed to the console.

### Kafka Instance Maintenance

The `managed_kafka.sh` script supports creating, listing, and deleting Kafka clusters.

1. To create a cluster, run `managed_kafka.sh --create <cluster name>`. Progress will be printed as the cluster is prepared and provisioned.
1. To list existing clusters, run `managed_kafka.sh --list`.
1. To remove an existing cluster, run `managed_kafka.sh --delete <cluster ID>`.
1. To patch an existing cluster (for instance changing a strimzi version), run ` managed_kafka.sh --admin --patch  <cluster ID> '{ "strimzi_version": "strimzi-cluster-operator.v0.23.0-3" }'`
1. To use kafka bin scripts against pre existing kafka cluster, run `managed_kafka.sh --certgen <kafka id> <Service_Account_ID> <Service_Account_Secret>`. If you do not pass the <Service_Account_ID> <Service_Account_Secret> arguments, the script will attempt to create a Service_Account for you. The cert generation is already performed at the end of `--create`. Point the `--command-config flag` to the generated app-services.properties in the working directory.
* If there is already 2 service accounts pre-existing you must delete 1 of them for this script to work

### Access the Kafka Cluster using command line tools

To use the Kafka Cluster that is created with the `managed_kafka.sh` script with command line tools like `kafka-topics.sh` or `kafka-console-consumer.sh` do the following.

1. Generate the certificate and `app-services.properties` file, run `managed_kafka.sh --certgen <instance-id>` where `instance-id` can found by running `managed_kafka.sh --list` and also bootstrap host to the cluster in same response.
1. Run the following to give the current user the permissions to create a topic and group. For the `<service-acct>` for below script take the service account from generated `app-services.properties` file

   ```
   curl -vs   -H"Authorization: Bearer $(./get_access_token.sh --owner)"   http://admin-server-$(./managed_kafka.sh --list | jq -r .items[0].bootstrap_server_host | awk -F: '{print $1}')/api/v1/acls   -XPOST   -H'Content-type: application/json'   --data '{"resourceType":"GROUP", "resourceName":"*", "patternType":"LITERAL", "principal":"User:<service-acct>", "operation":"ALL", "permission":"ALLOW"}'
   ```
   then for Topic
   ```
   curl -vs   -H"Authorization: Bearer $(./get_access_token.sh --owner)"   http://admin-server-$(./managed_kafka.sh --list | jq -r .items[0].bootstrap_server_host | awk -F: '{print $1}')/api/v1/acls   -XPOST   -H'Content-type: application/json'   --data '{"resourceType":"TOPIC", "resourceName":"*", "patternType":"LITERAL", "principal":"User:<service-acct>", "operation":"ALL", "permission":"ALLOW"}'
   ```

1. Then execute the your tool like `kafka-topics.sh --bootstrap-server <bootstrap-host>:443 --command-config app-services.properties --topic foo --create --partitions 9`
1. if you created separate service account using above instructions, edit the `app-services.properties` file and update the username and password with `clientID` and `clientSecret`

### Running E2E Test Suite (experimental)

1. Install all cluster components using `kas-installer.sh`
1. Clone the [e2e-test-suite][e2e_test_suite] repository locally and change directory to the test suite project root
1. Generate the test suite configuration with `${KAS_INSTALLER_DIR}/e2e-test-config.sh > config.json`
1. Execute individual test classes:
   - `./hack/testrunner.sh test KafkaAdminPermissionTest`
   - `./hack/testrunner.sh test KafkaInstanceAPITest`
   - `./hack/testrunner.sh test KafkaCLITest`

[git_tool]:https://git-scm.com/downloads
[jq]:https://stedolan.github.io/jq/
[openshift]:https://www.openshift.com/
[curl]:https://curl.se/
[e2e_test_suite]:https://github.com/bf2fc6cc711aee1a0c2a/e2e-test-suite
