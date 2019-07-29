#!/bin/bash

set -eux

ANNOTATION=${1:? Please pass an annotation as the first argument.}

API_URL="https://kubernetes.default.svc.cluster.local:443/api/v1/nodes"
KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

# Install curl
apk update
apk add curl

# Set the annotation via the REST API.
# Note: $UPDATE_AGENT_NODE is passed in via an environment variable.
curl -k -X PATCH \
    -H "Accept: application/json" \
    -H "Authorization: Bearer $KUBE_TOKEN" \
    -H "Content-Type: application/merge-patch+json" \
    -d "{\"metadata\":{\"annotations\":{\"${ANNOTATION}\":\"true\"}}}" \
    "${API_URL}/${UPDATE_AGENT_NODE}" \
