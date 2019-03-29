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
GCE_NAME="${GCE_BASE_NAME}-${GCE_ZONE}"

GCS_BUCKET_K8S="GCS_BUCKET_K8S_${PROJECT//-/_}"

# Fetch the kubeconfig from the first master so we can run kubectl commands
# locally
gcloud --project ${PROJECT} compute ssh ${GCE_NAME} \
    --command "sudo cat /etc/kubernetes/admin.conf" "${GCE_ARGS[@]}" > ./kube-config
export KUBECONFIG=./kube-config

# Fetch Secrets from GCS.
gsutil cp -R gs://${!GCS_BUCKET_K8S}/ndt-tls .
gsutil cp gs://${!GCS_BUCKET_K8S}/pusher-credentials.json ./pusher.json

# Evaluate template files.
sed -e "s|{{K8S_CLUSTER_CIDR}}|${K8S_CLUSTER_CIDR}|g" \
     ../config/flannel/flannel.yml.template > \
     ../config/flannel/flannel.yml
sed -e "s|{{K8S_FLANNEL_VERSION}}|${K8S_FLANNEL_VERSION}|g" \
    ../k8s/daemonsets/core/flannel-cloud.yml.template > \
    ../k8s/daemonsets/core/flannel-cloud.yml
sed -e "s|{{K8S_FLANNEL_VERSION}}|${K8S_FLANNEL_VERSION}|g" \
    ../k8s/daemonsets/core/flannel-platform.yml.template > \
    ../k8s/daemonsets/core/flannel-platform.yml

# Apply Namespaces
kubectl apply -f ../k8s/namespaces/

# Apply CustomResourceDefinitions. Among other possible things, this will apply
# NetworkAttachmentDefinitions used by multus-cni.
kubectl apply -f ../k8s/custom-resource-definitions/

# Apply Secrets.
kubectl create secret generic pusher-credentials --from-file pusher.json \
    --dry-run -o json | kubectl apply -f -
kubectl create secret generic ndt-tls --from-file ndt-tls/ \
    --dry-run -o json | kubectl apply -f -

# Apply RBAC configs.
kubectl apply -f ../k8s/roles/

# Apply ConfigMaps
kubectl create configmap prometheus-config --from-file ../config/flannel/flannel.yml \
    --dry-run -o json | kubectl apply -f -
kubectl create configmap pusher-dropbox --from-literal "bucket=pusher-${PROJECT}" \
    --dry-run -o json | kubectl apply -f -
kubectl create configmap prometheus-config --from-file ../config/prometheus/prometheus.yml \
    --dry-run -o json | kubectl apply -f -
kubectl create configmap prometheus-synthetic-textfile-metrics \
    --from-file ../config/prometheus-synthetic-textfile-metrics \
    --dry-run -o json | kubectl apply -f -

# Apply DaemonSets
kubectl apply -f ../k8s/daemonsets/experiments/
kubectl apply -f ../k8s/daemonsets/core/

# Apply Deployments
kubectl apply -f ../k8s/deployments/
