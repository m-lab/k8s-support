#!/bin/bash

set -euxo pipefail

PROJECT=${GOOGLE_CLOUD_PROJECT:-mlab-staging}

gsutil -h "Cache-Control: private, max-age=0, no-transform" \
  cp node_k8s_setup.sh "gs://epoxy-${PROJECT}/stage3_coreos/setup_k8s.sh"
