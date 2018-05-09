#!/bin/bash

exec 2> /tmp/k8s_setup.log 1>&2
set -euxo pipefail

# This should be the final step. Prior to this script running, we should have
# made sure that the disk is partitioned appropriately and mounted in the right
# places (one place to serve as a cache for Docker images, the other two to
# serve as repositories for core system data and experiment data, respectively)

# Make sure to download any and all necessary auth tokens prior to this point.
# It should be a simple wget from the master node to make that happen.
MASTER_NODE=k8s-platform-master.mlab-sandbox.measurementlab.net

# TODO(https://github.com/m-lab/k8s-support/issues/29) This installation of
# things into etc should be done as part of cloud-config.yml or ignition or just
# something besides this script.
# Install things in /etc
# Startup configs for the kubelet
RELEASE=$(cat /usr/share/oem/installed_k8s_version.txt)
mkdir -p /etc/systemd/system
curl --silent --show-error --location "https://raw.githubusercontent.com/kubernetes/kubernetes/${RELEASE}/build/debs/kubelet.service" > /etc/systemd/system/kubelet.service
mkdir -p /etc/systemd/system/kubelet.service.d
curl --silent --show-error --location "https://raw.githubusercontent.com/kubernetes/kubernetes/${RELEASE}/build/debs/10-kubeadm.conf" > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

systemctl daemon-reload
systemctl enable docker
systemctl start docker
systemctl enable kubelet
systemctl start kubelet

TOKEN=$(curl "http://${MASTER_NODE}:8000" | grep token | awk '{print $2}' | sed -e 's/"//g')
export PATH=/sbin:/usr/sbin:/opt/bin:${PATH}
kubeadm join "${MASTER_NODE}:6443" \
  --token "${TOKEN}" \
  --discovery-token-ca-cert-hash sha256:69dc2a47883159b22c97cbfabab65f81136104ece2f854f35d3b8b6a268a2607
