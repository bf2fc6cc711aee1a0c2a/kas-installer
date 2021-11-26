# Tips

## Testing strimzi upgrade end to end

When wanting to test the upgrade of strimzi, end to end, the rhosak bundle needs to provide at least two versions of strimzi.

By default, fleetmanager will always chose the latest strimzi when a new kafka instance is created.  The easiest way to trick the system into creating
a kafka instance with a previous version is to edit the strimzi deployment and change the `app.kubernetes.io/part-of` label on the strimzi deployment of
the newer strimzi to a value other than `managed-kafka` (e.g. `managed-kafkaX`).  Fleetshard will ignore the deployment and not advertise the the version
to Fleet Mangaer.  Check this by inspecting the `managedkafkaagent` resource.

You can then create an instance:

```
rhoas  kafka create --bypass-terms-check --provider aws --region us-east-1 --name foobar
```

Check the component versions are as you expect:

```
./managed_kafka.sh --admin --get c6ggs2ap1fc4s45jpa70  | jq
```

Now backout the label change made above and check the `managedkafkaagent` resource to ensure all versions are reported.

To cause the fleetmanager to upgrade directly, use a patch command like:

```
./managed_kafka.sh --admin --patch c6ggs2ap1fc4s45jpa70 '{ "strimzi_version": "strimzi-cluster-operator.v0.23.0-5", "kafka_version" : "2.8.1", "kafka_ibp_version" : "2.8" }'
```

You can also run the upgrader tool with a command line this:

```
 ./kas-upgrade-cli -v=9 exec --mas-sso-host $(oc get route -n mas-sso keycloak -o json | jq -r '"https://"+.spec.host')  --mas-sso-realm rhoas-kafka-sre --api-host $(oc get route -n kas-fleet-manager-${USER} kas-fleet-manager -o json | jq -r '"https://"+.spec.host') --client-id kafka-admin --client-secret kafka-admin --config configurations/staging/strimzi.yaml --dry-run=false  --alsologtostderr
```

You can watch the upgrade with a command like:

```
watch './managed_kafka.sh --admin --get c6ggs2ap1fc4s45jpa70  | jq'
```


