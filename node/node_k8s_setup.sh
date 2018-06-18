#!/bin/bash

exec 2> /tmp/k8s_setup.log 1>&2
set -euxo pipefail

# This script is intended to be called by epoxy as the action for the last stage
# in the boot process.  The actual epoxy config that calls this file can be
# found at:
#   https://github.com/m-lab/epoxy-images/blob/dev/actions/stage3_coreos/stage3post.json

# This should be the final step in the boot process. Prior to this script
# running, we should have made sure that the disk is partitioned appropriately
# and mounted in the right places (one place to serve as a cache for Docker
# images, the other two to serve as repositories for core system data and
# experiment data, respectively)

# Save the arguments
GCP_PROJECT="$1"
# IPV4="$2"  # Currently unused.
HOSTNAME="$3"
# K8S_TOKEN_URL="$4"  # Currently unused

# Turn the hostname into its component parts.
MACHINE=$(echo "${HOSTNAME}" | tr . ' ' | awk '{ print $1 }')
SITE=$(echo "${HOSTNAME}" | tr . ' ' | awk '{ print $2 }')
METRO="${SITE/[0-9]*/}"

# Make sure to download any and all necessary auth tokens prior to this point.
# It should be a simple wget from the master node to make that happen.
MASTER_NODE="k8s-platform-master.${GCP_PROJECT}.measurementlab.net"

# TODO(https://github.com/m-lab/k8s-support/issues/29) This installation of
# things into etc should be done as part of cloud-config.yml or ignition or just
# something besides this script.
# Install things in /etc
# Startup configs for the kubelet
RELEASE=$(cat /usr/share/oem/installed_k8s_version.txt)
mkdir -p /etc/systemd/system
curl --silent --show-error --location "https://raw.githubusercontent.com/kubernetes/kubernetes/${RELEASE}/build/debs/kubelet.service" > /etc/systemd/system/kubelet.service

# TODO: Once all CNI plugins are built into the image, stop copying things into
# /opt/cni/bin and make shim.sh call the read-only binaries in /usr/cni/bin.

# Install all cni plugins into /opt/cni/bin
mkdir -p /opt/cni/bin
pushd /opt/cni/bin
  cp /usr/cni/bin/* .
  # Install index_to_ip into /opt/cni/bin
  # TODO: Build index_to_ip into the epoxy image
  # TODO: Use index2ip built in go rather than the horrible index_to_ip shell
  # script.
  wget "https://storage.googleapis.com/k8s-platform-${GCP_PROJECT}/bin/index_to_ip"
  chmod +x index_to_ip
popd

# Make all the shims so that network plugins can be debugged
mkdir -p /opt/shimcni/bin
pushd /opt/shimcni/bin
  wget "https://storage.googleapis.com/k8s-platform-${GCP_PROJECT}/bin/shim.sh"
  chmod +x shim.sh
  for i in /opt/cni/bin/*; do
    ln -s /opt/shimcni/bin/shim.sh /opt/shimcni/bin/$(basename "$i")
  done
popd

# Add node tags to the kubelet so that node metadata is there right at the very
# beginning, and make sure that the kubelet has the right directory for the cni
# plugins.
#
# TODO: Don't make running the CNI plugins via the shim be the default.
#
# TODO: Add annotations to the node as well as labels. The annotations should
#       contain most of /proc/cmdline as well as the args to this script.
NODE_LABELS="mlab/machine=${MACHINE},mlab/site=${SITE},mlab/metro=${METRO},mlab/type=platform"
mkdir -p /etc/systemd/system/kubelet.service.d
curl --silent --show-error --location "https://raw.githubusercontent.com/kubernetes/kubernetes/${RELEASE}/build/debs/10-kubeadm.conf" \
  | sed -e "s|KUBELET_KUBECONFIG_ARGS=|KUBELET_KUBECONFIG_ARGS=--node-labels=$NODE_LABELS |g" \
  | sed -e 's|--cni-bin-dir=[^ "]*|--cni-bin-dir=/opt/shimcni/bin|' \
  > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

systemctl daemon-reload
systemctl enable docker
systemctl start docker
systemctl enable kubelet
systemctl start kubelet

TOKEN=$(curl "http://${MASTER_NODE}:8000" | grep token | awk '{print $2}' | sed -e 's/"//g')
export PATH=/sbin:/usr/sbin:/opt/bin:${PATH}
# TODO: Stop regenerating the CA on every call to setup_cloud_k8s_master.sh so
# that we can hard-code the CA hash below without having to change it all the
# time.
kubeadm join "${MASTER_NODE}:6443" \
  --token "${TOKEN}" \
  --discovery-token-ca-cert-hash sha256:f9ee71f7c93a6f562a7bf18ea61670f208c1b7506ea2a225a5a8948a6ff49b39
