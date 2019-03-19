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
gcloud compute ssh ${GCE_NAME} \
    --command "sudo cat /etc/kubernetes/admin.conf" "${GCE_ARGS[@]}" > ./kube-config
export KUBECONFIG=./kube-config

# Fetch Secrets from GCS.
gsutil cp -R gs://${!GCS_BUCKET_K8S}/ndt-tls .
gsutil cp gs://${!GCS_BUCKET_K8S}/pusher-credentials.json ./pusher.json

# Apply Secrets.
kubectl create secret generic pusher-credentials --from-file pusher.json || :
kubectl create secret generic ndt-tls --from-file ndt-tls/ || :

# Apply RBAC configs.
kubectl apply -f ../k8s/roles/

# Apply ConfigMaps
kubectl create configmap pusher-dropbox --from-literal "bucket=pusher-${PROJECT}" || :
kubectl create configmap prometheus-config --from-file ../config/prometheus/prometheus.yml || :
kubectl create configmap prometheus-synthetic-textfile-metrics \
    --from-file ../config/prometheus-synthetic-textfile-metrics || :

# Apply DaemonSets
# Apply does not seem to be working if pods are already running.  As a workaround
# we have been manually running 'kubectl delete ds ndt', (e.g. to remove the ndt pods), then
# rerunning the first apply command.
kubectl apply -f ../k8s/daemonsets/experiments/
kubectl apply -f ../k8s/daemonsets/core/

# Apply Deployments
# kubectl delete -f ../k8s/deployments/
kubectl apply -f ../k8s/deployments/
