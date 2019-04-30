#!/bin/bash

set -euxo pipefail

USAGE="USAGE: $0 <google-cloud-project> [<kubeconfig>]"
PROJECT=${1:?Please specify the google cloud project: $USAGE}
KUBECONFIG=${2:-}

if [[ -n "${KUBECONFIG}" ]]; then
  export KUBECONFIG="${KUBECONFIG}"
fi

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
GCE_NAME="${GCE_BASE_NAME}-${GCE_ZONE}"

GCS_BUCKET_K8S="GCS_BUCKET_K8S_${PROJECT//-/_}"

# Create the json configuration for the entire cluster (without secrets)
docker run -it -v $(cd ..; pwd):$(cd ..; pwd) -w $(pwd) sparkprime/jsonnet \
   --ext-str GCE_ZONE=$GCE_ZONE \
   --ext-str K8S_CLUSTER_CIDR=$K8S_CLUSTER_CIDR \
   --ext-str K8S_FLANNEL_VERSION=$K8S_FLANNEL_VERSION \
   --ext-str PROJECT_ID=$PROJECT \
   ../system.jsonnet > system.json

exit

# If a KUBECONFIG wasn't passed as an argument to the script, then attempt to
# fetch it from the first master node in the cluster.
if [[ -z "${KUBECONFIG}" ]]; then
  gcloud compute ssh ${GCE_NAME} --command "sudo cat /etc/kubernetes/admin.conf" \
      "${GCE_ARGS[@]}" > ./kube-config
  export KUBECONFIG=./kube-config
fi

# Apply the configuration

# We call 'kubectl apply -f system.json' three times because kubectl doesn't
# support defining and declaring certain objects in the same file. This is a
# bug in kubectl, and so we call it three times as a workaround for the bug.
kubectl apply -f system.json || true
kubectl apply -f system.json || true
kubectl apply -f system.json


# Fetch and configure all the secrets.
# Fetch Secrets from GCS, if they don't already exist locally.
if [[ ! -d "./ndt-tls" ]]; then
  gsutil cp -R gs://${!GCS_BUCKET_K8S}/ndt-tls .
fi
if [[ ! -f "./pusher.json" ]]; then
  gsutil cp gs://${!GCS_BUCKET_K8S}/pusher-credentials.json ./pusher.json
fi
if [[ ! -f "./fluentd.json" ]]; then
  gsutil cp gs://${!GCS_BUCKET_K8S}/fluentd-credentials.json ./fluentd.json
fi
if [[ ! -d "./etcd-tls" ]]; then
  mkdir -p ./etcd-tls
  gsutil cp gs://${!GCS_BUCKET_K8S}/pki/etcd/peer.* ./etcd-tls/
fi
if [[ ! -d "./reboot-api" ]]; then
  gsutil cp -R gs://${!GCS_BUCKET_K8S}/reboot-api .
fi

# Apply Secrets.
kubectl create secret generic pusher-credentials --from-file pusher.json \
    --dry-run -o json | kubectl apply -f -
kubectl create secret generic ndt-tls --from-file ndt-tls/ \
    --dry-run -o json | kubectl apply -f -
kubectl create secret generic fluentd-credentials --from-file fluentd.json \
    --dry-run -o json | kubectl apply -f -
kubectl create secret generic etcd-tls --from-file etcd-tls/ \
    --dry-run -o json | kubectl apply -f -
kubectl create secret generic reboot-api-credentials --from-file reboot-api/ \
    --dry-run -o json | kubectl apply -f -
