#!/bin/bash

set -euxo pipefail

# TODO(https://github.com/m-lab/k8s-support/issues/31) This script should be run
# by Travis to push to sandbox/staging/production in the ways that we have come
# to expect.

PROJECT=${GOOGLE_CLOUD_PROJECT:-mlab-sandbox}

gsutil -h "Cache-Control: private, max-age=0, no-transform" \
  cp setup_k8s.sh "gs://epoxy-${PROJECT}/stage3_coreos/setup_k8s.sh"

gsutil -h "Cache-Control: private, max-age=0, no-transform" \
  cp shim.sh "gs://k8s-support-${PROJECT}/bin/shim.sh"
