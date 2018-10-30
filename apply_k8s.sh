#!/bin/bash

set -euxo pipefail

USAGE="USAGE: $0 <google-cloud-project>"
PROJECT=${1:?Please specify the google cloud project: $USAGE}

# Apply Secrets
#
# TODO: figure out how to apply secrets automatically. For now these should be
# applied manually before anything else.
#
# If you don't know where to find a copy of pusher.json, then you may need to go
# into the pusher-dropbox-writer service account and generate a new JSON
# authentication key. NOTE: the JSON file are GCP project specific, so you will
# need to generate three new ones, one per project.
#
# Ask an Ops person how to find the NDT TLS certificate and private key.  Once
# in hand, you'll need to create a directory named ndt-tls/ and drop they key in
# there as "key.pem" and the certificate as "cert.pem".
# 
# Commands:
# 
# $ kubectl create secret generic pusher-credentials --from-file pusher.json
# $ kubectl create secret generic ndt-tls --from-file ndt-tls/

# Apply RBAC configs
kubectl apply -f k8s/roles/

# Apply ConfigMaps
kubectl create configmap pusher-dropbox --from-literal "bucket=pusher-${PROJECT}"
kubectl create configmap prometheus-config --from-file config/prometheus/prometheus.yml

# Apply Deployments
# 
# NOTE: the Prometheus deployment will only schedule pods on nodes with both of the
# following labels, and for now not more than a single node should have the
# label prometheus-node=true:
#     mlab/type=cloud
#     prometheus-node=true
kubectl apply -f k8s/deployments/prometheus.yml

# Apply DaemonSets
kubectl apply -f k8s/daemonsets/core/node-exporter.yml
kubectl apply -f k8s/daemonsets/experiments/ndt-cloud-with-fast-sidestream.yml
