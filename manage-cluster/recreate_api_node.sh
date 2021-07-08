#!/bin/bash
#
# Recreates an existing, healthy API node in an existing k8s cluster. This
# script assumes that there are functional nodes in the API cluster for both of
# the other zones not being recreated.
#
# The use case for this script is when there is a need to recreate an existing,
# healthy API node e.g., an upgrade to the base OS image. This script will allow
# an operator to recreate the API cluster one node at a time, with no downtime
# for the cluster.

set -euxo pipefail

USAGE="$0 <project> <zone> <reboot-day>"
PROJECT=${1:?Please provide the GCP project (e.g., mlab-sandbox): ${USAGE}}
ZONE=${2:?Please provide a GCE zone for the new node (e.g., c): ${USAGE}}
REBOOT_DAY=${3:?Please provide a reboot day (Tue, Wed or Thu): ${USAGE}}

# Include global configs and the bootstrap function "library".
source k8s_deploy.conf
source bootstraplib.sh

GCE_REGION_VAR="GCE_REGION_${PROJECT//-/_}"
GCE_REGION="${!GCE_REGION_VAR}"
GCE_ZONES_VAR="GCE_ZONES_${PROJECT//-/_}"
GCE_ZONES="${!GCE_ZONES_VAR}"
GCE_ZONE="${GCE_REGION}-${ZONE}"
GCE_NAME="master-${GCE_BASE_NAME}-${GCE_ZONE}"

GCS_BUCKET_K8S="GCS_BUCKET_K8S_${PROJECT//-/_}"

GCP_ARGS=("--project=${PROJECT}" "--quiet")
GCE_ARGS=("--zone=${GCE_ZONE}" "${GCP_ARGS[@]}")

ETCD_CLUSTER_STATE="existing"

# Issue a warning to the user and only continue if they agree.
cat <<EOF
  WARNING: this script will delete the following API cluster node VM, remove it
  from the cluster, and recreate it:

  ${GCE_NAME}

  Are you sure you want to continue? [y/N]:
EOF
read keepgoing
if [[ "${keepgoing}" != "y" ]]; then
  exit 0
fi

# The "bootstrap" zone will be the first zone in the list of zones for the
# project that is _not_ the zone of the node being recreated.
for z in $GCE_ZONES; do
  if [[ "$z" != "${ZONE}" ]]; then
    BOOTSTRAP_MASTER="master-${GCE_BASE_NAME}-${GCE_REGION}-${z}"
    BOOTSTRAP_MASTER_ZONE="${GCE_REGION}-${z}"
    break
  fi
done

# Use `kubeadm reset` to gracefully undo most of what `kubeadm join/init`
# initially did. It also removes the node from the etcd cluster and removes it
# from the ClusterStatus key of the kubeadm-config ConfigMap.
gcloud compute ssh "${GCE_NAME}" "${GCE_ARGS[@]}" <<EOF
  set -eoux pipefail
  sudo --login

  # Run set again for use inside the sudo shell
  set -eoux pipefail

  kubeadm reset --force
EOF

# Delete the VM
gcloud compute instances delete "${GCE_NAME}" "${GCE_ARGS[@]}"

# `kubeadm reset` does not remove the node from the cluster, so take care of
# that here, if the node is still part of the cluster.
if kubectl --context "${PROJECT}" get nodes | grep ${GCE_NAME}; then
  kubectl --context "${PROJECT}" delete node "${GCE_NAME}"
fi

# If they exist, delete the node name from various loadbalancer group resources.
delete_server_backend "${GCE_NAME}" "${GCE_ZONE}" "${TOKEN_SERVER_BASE_NAME}"
delete_server_backend "${GCE_NAME}" "${GCE_ZONE}" "${BMC_STORE_PASSWORD_BASE_NAME}"
delete_server_backend "${GCE_NAME}" "${GCE_ZONE}" "${GCE_BASE_NAME}"
delete_instance_group "${GCE_NAME}" "${GCE_ZONE}"

# Now add the new master.
create_master "${ZONE}" "${REBOOT_DAY}"
