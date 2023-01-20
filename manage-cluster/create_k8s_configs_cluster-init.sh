#!/bin/bash

set -euxo pipefail

# Source the main configuration file.
source ./k8s_deploy.conf

GCS_BUCKET_K8S="GCS_BUCKET_K8S_${project//-/_}"

# Create the json configuration for the entire cluster (except for secrets)
jsonnet \
   --ext-str GCE_ZONE=${zone} \
   --ext-str K8S_CLUSTER_CIDR=${cluster_cidr} \
   --ext-str K8S_FLANNEL_VERSION=${K8S_FLANNEL_VERSION} \
   --ext-str PROJECT_ID=${project} \
   --ext-str DEPLOYMENTSTAMP=$(date +%s) \
   ../system.jsonnet > system.json

# Download every secret, and turn each one into a config.
mkdir -p secrets
mkdir -p secret-configs

# Fetch and configure all the secrets.
gsutil cp -R gs://${!GCS_BUCKET_K8S}/ndt-tls secrets/.
gsutil cp -R gs://${!GCS_BUCKET_K8S}/wehe-ca secrets/.
gsutil cp gs://${!GCS_BUCKET_K8S}/uuid-annotator-credentials.json secrets/uuid-annotator.json
gsutil cp gs://${!GCS_BUCKET_K8S}/pusher-credentials.json secrets/pusher.json
gsutil cp gs://${!GCS_BUCKET_K8S}/cert-manager-credentials.json secrets/cert-manager.json
gsutil cp gs://${!GCS_BUCKET_K8S}/vector-credentials.json secrets/vector.json
gsutil cp gs://${!GCS_BUCKET_K8S}/snmp-community/snmp.community secrets/snmp.community
gsutil cp gs://${!GCS_BUCKET_K8S}/prometheus-htpasswd secrets/auth
# The alertmanager-basicauth.yaml file is already a valid k8s YAML Secret
# specification, so copy it directly to the secret-configs/ directory.
gsutil cp gs://${!GCS_BUCKET_K8S}/alertmanager-basicauth.yaml secret-configs/.
gsutil cp -R gs://${!GCS_BUCKET_K8S}/locate secrets/.
gsutil cp -R gs://${!GCS_BUCKET_K8S}/locate-heartbeat secrets/.

# Convert secret data into configs.
kubectl create secret generic uuid-annotator-credentials --from-file secrets/uuid-annotator.json \
    --dry-run=client -o json > secret-configs/uuid-annotator-credentials.json
kubectl create secret generic pusher-credentials --from-file secrets/pusher.json \
    --dry-run=client -o json > secret-configs/pusher-credentials.json
kubectl create secret generic cert-manager-credentials --namespace cert-manager \
    --from-file secrets/cert-manager.json \
    --dry-run=client -o json > secret-configs/cert-manager-credentials.json
kubectl create secret generic ndt-tls --from-file secrets/ndt-tls/ \
    --dry-run=client -o json > secret-configs/ndt-tls.json
kubectl create secret generic wehe-ca --from-file secrets/wehe-ca/ \
    --dry-run=client -o json > secret-configs/wehe-ca.json
kubectl create secret generic vector-credentials --from-file secrets/vector.json \
    --dry-run=client -o json > secret-configs/vector.json
kubectl create secret generic snmp-community --from-file secrets/snmp.community \
    --dry-run=client -o json > secret-configs/snmp-community.json
# NB: The file containing the user/password pair must be called 'auth'.
kubectl create secret generic prometheus-htpasswd --from-file secrets/auth \
    --dry-run=client -o json > secret-configs/prometheus-htpasswd.json
kubectl create secret generic locate-verify-keys --from-file secrets/locate/ \
    --dry-run=client -o json > secret-configs/locate-verify-keys.json
kubectl create secret generic locate-heartbeat-key --from-file secrets/locate-heartbeat/ \
    --dry-run=client -o json > secret-configs/locate-heartbeat-key.json

# Evaluate the setup_k8s.sh.template using the generated hash of the CA cert.
sed -e "s/{{CA_CERT_HASH}}/${ca_cert_hash}/" ../node/setup_k8s.sh.template \
    > ./setup_k8s.sh

