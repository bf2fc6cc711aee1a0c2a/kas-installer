# utils/common.sh

OS=$(uname)

GIT=$(which git)
OC=$(which oc)
OCM=$(which ocm)
KUBECTL=$(which kubectl)
MAKE=$(which make)
OPENSSL=$(which openssl)

if [ "$OS" = 'Darwin' ]; then
  # for MacOS
  SED=$(which gsed)
  AWK=$(which gawk)
  BASE64=$(which gbase64)
else
  # for Linux and Windows
  SED=$(which sed)
  AWK=$(which awk)
  BASE64=$(which base64)
fi

function cluster_domain_check() {
  K8S_CLUSTER_DOMAIN="${1}"
  OP="${2:-install}"

  # Parse the domain reported by cluster-info to ensure a match with the user-configured k8s domain
  K8S_CLUSTER_REPORTED_DOMAIN=$(${OC} cluster-info | grep -o 'is running at .*https.*$' | cut -d '/' -f3 | cut -d ':' -f1 | cut -c5-)

  if [ "${K8S_CLUSTER_REPORTED_DOMAIN}" != "${K8S_CLUSTER_DOMAIN}" ] ; then
      echo "Configured k8s domain '${K8S_CLUSTER_DOMAIN}' is different from domain reported by 'oc cluster-info': '${K8S_CLUSTER_REPORTED_DOMAIN}'"
      echo -n "Proceed with ${OP} process? [yN]: "
      read -r proceed

      if [ "$(echo ${proceed} | tr [a-z] [A-Z])" != "Y" ] ; then
          return 1
      else
          echo "Ignoring k8s cluster domain difference..."
      fi
  fi
  return 0

}
