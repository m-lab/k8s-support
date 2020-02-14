#!/bin/bash

set -euxo pipefail

USAGE="USAGE: $0 <google-cloud-project>"
PROJECT=${1:?Please specify the google cloud project: $USAGE}

# Source the main configuration file.
source ./k8s_deploy.conf

# Create a string representing region and zone variable names for this project.
GCE_REGION_VAR="GCE_REGION_${PROJECT//-/_}"
GCE_ZONES_VAR="GCE_ZONES_${PROJECT//-/_}"

# Dereference the region and zones variables.
GCE_REGION="${!GCE_REGION_VAR}"
GCE_ZONES="${!GCE_ZONES_VAR}"

GCE_ZONE="${GCE_REGION}-$(echo ${GCE_ZONES} | awk '{print $1}')"
GCE_ARGS=("--zone=${GCE_ZONE}" "--project=${PROJECT}" "--quiet")
GCE_NAME="master-${GCE_BASE_NAME}-${GCE_ZONE}"

GCS_BUCKET_K8S="GCS_BUCKET_K8S_${PROJECT//-/_}"
GCS_BUCKET_SITEINFO="GCS_BUCKET_SITEINFO_${PROJECT//-/_}"

# Fetch switches.json from siteinfo and create a directory with site-speed
# mappings. This directory will created into a ConfigMap later. These value
# mappings will ultimately be used to set the --max-rate flag for ndt-server.
# This is a roundabout way of informing a container about the uplink capacity.
curl --silent --output switches.json "https://siteinfo.mlab-oti.measurementlab.net/v1/sites/switches.json"
mkdir -p "${MAX_RATES_DIR}"
for r in $(jq -r 'keys[] as $k | "\($k):\(.[$k].uplink_speed)"' switches.json); do
  site=$(echo $r | cut -d: -f1)
  speed=$(echo $r | cut -d: -f2)
  for node in mlab1 mlab2 mlab3 mlab4; do
    if [[ "${speed}" == "1g" ]]; then
      echo "${MAX_RATE_1G}" > "${MAX_RATES_DIR}/$node.${site}.measurement-lab.org"
    elif [[ "${speed}" == "10g" ]]; then
      echo "${MAX_RATE_10G}" > "${MAX_RATES_DIR}/$node.${site}.measurement-lab.org"
    else
      echo "Site ${site} does not have a valid uplink_speed set: ${speed}"
      exit 1
    fi
  done
done

# Create the nodes max rates ConfigMap
kubectl create configmap "${MAX_RATES_CONFIGMAP}" \
    --from-file "${MAX_RATES_DIR}/" \
    --dry-run -o json > "../config/nodes-max-rate.json"

# Create the json configuration for the entire cluster (except for secrets)
jsonnet \
   --ext-str GCE_ZONE=${GCE_ZONE} \
   --ext-str K8S_CLUSTER_CIDR=${K8S_CLUSTER_CIDR} \
   --ext-str K8S_FLANNEL_VERSION=${K8S_FLANNEL_VERSION} \
   --ext-str PROJECT_ID=${PROJECT} \
   --ext-str PROJECT_ID=${PROJECT} \
   --ext-str DEPLOYMENTSTAMP=$(date +%s) \
   --ext-str MAX_RATES_CONFIGMAP=${MAX_RATES_CONFIGMAP} \
   ../system.jsonnet > system.json

# Download every secret, and turn each one into a config.
mkdir -p secrets
mkdir -p secret-configs

# Fetch and configure all the secrets.
gsutil cp -R gs://${!GCS_BUCKET_K8S}/ndt-tls secrets/.
gsutil cp -R gs://${!GCS_BUCKET_K8S}/wehe-ca secrets/.
gsutil cp gs://${!GCS_BUCKET_K8S}/uuid-annotator-credentials.json secrets/uuid-annotator.json
gsutil cp gs://${!GCS_BUCKET_K8S}/pusher-credentials.json secrets/pusher.json
gsutil cp gs://${!GCS_BUCKET_K8S}/fluentd-credentials.json secrets/fluentd.json
mkdir -p secrets/prometheus-etcd-tls
gsutil cp gs://${!GCS_BUCKET_K8S}/prometheus-etcd-tls/client.* secrets/prometheus-etcd-tls/
gsutil cp gs://${!GCS_BUCKET_K8S}/snmp-community/snmp.community secrets/snmp.community
gsutil cp gs://${!GCS_BUCKET_K8S}/prometheus-htpasswd secrets/auth

# Convert secret data into configs.
kubectl create secret generic uuid-annotator-credentials --from-file secrets/uuid-annotator.json \
    --dry-run -o json > secret-configs/uuid-annotator-credentials.json
kubectl create secret generic pusher-credentials --from-file secrets/pusher.json \
    --dry-run -o json > secret-configs/pusher-credentials.json
kubectl create secret generic ndt-tls --from-file secrets/ndt-tls/ \
    --dry-run -o json > secret-configs/ndt-tls.json
kubectl create secret generic wehe-ca --from-file secrets/wehe-ca/ \
    --dry-run -o json > secret-configs/wehe-ca.json
kubectl create secret generic fluentd-credentials --from-file secrets/fluentd.json \
    --dry-run -o json > secret-configs/fluentd-credentials.json
kubectl create secret generic prometheus-etcd-tls --from-file secrets/prometheus-etcd-tls/ \
    --dry-run -o json > secret-configs/prometheus-etcd-tls.json
kubectl create secret generic snmp-community --from-file secrets/snmp.community \
    --dry-run -o json > secret-configs/snmp-community.json
# NB: The file containing the user/password pair must be called 'auth'.
kubectl create secret generic prometheus-htpasswd --from-file secrets/auth \
    --dry-run -o json > secret-configs/prometheus-htpasswd.json

# Download the platform cluster CA cert.
gsutil cp gs://k8s-support-${PROJECT}/pki/ca.crt .

# Generate a hash of the CA cert.
# https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-join/#token-based-discovery-with-ca-pinning
ca_cert_hash=$(openssl x509 -pubkey -in ./ca.crt | \
    openssl rsa -pubin -outform der 2>/dev/null | \
    openssl dgst -sha256 -hex | sed 's/^.* //')

# Evaluate the setup_k8s.sh.template using the generated hash of the CA cert.
sed -e "s/{{CA_CERT_HASH}}/${ca_cert_hash}/" ../node/setup_k8s.sh.template \
    > ./setup_k8s.sh

# Upload the evaluated template to GCS.
cache_control="Cache-Control:private, max-age=0, no-transform"
gsutil -h "$cache_control" cp ./setup_k8s.sh gs://epoxy-${PROJECT}/stage3_coreos/setup_k8s.sh
