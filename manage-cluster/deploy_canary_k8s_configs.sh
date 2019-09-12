#!/bin/bash

set -euxo pipefail

USAGE="USAGE: $0 <google-cloud-project> <kubeconfig>"
PROJECT=${1:?Please specify the google cloud project: $USAGE}
KUBECONFIG=${2:?Please specify a valid KUBECONFIG: $USAGE}

export KUBECONFIG=$KUBECONFIG

# Create the canary configurations.
jsonnet \
   --ext-str PROJECT_ID=${PROJECT} \
   --ext-code CANARY=true \
   ../canaries.jsonnet > canaries.json

# Apply the canary configurations to the cluster.
kubectl apply -f canaries.json
