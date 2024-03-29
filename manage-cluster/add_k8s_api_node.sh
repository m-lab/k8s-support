#!/bin/bash
#
# Adds a new master node to an existing k8s cluster. This script assumes that
# there are functional nodes in the API cluster for both of the other zones not
# being added.
#
# IMPORTANT: This script is intended to be used _very_ infrequently. It's use
# case is for when an API node is accidentally deleted or otherwise corrupted
# and cannot be easily recovered. The expectation is that node was ungracefully
# removed or broken without doing any sort of cluster cleanup first.

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
  WARNING: this script is intended to be used to recreate an API node VM that
  was accidentally deleted, corrupted beyond repair, or otherwise broken, and
  the node was ungracefully removed without any cluster cleanup. If all you want
  to do is to recreate an existing, healthy API node, then please use the
  recreate_api_node.sh script.

  Are you sure you want to continue? [y/N]:
EOF
read keepgoing
if [[ "${keepgoing}" != "y" ]]; then
  exit 0
fi

# The "bootstrap" zone will be the first zone in the list of zones for the
# project that is _not_ the zone of the node being added.
for z in $GCE_ZONES; do
  if [[ "$z" != "${ZONE}" ]]; then
    BOOTSTRAP_MASTER="master-${GCE_BASE_NAME}-${GCE_REGION}-${z}"
    BOOTSTRAP_MASTER_ZONE="${GCE_REGION}-${z}"
    break
  fi
done

# Be sure that a master doesn't already exist in the specified zone.
EXISTING_MASTER=$(gcloud compute instances list \
    --filter "name=${GCE_NAME}" \
    --format "value(name)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_MASTER}" ]]; then
  echo "A master node already exists in zone ${GCE_ZONE}. Exiting."
  exit 1
fi

# Be sure that the node that is being added is already deleted from the k8s
# cluster and etcd.
gcloud compute ssh "${BOOTSTRAP_MASTER}" "${GCP_ARGS[@]}" --zone "${BOOTSTRAP_MASTER_ZONE}" <<EOF
  set -eoux pipefail
  sudo --login

  # Run set again for use inside the sudo shell
  set -eoux pipefail

  export PATH=\$PATH:/opt/bin

  # Remove the node from the cluster.
  if kubectl get nodes | grep ${GCE_NAME}; then
    kubectl delete node ${GCE_NAME}
  fi

  # See if the node is a member of the etcd cluster, and if so, delete it.
  delete_node=\$(etcdctl member list | grep ${GCE_NAME} || true)
  if [[ -n "\${delete_node}" ]]; then
    node_id=\$(echo "\${delete_node}" | cut -d, -f1)
    etcdctl member remove \$node_id
  fi

  # Remove the node from the ClusterStatus key of kubeadm-config ConfigMap (in
  # kube-system namespace). If this isn't done, the new node will fail to join
  # because kubeadm will think the etcd cluster is down, even though it isn't.
  # It's basing it's decision on the etcd endpoints it *thinks* should exist
  # per the kubeadm-config, even though the live cluster doesn't have that node.
  # https://github.com/kubernetes/kubernetes/blob/master/cmd/kubeadm/app/util/etcd/etcd.go#L81
  #
  # Extract the ClusterStatus, removing the reference to the node that was
  # deleted. The sed statement matches the deleted node name, then deletes that
  # line and the 2 lines after it.
  kubectl get configmap kubeadm-config -n kube-system -o jsonpath='{.data.ClusterStatus}' | \
      sed -e "/$GCE_NAME/,+2d" > ClusterStatus
  # Extract the ClusterConfiguration
  kubectl get configmap kubeadm-config -n kube-system -o jsonpath='{.data.ClusterConfiguration}' \
      > ClusterConfiguration
  # Generate the new ConfigMap using the two files we just created, and replace the existing ConfigMap.
  kubectl create configmap kubeadm-config -n kube-system \
      --from-file ClusterConfiguration \
      --from-file ClusterStatus \
      -o yaml --dry-run=client | kubectl replace -f -
EOF

# If they exist, delete the node name from various loadbalancer group resources.
delete_server_backend "${GCE_NAME}" "${GCE_ZONE}" "${TOKEN_SERVER_BASE_NAME}"
delete_server_backend "${GCE_NAME}" "${GCE_ZONE}" "${BMC_STORE_PASSWORD_BASE_NAME}"
delete_server_backend "${GCE_NAME}" "${GCE_ZONE}" "${GCE_BASE_NAME}"
delete_instance_group "${GCE_NAME}" "${GCE_ZONE}"

# Now add the new master.
create_master "${ZONE}" "${REBOOT_DAY}"
