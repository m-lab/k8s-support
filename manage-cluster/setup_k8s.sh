#!/bin/bash

exec 2> /tmp/setup_k8s.log 1>&2
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
GCP_PROJECT=${1:?GCP Project is missing.}
# IPV4="$2"  # Currently unused.
HOSTNAME=${3:?Node hostname is missing.}
K8S_TOKEN_URL=${4:?k8s token URL is missing. Node cannot join k8s cluster.}

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

# Install all cni plugins into /opt/cni/bin so they can be edited
mkdir -p /opt/cni/bin
pushd /opt/cni/bin
  cp /usr/cni/bin/* .
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

# Copy the multus-cni configuration from the epoxy-image resources folder
# to /etc/cni/net.d/ - this makes sure kubelet can find it on first run.
mkdir -p /etc/cni/net.d
cp /usr/share/oem/multus-cni.conf /etc/cni/net.d

# Make the directory /etc/kubernetes/manifests. The declaration staticPodPath in
# `staticPodPath` /var/lib/kubelet/config.yaml defines this and is a standard
# for k8s. If it doesn't exist the kubelet logs a message every few seconds that
# it doesn't exist, polluting the logs terribly.
mkdir -p /etc/kubernetes/manifests

systemctl daemon-reload
systemctl enable docker
systemctl start docker

# Fetch k8s token via K8S_TOKEN_URL. Curl should report most errors to stderr.
TOKEN=$( curl --fail --silent --show-error -XPOST --data-binary "{}" ${K8S_TOKEN_URL} )
export PATH=/sbin:/usr/sbin:/opt/bin:${PATH}
# TODO: Stop regenerating the CA on every call to setup_cloud_k8s_master.sh so
# that we can hard-code the CA hash below without having to change it all the
# time.
kubeadm join "${MASTER_NODE}:6443" \
  --token "${TOKEN}" \
  --discovery-token-ca-cert-hash sha256:898b7a0f49edd7f80992d25e794b0362e7f8707c27a6322bcf8dd10f9d701d50

systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet

echo 'Success: everything we did appeared to work - good luck'
