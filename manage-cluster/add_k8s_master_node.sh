#!/bin/bash
#
# A script that can add a new master node to a k8s cluster.
#
# NOTE: If a master node in the same zone already existed then you will want to
# both manually delete the node from the k8s cluster as well as manually
# removing the node from the etcd cluster. Removing the node from the k8s
# cluster is as simple as `kubectl delete node <node name>`. Deleting the nodce
# from the etcd cluster can be achieved with the following (run on an existing
# master node):
#
# $ etcdctl member list
# // Note the endpoint ID (a 16 char sring)
# $ etcdctl member remove <ID>

set -euxo pipefail

USAGE="$0 <cloud project> <zone> <existing master>"
PROJECT=${1:?Please provide the cloud project (e.g., mlab-sandbox): ${USAGE}}
ZONE=${2:?Please provide a GCP zone (e.g., c): ${USAGE}}
BOOTSTRAP_MASTER=${3:?Please provide the GCE name of any existing master node: ${USAGE}}

source k8s_deploy.conf
source bootstraplib.sh

GCE_REGION_VAR="GCE_REGION_${PROJECT//-/_}"
GCE_REGION="${!GCE_REGION_VAR}"
GCE_ZONE="${GCE_REGION}-${ZONE}"
GCE_NAME="${GCE_BASE_NAME}-${GCE_ZONE}"

GCS_BUCKET_K8S="GCS_BUCKET_K8S_${PROJECT//-/_}"

GCP_ARGS=("--project=${PROJECT}" "--quiet")
GCE_ARGS=("--zone=${GCE_ZONE}" "${GCP_ARGS[@]}")

ETCD_CLUSTER_STATE="existing"
ETCD_INITIAL_CLUSTER=""

# This command returns the existing master cluster nodes and their internal IP
# addresses.
SSH_COMMAND="PATH=\$PATH:/opt/bin kubectl get nodes --selector=node-role.kubernetes.io/master -o jsonpath='{range .items[*]}{@.metadata.name}{\",\"}{@.status.addresses[?(@.type==\"InternalIP\")].address}{\"\n\"}{end}'"

# Determine the GCE zone of the bootstrap master node.
BOOTSTRAP_MASTER_ZONE=$(gcloud compute instances list \
    --filter "name=${BOOTSTRAP_MASTER}" \
    --format "value(zone)" \
    "${GCP_ARGS[@]}" || true)
if [[ -z "${BOOTSTRAP_MASTER_ZONE}" ]]; then
  echo "Could not determine the zone of ${BOOTSTRAP_MASTER}. Exiting."
  exit 1
fi

# Be sure that a master doesn't already exist in the specified zone.
EXISTING_MASTER=$(gcloud compute instances list \
    --filter "name=${GCE_NAME}" \
    --format "value(name)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_MASTER}" ]]; then
  echo "A master node already exists in zone ${GCE_ZONE}. Exiting."
  exit 1
fi

master_nodes=$(gcloud compute ssh "${BOOTSTRAP_MASTER}" \
    --command "${SSH_COMMAND}" \
    --project "${PROJECT}" --zone "${BOOTSTRAP_MASTER_ZONE}")
# Populates ETCD_INITIAL_CLUSTER with all existing etcd cluster nodes.
for node in $master_nodes; do
  node_name=$(echo $node | cut -d, -f1)
  node_ip=$(echo $node | cut -d, -f2)

  if [[ -z "${ETCD_INITIAL_CLUSTER}" ]]; then
    ETCD_INITIAL_CLUSTER="${node_name}=https://${node_ip}:2380"
    FIRST_INSTANCE_NAME="${node_name}"
    FIRST_INSTANCE_IP="${node_ip}"
  else
    ETCD_INITIAL_CLUSTER="${ETCD_INITIAL_CLUSTER},${node_name}=https://${node_ip}:2380"
  fi
done

delete_token_server_backend "${GCE_NAME}" "${GCE_ZONE}"
delete_target_pool_instance "${GCE_NAME}" "${GCE_ZONE}"
delete_instance_group "${GCE_NAME}" "${GCE_ZONE}"
create_master "${ZONE}"
