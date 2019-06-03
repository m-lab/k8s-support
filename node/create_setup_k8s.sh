#!/bin/sh
#
# A small script meant to be run with an alpine Docker image in Google Cloud
# Build which determines the hash of the k8s platform cluster CA cert, and then
# uses that to evaluate the setup_k8s.sh template.

set -euxo pipefail

apk add openssl

# Generate a hash of the CA cert.
# https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-join/#token-based-discovery-with-ca-pinning
ca_cert_hash=$(openssl x509 -pubkey -in ./ca.crt | \
    openssl rsa -pubin -outform der 2>/dev/null | \
    openssl dgst -sha256 -hex | sed 's/^.* //')

sed -e "s/{{CA_CERT_HASH}}/${ca_cert_hash}/" /workspace/node/setup_k8s.sh.template \
    > /workspace/setup_k8s.sh
