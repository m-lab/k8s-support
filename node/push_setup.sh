#!/bin/bash

set -euxo pipefail

gsutil -h "Cache-Control: private, max-age=0, no-transform" \
  cp node_k8s_setup.sh gs://epoxy-mlab-staging/stage3_coreos/setup_k8s.sh
