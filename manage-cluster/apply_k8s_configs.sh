#!/bin/bash

set -euxo pipefail

USAGE="USAGE: $0 <google-cloud-project> [<kubeconfig>]"
PROJECT=${1:?Please specify the google cloud project: $USAGE}
KUBECONFIG=${2:-}

if [[ -n "${KUBECONFIG}" ]]; then
  export KUBECONFIG="${KUBECONFIG}"
else
  # If a KUBECONFIG wasn't passed as an argument to the script, then attempt to
  # fetch it from the first master node in the cluster.

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

  gcloud compute ssh ${GCE_NAME} --command "sudo cat /etc/kubernetes/admin.conf" \
      "${GCE_ARGS[@]}" > ./kube-config
  export KUBECONFIG=./kube-config
fi

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

# Apply the canary DaemonSets
kubectl apply -f canaries.json

