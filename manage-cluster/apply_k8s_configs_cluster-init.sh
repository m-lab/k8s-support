#!/bin/bash

set -euxo pipefail

# Source the main configuration file.
source ./k8s_deploy.conf

export KUBECONFIG=/etc/kubernetes/admin.conf

# Upload the evaluated setup_k8s.sh template to GCS.
# TODO(kinkade): Move setup_k8s.sh to the epoxy-images repo to be baked into
# stage3 images, obviating the need for the static "version" path in GCS of
# "latest": https://github.com/m-lab/k8s-support/issues/569
cache_control="Cache-Control:private, max-age=0, no-transform"
gsutil -h "$cache_control" cp ./setup_k8s.sh gs://epoxy-${project}/latest/stage3_ubuntu/setup_k8s.sh

# Download helm and use it to install cert-manager and ingress-nginx
curl -O https://get.helm.sh/helm-${K8S_HELM_VERSION}-linux-amd64.tar.gz
tar -zxvf helm-${K8S_HELM_VERSION}-linux-amd64.tar.gz

# Add the required Helm repositories.
./linux-amd64/helm repo add jetstack https://charts.jetstack.io
./linux-amd64/helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
./linux-amd64/helm repo add vector https://helm.vector.dev

# Helm 3 does not automatically create namespaces anymore.
kubectl create namespace cert-manager --dry-run=client -o json | kubectl apply -f -
kubectl create namespace ingress-nginx --dry-run=client -o json | kubectl apply -f -
kubectl create namespace logging --dry-run=client -o json | kubectl apply -f -

# Install ingress-nginx and set it to run on the same node as prometheus-server.
./linux-amd64/helm upgrade --install ingress-nginx \
  --namespace ingress-nginx \
  --values ../helm/ingress-nginx/helm-values-overrides.yaml \
  ingress-nginx/ingress-nginx

# Install cert-manager and configure it to use the "letsencrypt" ClusterIssuer
# by default.
# https://docs.cert-manager.io/en/latest/getting-started/install/kubernetes.html
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/${K8S_CERTMANAGER_VERSION}/cert-manager.crds.yaml
./linux-amd64/helm upgrade --install cert-manager \
  --namespace cert-manager \
  --version ${K8S_CERTMANAGER_VERSION} \
  --values ../helm/cert-manager/helm-values-overrides.yaml \
  --debug \
  jetstack/cert-manager

# Replace per-project variables in Vector's values.yaml and install Vector.
sed -e "s|{{PROJECT}}|${project}|g" \
    -e "s|{{IMAGE}}|${K8S_VECTOR_IMAGE}|g" \
    ../helm/vector/values.yaml.template > \
    ../helm/vector/values.yaml

./linux-amd64/helm upgrade --install vector \
  --values ../helm/vector/values.yaml \
  --version ${K8S_VECTOR_CHART} \
  vector/vector

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
