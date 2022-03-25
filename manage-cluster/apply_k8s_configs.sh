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

# Upgrade kubectl the lastest version supported the SDK release. The specific
# impetus for this is:
# https://cert-manager.io/docs/installation/upgrading/upgrading-0.16-1.0/#issue-with-older-versions-of-kubectl
# ... but otherwise it can't really hurt.
gcloud --quiet components update kubectl

# Upload the evaluated setup_k8s.sh template to GCS.
# TODO(kinkade): Move setup_k8s.sh to the epoxy-images repo to be baked into
# stage3 images, obviating the need for the static "version" path in GCS of
# "latest": https://github.com/m-lab/k8s-support/issues/569
cache_control="Cache-Control:private, max-age=0, no-transform"
gsutil -h "$cache_control" cp ./setup_k8s.sh gs://epoxy-${PROJECT}/latest/stage3_ubuntu/setup_k8s.sh

# Download helm and use it to install cert-manager and ingress-nginx
curl -O https://get.helm.sh/helm-${K8S_HELM_VERSION}-linux-amd64.tar.gz
tar -zxvf helm-${K8S_HELM_VERSION}-linux-amd64.tar.gz

# Add the required Helm repositories.
./linux-amd64/helm repo add jetstack https://charts.jetstack.io
./linux-amd64/helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
./linux-amd64/helm repo add fluent https://fluent.github.io/helm-charts

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

# Install fluent-bit and configure to export to Google Stackdriver.

# Replace per-project variables in fluent-bit's values.yaml.
sed -e "s|{{PROJECT}}|${PROJECT}|g" \
    -e "s|{{IMAGE}}|${K8S_FLUENTBIT_VERSION}|g" \
    ../config/fluent-bit/values.yaml.template > \
    ../config/fluent-bit/values.yaml

./linux-amd64/helm upgrade --install fluent-bit fluent/fluent-bit

# Apply the configuration

# The configurations of the secrets for the cluster happen in a separate
# directory. We might publicly archive system.json. We should never make any
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
