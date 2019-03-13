#!/bin/bash
#
# Creates a new cloud VM and joins it to the cluster for which
# k8s-platform-master is the master node.  This script is intended to be run
# (infrequently) by a human as we add more monitoring services to the platform
# k8s cluster and start needing more and higher capacity compute nodes running
# in cloud.

set -euxo pipefail

usage() {
  echo "USAGE: $0 -p <project> [-n <node-name>] [-a <address>] [-t <gce-tag> ...] [-l <k8s-label> ...]"
}

LABELS=""
TAGS=""

while getopts ':p:n:a:l:t:' opt; do
  case $opt in
    p) PROJECT=$OPTARG ;;
    n) NODE_NAME=$OPTARG ;;
    a) ADDRESS=$OPTARG ;;
    l) LABELS="$LABELS $OPTARG" ;;
    t)
      if [[ -z "${TAGS}" ]]; then
        TAGS="$OPTARG"
      else
        TAGS="$TAGS,$OPTARG"
      fi
      ;;
    \?) echo "Invalid option: -$OPTARG"; usage; exit 1 ;;
    :) echo "Options -$OPTARG requires a argument."; usage; exit 1 ;;
  esac
done

if [[ -z $PROJECT ]]; then
  echo "Please specify the GCP project with the -p flag."
  usage
  exit 1
fi

# Source all the global configuration variables.
source k8s_deploy.conf

GCE_REGION="GCE_REGION_${PROJECT//-/_}"
GCE_ZONES="GCE_ZONES_${PROJECT//-/_}"

GCE_ZONE="${!GCE_REGION}-$(echo ${!GCE_ZONES} | awk '{print $1}')"
GCP_ARGS=("--project=${PROJECT}" "--quiet")
GCE_ARGS=("--zone=${GCE_ZONE}" "${GCP_ARGS[@]}")

# Use the first k8s master from the region to contact to join this cloud node to
# the cluster.
K8S_MASTER="${GCE_BASE_NAME}-${GCE_ZONE}"

if [[ -z "$NODE_NAME" ]]; then
  # Get a list of all VMs in the desired project that have a name in the right
  # format (the format ends with a number) and find the lowest number that is
  # not in the list (it may fill in a hole in the middle).
  set +e  # The next command exits with nonzero, even when it works properly.
  NEW_NODE_NUM=$(comm -1 -3 --nocheck-order \
      <(gcloud compute instances list \
          --filter="name~'${K8S_CLOUD_NODE_BASE_NAME}-\d+'" \
          --format='value(name)' \
          "${GCP_ARGS[@]}" \
        | sed -e 's/.*-//' \
        | sort -n) \
      <(seq 10000) \
    | head -n 1)
  set -e
  NODE_NAME="${K8S_CLOUD_NODE_BASE_NAME}-${NEW_NODE_NUM}"
fi

if [[ -n "${ADDRESS}" ]]; then
  ADDRESS_FLAG="--address ${ADDRESS}"
else
  ADDRESS_FLAG=""
fi

if [[ -n "${TAGS}" ]]; then
  TAGS_FLAG="--tags ${TAGS}"
else
  TAGS_FLAG=""
fi

# Allocate a new VM.
gcloud compute instances create "${NODE_NAME}" \
  --image-family "${GCE_IMAGE_FAMILY}" \
  --image-project "${GCE_IMAGE_PROJECT}" \
  --network "${GCE_NETWORK}" \
  ${ADDRESS_FLAG} \
  ${TAGS_FLAG} \
  --subnet "${GCE_K8S_SUBNET}" \
  --scopes "${GCE_API_SCOPES}" \
  --metadata-from-file "user-data=cloud-config_node.yml" \
  "${GCE_ARGS[@]}"

# Give the instance time to appear.  Make sure it appears twice - there have
# been multiple instances of it connecting just once and then failing again for
# a bit.
until gcloud compute ssh "${NODE_NAME}" --command true --ssh-flag "-o PasswordAuthentication=no" "${GCE_ARGS[@]}" && \
      sleep 10 && \
      gcloud compute ssh "${NODE_NAME}" --command true --ssh-flag "-o PasswordAuthentication=no" "${GCE_ARGS[@]}"; do
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
  set -euxo pipefail
  sudo -s

  # Bash options are not inherited by subshells. Reset them to exit on any error.
  set -euxo pipefail

  # Binaries will get installed in /opt/bin, put it in root's PATH
  echo "export PATH=$PATH:/opt/bin" >> /root/.bashrc

  # Install CNI plugins.
  mkdir -p /opt/cni/bin
  curl -L "https://github.com/containernetworking/plugins/releases/download/${K8S_CNI_VERSION}/cni-plugins-amd64-${K8S_CNI_VERSION}.tgz" | tar -C /opt/cni/bin -xz

  # Install crictl.
  mkdir -p /opt/bin
  curl -L "https://github.com/kubernetes-incubator/cri-tools/releases/download/${K8S_CRICTL_VERSION}/crictl-${K8S_CRICTL_VERSION}-linux-amd64.tar.gz" | tar -C /opt/bin -xz

  # Install kubeadm, kubelet and kubectl.
  cd /opt/bin
  curl -L --remote-name-all https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/{kubeadm,kubelet,kubectl}
  chmod +x {kubeadm,kubelet,kubectl}

  # Install kubelet systemd service and enable it.
  curl -sSL "https://raw.githubusercontent.com/kubernetes/kubernetes/${K8S_VERSION}/build/debs/kubelet.service" \
      | sed "s:/usr/bin:/opt/bin:g" > /etc/systemd/system/kubelet.service
  mkdir -p /etc/systemd/system/kubelet.service.d
  curl -sSL "https://raw.githubusercontent.com/kubernetes/kubernetes/${K8S_VERSION}/build/debs/10-kubeadm.conf" \
      | sed "s:/usr/bin:/opt/bin:g" > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

  # Override the node name, which without this will be something like:
  #     ${NODE_NAME}.c.mlab-sandbox.internal
  # https://kubernetes.io/docs/concepts/architecture/nodes/#addresses
  echo "KUBELET_EXTRA_ARGS='--hostname-override ${NODE_NAME}'" > /etc/default/kubelet

  # Enable and start the kubelet service
  systemctl enable --now kubelet.service
  systemctl daemon-reload
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
  set -euxo pipefail
  sudo -s

  # Bash options are not inherited by subshells. Reset them to exit on any error.
  set -euxo pipefail

  kubeadm token create --ttl=5m --print-join-command --description="Token for ${NODE_NAME}"
EOF
))

# Ssh to the new node and use the newly created token to join the cluster.
gcloud compute ssh "${NODE_NAME}" "${GCE_ARGS[@]}" <<EOF
  set -euxo pipefail
  sudo -s

  # Bash options are not inherited by subshells. Reset them to exit on any error.
  set -euxo pipefail

  sudo ${JOIN_COMMAND} --node-name ${NODE_NAME}
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
  sudo -s

  # Bash options are not inherited by subshells. Reset them to exit on any error.
  set -euxo pipefail

  kubectl annotate node ${NODE_NAME} \
      flannel.alpha.coreos.com/public-ip-overwrite=${EXTERNAL_IP} \
      --overwrite=true

  for label in ${K8S_CLOUD_NODE_LABELS}; do
    kubectl label nodes ${NODE_NAME} \${label} --overwrite=true
  done

  # Add any labels passed as arguments to this script.
  for label in ${LABELS}; do
    kubectl label nodes ${NODE_NAME} \${label} --overwrite=true
  done
EOF

