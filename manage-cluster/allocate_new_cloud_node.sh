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

GCE_REGION="GCE_REGION_${PROJECT/-/_}"
GCE_ZONES="GCE_ZONES_${PROJECT/-/_}"

GCE_ZONE="${!GCE_REGION}-$(echo ${!GCE_ZONES} | awk '{print $1}')"
GCP_ARGS=("--project=${PROJECT}" "--quiet")
GCE_ARGS=("--zone=${GCE_ZONE}" "${GCP_ARGS[@]}")

# Use the first k8s master from the region to contact to join this cloud node to
# the cluster.
K8S_MASTER="${GCE_BASE_NAME}-${GCE_ZONE}"

# Get a list of all VMs in the desired project that have a name in the right
# format (the format ends with a number) and find the lowest number that is
# not in the list (it may fill in a hole in the middle).
set +e  # The next command exits with nonzero, even when it works properly.
NEW_NODE_NUM=$(comm -1 -3 --nocheck-order \
    <(gcloud compute instances list \
        --filter="name~'${K8S_NODE_PREFIX}-\d+'" \
        --format='value(name)' \
        "${GCP_ARGS[@]}" \
      | sed -e 's/.*-//' \
      | sort -n) \
    <(seq 10000) \
  | head -n 1)
set -e

NODE_NAME="${K8S_CLOUD_NODE_BASE_NAME}-${NEW_NODE_NUM}"

# Allocate a new VM.
gcloud compute instances create "${NODE_NAME}" \
  --image-family "${GCE_IMAGE_FAMILY}" \
  --image-project "${GCE_IMAGE_PROJECT}" \
  --network "${GCE_NETWORK}" \
  --subnet "${GCE_K8S_SUBNET}" \
  "${GCE_ARGS[@]}"

# Give the instance time to appear.  Make sure it appears twice - there have
# been multiple instances of it connecting just once and then failing again for
# a bit.
until gcloud compute ssh "${NODE_NAME}" --command true "${GCE_ARGS[@]}" && \
      sleep 10 && \
      gcloud compute ssh "${NODE_NAME}" --command true "${GCE_ARGS[@]}"; do
  echo Waiting for "${NODE_NAME}" to boot up.
  # Refresh keys in case they changed mid-boot. They change as part of the
  # GCE bootup process, and it is possible to ssh at the precise moment a
  # temporary key works, get that key put in your permanent storage, and have
  # all future communications register as a MITM attack.
  #
  # Same root cause as the need to ssh twice in the loop condition above.
  gcloud compute config-ssh "${GCP_ARGS[@]}"
done

# Ssh to the new node, install all the k8s binaries.
gcloud compute ssh "${NODE_NAME}" "${GCE_ARGS[@]}" <<EOF
  sudo -s
  set -euxo pipefail
  apt-get update
  apt-get install -y docker.io

  apt-get update && apt-get install -y apt-transport-https curl
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  echo deb http://apt.kubernetes.io/ kubernetes-xenial main >/etc/apt/sources.list.d/kubernetes.list
  apt-get update
  apt-get install -y kubelet=${K8S_VERSION}-${K8S_PKG_VERSION} kubeadm=${K8S_VERSION}-${K8S_PKG_VERSION} kubectl=${K8S_VERSION}-${K8S_PKG_VERSION}

  # Create a suitable cloud-config file for the cloud provider and set the cloud
  # provider to "gce".
  echo -e "[Global]\nproject-id = ${PROJECT}\n" > /etc/kubernetes/cloud-provider.conf
  echo 'KUBELET_EXTRA_ARGS="--cloud-provider=gce --cloud-config=/etc/kubernetes/cloud-provider.conf"' > \
      /etc/default/kubelet

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
JOIN_COMMAND=$(tail -n1 <(gcloud compute ssh "${K8S_MASTER}" "${GCE_ARGS[@]}" <<EOF
  sudo -s
  set -euxo pipefail
  kubeadm token create --ttl=5m --print-join-command --description="Token for ${NODE_NAME}"
EOF
))

# Ssh to the new node and use the newly created token to join the cluster.
gcloud compute ssh "${NODE_NAME}" "${GCE_ARGS[@]}" <<EOF
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
gcloud compute ssh "${K8S_MASTER}" "${GCE_ARGS[@]}" <<EOF
  set -euxo pipefail
  kubectl annotate node ${NODE_NAME} flannel.alpha.coreos.com/public-ip-overwrite=${EXTERNAL_IP}
  for label in ${K8S_CLOUD_NODE_LABELS}; do
    kubectl label nodes ${NODE_NAME} \${label}
  done

  # Work around a known issue with --cloud-provider=gce and CNI plugins.
  # https://github.com/kubernetes/kubernetes/issues/44254
  # Without the following action a node will have a node-condition of
  # NetworkUnavailable=True, which has the result of a taint getting added to
  # the node which may prevent some pods from getting scheduled on the node if
  # they don't explicitly tolerate the taint.
  kubectl proxy --port 8888 &> /dev/null &
  # Give the proxy a couple seconds to start up.
  sleep 2
  curl http://localhost:8888/api/v1/nodes/${NODE_NAME}/status > a.json
  cat a.json | tr -d '\n' | sed 's/{[^}]\+NetworkUnavailable[^}]\+}/{"type": "NetworkUnavailable","status": "False","reason": "RouteCreated","message": "Manually set through k8s API."}/g' > b.json
  curl -X PUT http://localhost:8888/api/v1/nodes/${NODE_NAME}/status -H "Content-Type: application/json" -d @b.json
  kill %1
EOF

