#!/bin/bash
#
# Creates a new cloud VM and joins it to the cluster for which
# k8s-platform-master is the master node.  This script is intended to be run
# (infrequently) by a human as we add more monitoring services to the platform
# k8s cluster and start needing more and higher capacity compute nodes running
# in cloud.
#
# TODO: Make the node be a CoreOS node instead of Ubuntu

set -euxo pipefail

USAGE="USAGE: $0 <google-cloud-project>"
PROJECT=${1:?Please specify the google cloud project: $USAGE}

# Source all the global configuration variables.
source k8s_deploy.conf

K8S_NODE_PREFIX="k8s-platform-cluster-node"

# Use the first k8s master from the region to contact to join this cloud node to
# the cluster.
GCE_ZONE="${GCE_REGION}-$(echo ${GCE_ZONES} | awk '{print $1}')"
K8S_MASTER="${GCE_BASE_NAME}-${GCE_ZONE}"

# Get a list of all VMs in the desired project that have a name in the right
# format (the format ends with a number) and find the lowest number that is not
# in the list (it may fill in a hole in the middle).
set +e  # The next command exits with nonzero, even when it works properly.
NEW_NODE_NUM=$(comm -1 -3 --nocheck-order \
    <(gcloud compute instances list \
        --project="${PROJECT}" \
        --filter="name~'${K8S_NODE_PREFIX}-\d+'" \
        --format='value(name)' \
      | sed -e 's/.*-//' \
      | sort -n) \
    <(seq 10000) \
  | head -n 1)
set -e

# Allocate a new VM with the right name.
#
# WARNING: As-is this setup potentially reduces the security guarantees of
# ePoxy.
# TODO: Stop putting nodes on epoxy-extension-private-network. We must redesign
# our GCP network setup to separate the "cluster network" from the "epoxy
# network".
NODE_NAME="${K8S_NODE_PREFIX}-${NEW_NODE_NUM}"
gcloud compute instances create "${NODE_NAME}" \
  --image-family "${GCE_IMAGE_FAMILY}" \
  --image-project "${GCE_IMAGE_PROJECT}" \
  --network "${GCE_NETWORK}" \
  --subnet "${GCE_K8S_SUBNET}" \
  --project="${PROJECT}" \
  --zone="${GCE_ZONE}"

sleep 120  # Wait for the node to appear
gcloud compute config-ssh --project="${PROJECT}"

# Ssh to the new node, install all the k8s binaries and make sure the node will
# be tagged as mlab/type:cloud when it joins.
#
# TODO: Figure out how to make the node ip be part of its registration. Possibly
# something like:
#   sed -e 's#KUBELET_NETWORK_ARGS=#KUBELET_NETWORK_ARGS=--node-ip=${EXTERNAL_IP} #' -i /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
# but including that exact line in the commands below causes the entire
# 'Addresses' section of the node config in k8s to not exist, which seems
# incorrect.
gcloud compute ssh --project="${PROJECT}" --zone="${GCE_ZONE}" "${NODE_NAME}" <<EOF
  sudo -s
  set -euxo pipefail
  apt-get update
  apt-get install -y docker.io

  apt-get update && apt-get install -y apt-transport-https curl
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  echo deb http://apt.kubernetes.io/ kubernetes-xenial main >/etc/apt/sources.list.d/kubernetes.list
  apt-get update
  apt-get install -y kubelet=${K8S_VERSION}-00 kubeadm=${K8S_VERSION}-00 kubectl=${K8S_VERSION}-00
  sed -e 's#KUBELET_KUBECONFIG_ARGS=#KUBELET_KUBECONFIG_ARGS=--node-labels=mlab/type=cloud #' -i /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
  systemctl daemon-reload
  systemctl enable docker.service
  systemctl restart kubelet
EOF

# Ssh to k8s-platform-master and create a new token for login.
#
# TODO: This approach feels weird and brittle or unsafe or just architecturally
# wrong.  It works, but we would prefer some strategy where the node registers
# itself instead of requiring that the user running this script also have root
# on k8s-platform-master.  We should figure out how that should work and do that
# instead of the below.
JOIN_COMMAND=$(tail -n1 <(gcloud compute ssh --project="${PROJECT}" --zone="${GCE_ZONE}" "${K8S_MASTER}" <<EOF
  sudo -s
  set -euxo pipefail
  kubeadm token create --ttl=5m --print-join-command --description="Token for ${NODE_NAME}"
EOF
))

# Ssh to the new node and use the newly created token to join the cluster.
gcloud compute ssh --project="${PROJECT}" --zone="${GCE_ZONE}" "${NODE_NAME}" <<EOF
  sudo -s
  set -euxo pipefail
  sudo ${JOIN_COMMAND}
EOF

# This command takes long enough that the race condition with node registration
# has resolved by the time this command returns.  If you move this assignment to
# earlier in the file, make sure to insert a sleep here so prevent the next
# lines from happening too soon after the initial registration.
EXTERNAL_IP=$(gcloud compute instances list \
    --format 'value(networkInterfaces[].accessConfigs[0].natIP)'\
    --project="${PROJECT}" \
    --filter="name~'${NODE_NAME}'")

# Ssh to the master and fix the network annotation for the node.
gcloud compute ssh --project="${PROJECT}" --zone="${GCE_ZONE}" "${K8S_MASTER}" <<EOF
  set -euxo pipefail
  kubectl annotate node ${NODE_NAME} flannel.alpha.coreos.com/public-ip-overwrite=${EXTERNAL_IP}
EOF
