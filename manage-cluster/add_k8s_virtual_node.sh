#!/bin/bash
#
# Creates a new cloud VM and joins it to the cluster for which
# master-platform-master-<zone> is the master node.  This script is intended to
# be run (infrequently) by a human as we add more monitoring services to the
# platform k8s cluster and start needing more and higher capacity compute nodes
# running in cloud.
#
# NOTE: The distinction between GCE_NAME and HOST_NAME is that GCE_NAME, as the
# name implies, is the name of the VM in GCP, while HOST_NAME is the name of
# the kubernetes node. This distinction is necessary because GCE does not allow
# VM names with dots (`.`), while k8s node name may have dots. Many of our
# tools expect a node name to be of the standard format (e.g.,
# node1.abc02.measurement-lab.org). In the case that this script is being used
# to add a node to the k8s platform cluster, then -h must be specified with a
# standard M-Lab node name.

set -euxo pipefail

usage() {
  echo "USAGE: $0 -p <project> [-z <gcp-zone>] [-m <machine-type>] [-n <gce-name>] [-H <hostname>] [-a <address>] [-t <gce-tag> ...] [-l <k8s-label> ...]"
}

ADDRESS=""
HOST_NAME=""
LABELS=""
MACHINE_TYPE=""
GCE_NAME=""
GCE_ZONE=""
PROJECT=""
TAGS=""

while getopts ':a:H:l:m:n:p:t:z:' opt; do
  case $opt in
    a) ADDRESS=$OPTARG ;;
    H) HOST_NAME=$OPTARG ;;
    l) LABELS="$LABELS $OPTARG" ;;
    m) MACHINE_TYPE=$OPTARG ;;
    n) GCE_NAME=$OPTARG ;;
    p) PROJECT=$OPTARG ;;
    t)
      if [[ -z "${TAGS}" ]]; then
        TAGS="$OPTARG"
      else
        TAGS="$TAGS,$OPTARG"
      fi
      ;;
    z) GCE_ZONE=$OPTARG ;;
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

MASTER_ZONE="${!GCE_REGION}-$(echo ${!GCE_ZONES} | awk '{print $1}')"
GCP_ARGS=("--project=${PROJECT}" "--quiet")

if [[ -z "${GCE_ZONE}" ]]; then
  GCE_ARGS=("--zone=${MASTER_ZONE}" "${GCP_ARGS[@]}")
else
  GCE_ARGS=("--zone=${GCE_ZONE}" "${GCP_ARGS[@]}")
fi

# Use the first k8s master from the region to contact to join this cloud node to
# the cluster.
K8S_MASTER="master-${GCE_BASE_NAME}-${MASTER_ZONE}"

if [[ -z "$GCE_NAME" ]]; then
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
  GCE_NAME="${K8S_CLOUD_NODE_BASE_NAME}-${NEW_NODE_NUM}"
fi

if [[ -n "${ADDRESS}" ]]; then
  ADDRESS_FLAG="--address ${ADDRESS}"
else
  ADDRESS_FLAG=""
fi

if [[ -n "${HOST_NAME}" ]]; then
  HOSTNAME_FLAG="--hostname ${HOST_NAME}"
  K8S_NODE_NAME="${HOST_NAME}"
else
  HOSTNAME_FLAG=""
  K8S_NODE_NAME="${GCE_NAME}"
fi

if [[ -n "${TAGS}" ]]; then
  TAGS_FLAG="--tags ${TAGS}"
else
  TAGS_FLAG=""
fi

if [[ -z "${MACHINE_TYPE}" ]]; then
  MACHINE_TYPE="n1-standard-1"
fi

# Allocate a new VM.
gcloud compute instances create "${GCE_NAME}" \
  ${HOSTNAME_FLAG} \
  --image-family "${GCE_IMAGE_FAMILY}" \
  --image-project "${GCE_IMAGE_PROJECT}" \
  --machine-type "${MACHINE_TYPE}" \
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
until gcloud compute ssh "${GCE_NAME}" --command true --ssh-flag "-o PasswordAuthentication=no" "${GCE_ARGS[@]}" && \
      sleep 10 && \
      gcloud compute ssh "${GCE_NAME}" --command true --ssh-flag "-o PasswordAuthentication=no" "${GCE_ARGS[@]}"; do
  echo Waiting for "${GCE_NAME}" to boot up.
  # Refresh keys in case they changed mid-boot. They change as part of the
  # GCE bootup process, and it is possible to ssh at the precise moment a
  # temporary key works, get that key put in your permanent storage, and have
  # all future communications register as a MITM attack.
  #
  # Same root cause as the need to ssh twice in the loop condition above.
  gcloud compute config-ssh "${GCP_ARGS[@]}"
done

# Ssh to the new node, install all the k8s binaries.
gcloud compute ssh "${GCE_NAME}" "${GCE_ARGS[@]}" <<EOF
  set -euxo pipefail
  sudo --login

  # Bash options are not inherited by subshells. Reset them to exit on any error.
  set -euxo pipefail

  # Binaries will get installed in /opt/bin, put it in root's PATH
  # Write it to .profile and .bashrc so that it get loaded on both interactive
  # and non-interactive session.
  echo "export PATH=\$PATH:/opt/bin" >> /root/.profile
  echo "export PATH=\$PATH:/opt/bin" >> /root/.bashrc

  # Adds /opt/bin to the end of the secure_path sudoers configuration.
  sed -i -e '/secure_path/ s|"$|:/opt/bin"|' /etc/sudoers

  # Install CNI plugins.
  mkdir -p /opt/cni/bin
  curl --location "https://github.com/containernetworking/plugins/releases/download/${K8S_CNI_VERSION}/cni-plugins-linux-amd64-${K8S_CNI_VERSION}.tgz" | tar -C /opt/cni/bin -xz

  # Install the Flannel CNI plugin.
  # v0.9.1 of the official CNI plugins release stopped including flannel, so we
  # must now install it manually from its official source.
  curl --location "https://github.com/flannel-io/cni-plugin/releases/download/${K8S_FLANNELCNI_VERSION}/flannel-amd64" > /opt/cni/bin/flannel
  chmod +x /opt/cni/bin/flannel

  # Install crictl.
  mkdir -p /opt/bin
  curl --location "https://github.com/kubernetes-incubator/cri-tools/releases/download/${K8S_CRICTL_VERSION}/crictl-${K8S_CRICTL_VERSION}-linux-amd64.tar.gz" | tar -C /opt/bin -xz

  # Install a few network-related packages.
  apt install -y conntrack ebtables iptables socat

  # Install kubeadm, kubelet and kubectl.
  cd /opt/bin
  curl --location --remote-name-all https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/{kubeadm,kubelet,kubectl}
  chmod +x {kubeadm,kubelet,kubectl}

  # Install kubelet systemd service and enable it.
  curl --silent --show-error --location \
    "https://raw.githubusercontent.com/kubernetes/release/${K8S_TOOLING_VERSION}/cmd/kubepkg/templates/latest/deb/kubelet/lib/systemd/system/kubelet.service" \
	| sed "s:/usr/bin:/opt/bin:g" | sudo tee /etc/systemd/system/kubelet.service

  mkdir -p /etc/systemd/system/kubelet.service.d
  curl --silent --show-error --location \
    "https://raw.githubusercontent.com/kubernetes/release/${K8S_TOOLING_VERSION}/cmd/kubepkg/templates/latest/deb/kubeadm/10-kubeadm.conf" \
	| sed "s:/usr/bin:/opt/bin:g" | sudo tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

  # Override the node name, which without this will be something like:
  #     ${K8S_NODE_NAME}.c.mlab-sandbox.internal
  # https://kubernetes.io/docs/concepts/architecture/nodes/#addresses
  echo "KUBELET_EXTRA_ARGS='--hostname-override ${K8S_NODE_NAME}'" > /etc/default/kubelet

  # Enable and start the kubelet service
  systemctl enable --now kubelet.service
  systemctl daemon-reload
  systemctl restart kubelet
EOF

# Ssh to master-platform-master-<zone> and create a new token for login.
#
# TODO: This approach feels weird and brittle or unsafe or just architecturally
# wrong.  It works, but we would prefer some strategy where the node registers
# itself instead of requiring that the user running this script also have root
# on master-platform-master-<zone>.  We should figure out how that should work
# and do that instead of the below.
JOIN_COMMAND=$(tail -n1 <(gcloud compute ssh "${K8S_MASTER}" --zone "${MASTER_ZONE}" "${GCP_ARGS[@]}" <<EOF
  set -euxo pipefail
  sudo --login

  # Bash options are not inherited by subshells. Reset them to exit on any error.
  set -euxo pipefail

  kubeadm token create --ttl=5m --print-join-command --description="Token for ${GCE_NAME}"
EOF
))

# Ssh to the new node and use the newly created token to join the cluster.
gcloud compute ssh "${GCE_NAME}" "${GCE_ARGS[@]}" <<EOF
  set -euxo pipefail
  sudo --login

  # Bash options are not inherited by subshells. Reset them to exit on any error.
  set -euxo pipefail

  # It is possible that at this point cloud-init is not done configuring the
  # system. Wati until it is done before attempting to join the cluster.
  while [[ ! -f /var/lib/cloud/instance/boot-finished ]]; do
    echo "Waiting for cloud-init to finish before joining the cluster."
    sleep 10
  done

  ${JOIN_COMMAND} --v=4 --node-name ${K8S_NODE_NAME}
EOF

# This command takes long enough that the race condition with node registration
# has resolved by the time this command returns.  If you move this assignment to
# earlier in the file, make sure to insert a sleep here so prevent the next
# lines from happening too soon after the initial registration.
EXTERNAL_IP=$(gcloud compute instances list \
    --format 'value(networkInterfaces[].accessConfigs[0].natIP)'\
    --project="${PROJECT}" \
    --filter="name~'${GCE_NAME}'")

# Ssh to the new VM and write out various pieces of metadata to the filesystem.
# These bits of metadata can be used by various services running on the VM to
# know more about their environment. For example, an experiment might use the
# metadata to label data that it produces so that someone querying the data in
# BigQuery could discover more about the operating environment of the experiment.
gcloud compute ssh "${GCE_NAME}" "${GCE_ARGS[@]}" <<EOF
  set -euxo pipefail
  sudo --login

  # Bash options are not inherited by subshells. Reset them to exit on any error.
  set -euxo pipefail

  metadata_dir=/var/local/metadata

  mkdir -p \$metadata_dir

  echo $GCE_ZONE > "\${metadata_dir}/zone"
  echo $EXTERNAL_IP > "\${metadata_dir}/external-ip"
  echo $MACHINE_TYPE > "\${metadata_dir}/machine-type"
EOF

# Ssh to the master and fix the network annotation for the node.
gcloud compute ssh "${K8S_MASTER}" --zone "${MASTER_ZONE}" "${GCP_ARGS[@]}" <<EOF
  set -euxo pipefail
  sudo --login

  # Bash options are not inherited by subshells. Reset them to exit on any error.
  set -euxo pipefail

  kubectl annotate node ${K8S_NODE_NAME} \
      flannel.alpha.coreos.com/public-ip-overwrite=${EXTERNAL_IP} \
      --overwrite=true

  for label in ${K8S_CLOUD_NODE_LABELS}; do
    kubectl label nodes ${K8S_NODE_NAME} \${label} --overwrite=true
  done

  # Add any labels passed as arguments to this script.
  for label in ${LABELS}; do
    kubectl label nodes ${K8S_NODE_NAME} \${label} --overwrite=true
  done
EOF
