#!/bin/bash

set -euxo pipefail

USAGE="USAGE: $0 <google-cloud-project> [<kubeconfig>]"
PROJECT=${1:?Please specify the google cloud project: $USAGE}
KUBECONFIG=${2:-}

# Source the main configuration file.
source ./k8s_deploy.conf

if [[ -n "${KUBECONFIG}" ]]; then
  export KUBECONFIG="${KUBECONFIG}"
else
  # If a KUBECONFIG wasn't passed as an argument to the script, then attempt to
  # fetch it from the first master node in the cluster.

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

  gcloud compute ssh ${GCE_NAME} --command "sudo cat /etc/kubernetes/admin.conf" \
      "${GCE_ARGS[@]}" > ./kube-config
  export KUBECONFIG=./kube-config
fi

# Upload the evaluated setup_k8s.sh template to GCS.
cache_control="Cache-Control:private, max-age=0, no-transform"
gsutil -h "$cache_control" cp ./setup_k8s.sh gs://epoxy-${PROJECT}/stage3_coreos/setup_k8s.sh
gsutil -h "$cache_control" cp ./setup_k8s.sh gs://epoxy-${PROJECT}/stage3_ubuntu/setup_k8s.sh

# Download helm and use it to install cert-manager and ingress-nginx
curl -O https://get.helm.sh/helm-${K8S_HELM_VERSION}-linux-amd64.tar.gz
tar -zxvf helm-${K8S_HELM_VERSION}-linux-amd64.tar.gz

# Add the required Helm repositories.
./linux-amd64/helm repo add jetstack https://charts.jetstack.io
./linux-amd64/helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
./linux-amd64/helm repo add vector https://packages.timber.io/helm/nightly

# Helm 3 does not automatically create namespaces anymore.
kubectl create namespace cert-manager --dry-run=client -o json | kubectl apply -f -
kubectl create namespace ingress-nginx --dry-run=client -o json | kubectl apply -f -
kubectl create namespace logging --dry-run=client -o json | kubectl apply -f -

# Install ingress-nginx and set it to run on the same node as prometheus-server.
./linux-amd64/helm upgrade --install ingress-nginx \
  --namespace ingress-nginx \
  --values ../config/ingress-nginx/helm-values-overrides.yaml \
  ingress-nginx/ingress-nginx

# Install cert-manager and configure it to use the "letsencrypt" ClusterIssuer
# by default.
# https://docs.cert-manager.io/en/latest/getting-started/install/kubernetes.html
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/${K8S_CERTMANAGER_VERSION}/cert-manager.crds.yaml
./linux-amd64/helm upgrade --install cert-manager \
  --namespace cert-manager \
  --version ${K8S_CERTMANAGER_VERSION} \
  --values ../config/cert-manager/helm-values-overrides.yaml \
  jetstack/cert-manager

# Install Vector and configure to export to Google Stackdriver.

# Replace per-project variables in Vector's values.yaml.
sed -e "s/{{PROJECT}}/${PROJECT}/" ../config/vector/values.yaml.template \
  > ../config/vector/values.yaml

# TODO(roberto) update to a non-nightly version as soon as it's available.
./linux-amd64/helm upgrade --install vector \
  --version 0.11.0-nightly-2020-10-12 \
  --values ../config/vector/values.yaml \
  vector/vector

# Apply the configuration

# The configurations of the secrets for the cluster happen in a separate
# directory. We might publicly aechive system.json. We should never make any
# part of secret-configs public.  They are our passwords and private keys!
kubectl apply -f secret-configs/

# We call 'kubectl apply -f system.json' three times because kubectl doesn't
# support defining and declaring certain objects in the same file. This is a
# bug in kubectl, and so we call it three times as a workaround for the bug.
kubectl apply -f system.json || true
kubectl apply -f system.json || true
# Sleep for a bit to give all pods a chance to start. Specifically, this
# command will fail, causing the build to fail, if cert-manager-webhook is
# not up and running.
sleep 60
kubectl apply -f system.json
