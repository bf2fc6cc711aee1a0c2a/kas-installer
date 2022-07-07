
if ! cluster_domain_check "${K8S_CLUSTER_DOMAIN}" "install"; then
    echo "Exiting ${0}"
    exit 1
fi

CONTAINER_CLI=${CONTAINER_CLI:-"$(which podman || which docker)"}
