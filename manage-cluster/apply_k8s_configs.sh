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

# Download helm and use it to install cert-manager and ingress-nginx
curl -O https://get.helm.sh/helm-${K8S_HELM_VERSION}-linux-amd64.tar.gz
tar -zxvf helm-${K8S_HELM_VERSION}-linux-amd64.tar.gz

# Add the required Helm repositories.
./linux-amd64/helm repo add jetstack https://charts.jetstack.io
./linux-amd64/helm repo add stable https://kubernetes-charts.storage.googleapis.com/
./linux-amd64/helm repo update

# Helm 3 does not automatically create namespaces anymore.
kubectl create namespace cert-manager || true
kubectl create namespace nginx-ingress || true

# Install ingress-nginx and set it to run on the same node as prometheus-server.
./linux-amd64/helm install nginx-ingress \
  --namespace nginx-ingress \
  --set rbac.create=true \
  --set controller.nodeSelector.run=prometheus-server \
  --set defaultBackend.nodeSelector.run=prometheus-server \
  --set controller.service.enabled=false \
  --set controller.hostNetwork=true \
  stable/nginx-ingress || true

# Install cert-manager and configure it to use the "letsencrypt" ClusterIssuer
# by default.
# https://docs.cert-manager.io/en/latest/getting-started/install/kubernetes.html
kubectl apply --validate=false -f https://raw.githubusercontent.com/jetstack/cert-manager/${K8S_CERTMANAGER_RESOURCES_VERSION}/deploy/manifests/00-crds.yaml
./linux-amd64/helm install cert-manager \
  --namespace cert-manager \
  --version ${K8S_CERTMANAGER_VERSION} \
  --set ingressShim.defaultIssuerName=letsencrypt \
  --set ingressShim.defaultIssuerKind=ClusterIssuer \
  jetstack/cert-manager || true

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
kubectl apply -f system.json
