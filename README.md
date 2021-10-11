# kas-installer

KAS Installer allows the deployment and configuration of Managed Kafka Service
in a single K8s cluster.

## Prerequisites
* [jq][jq]
* [curl][curl]
* [OpenShift][openshift]. In the future there are plans to make it compatible
  with native K8s. Currently an OpenShift dedicated based environment is needed
  (Currently needs to be a multi-zone cluster if you want to create a Kafka
  instance through the fleet manager by using `managed_kafka.sh`).
* [git][git_tool]
* oc
* kubectl
* openssl CLI tool
* A user with administrative privileges in the OpenShift cluster
* brew coreutils (Mac only)
* OSD Cluster with the following specs:
   * 3 compute nodes
   * Size: m5.4xlarge
   * MultiAz: True


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

### Deploy Managed Kafka Service
1. Create and fill the KAS installer configuration file `kas-installer.env`. An
   example of the needed values can be found in the `kas-installer.env.example`
   file
1. Run the KAS installer `kas-installer.sh` to deploy and configure Managed
   Kafka Service
1. Run `uninstall.sh` to remove KAS from the cluster.  You should remove any deployed Kafkas before runnig this script.
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
   curl -vs   -H"Authorization: Bearer $(./get_access_token.sh --owner)"   http://admin-server-$(./managed_kafka.sh --list | jq -r .items[0].bootstrap_server_host | awk -F: '{print $1}')/rest/acls   -XPOST   -H'Content-type: application/json'   --data '{"resourceType":"GROUP", "resourceName":"*", "patternType":"LITERAL", "principal":"User:<service-acct>", "operation":"ALL", "permission":"ALLOW"}'
   ```
   then for Topic
   ```
   curl -vs   -H"Authorization: Bearer $(./get_access_token.sh --owner)"   http://admin-server-$(./managed_kafka.sh --list | jq -r .items[0].bootstrap_server_host | awk -F: '{print $1}')/rest/acls   -XPOST   -H'Content-type: application/json'   --data '{"resourceType":"TOPIC", "resourceName":"*", "patternType":"LITERAL", "principal":"User:<service-acct>", "operation":"ALL", "permission":"ALLOW"}'
   ```

1. Then execute the your tool like `kafka-topics.sh --bootstrap-server <bootstrap-host>:443 --command-config app-services.properties --topic foo --create --partitions 9`
1. if you created separate service account using above instructions, edit the `app-services.properties` file and update the username and password with `clientID` and `clientSecret`


[git_tool]:https://git-scm.com/downloads
[jq]:https://stedolan.github.io/jq/
[openshift]:https://www.openshift.com/
[curl]:https://curl.se/
