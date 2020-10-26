#!/bin/bash
#
# bootstrap_k8s_master_cluster.sh sets up the master node in GCE for k8s in the
# cloud.
#
# By default (with no special environment variables set) it will set up in
# mlab-sandbox.  To change the defaults, override the shell variables
# ${GOOGLE_CLOUD_PROJECT}, ${GOOGLE_CLOUD_ZONE}, and ${K8S_GCE_MASTER}.
#
# This script is intended to eventually be run from Travis, but right now
# requires a human.  Be careful with it, as it changes your default gcloud
# project and zone.

set -euxo pipefail

USAGE="$0 <cloud project>"
PROJECT=${1:?Please provide the cloud project: ${USAGE}}

# Source all of the global configuration variables.
source k8s_deploy.conf

# Source bootstraplib.sh which contains various helper functions.
source bootstraplib.sh

# Issue a warning to the user and only continue if they agree.
cat <<EOF
  WARNING: this script is destructive. It will completely delete and then
  recreate from scratch absolutely everything in the k8s platform cluster,
  including ALL ETCD DATA. The cluster in its entirety, including all etcd data,
  will be irrevoacably lost.  Only continue if this is what you intend. Do you
  want to continue [y/N]:
EOF
read keepgoing
if [[ "${keepgoing}" != "y" ]]; then
  exit 0
fi

# Create a string representing region and zone variable names for this project.
GCE_REGION_VAR="GCE_REGION_${PROJECT//-/_}"
GCE_ZONES_VAR="GCE_ZONES_${PROJECT//-/_}"

# Dereference the region and zones variables.
GCE_REGION="${!GCE_REGION_VAR}"
GCE_ZONES="${!GCE_ZONES_VAR}"

# Set up project GCS bucket variables. NOTE: these will need to be dereferenced
# to use them.
GCS_BUCKET_EPOXY="GCS_BUCKET_EPOXY_${PROJECT//-/_}"
GCS_BUCKET_K8S="GCS_BUCKET_K8S_${PROJECT//-/_}"

# NOTE: GCP currently only offers tcp/udp network load balacing on a regional level.
# If we want more redundancy than GCP zones offer, then we'll need to figure out
# some way to use a proxying load balancer.
#
# The external load balancer will always be located in the first specified zone.
# TODO: remove if unused.
EXTERNAL_LB_ZONE="${GCE_REGION}-$(echo ${GCE_ZONES_VAR} | awk '{print $1}')"

# Delete any temporary files and dirs from a previous run.
rm -f setup_k8s.sh transaction.yaml

# Put gcloud in the PATH when on Travis.
if [[ ${TRAVIS:-false} == true ]]; then
  # Source a bash include file to put gcloud on the path.
  # Tell the linter to skip path.bash.inc
  # shellcheck source=/dev/null
  source "${HOME}/google-cloud-sdk/path.bash.inc"
fi

# Error out if gcloud is unavailable.
if ! which gcloud; then
  echo "The google-cloud-sdk must be installed and gcloud in your path."
  exit 1
fi

# Error out if gsutil is unavailable.
if ! which gsutil; then
  echo "The google-cloud-sdk must be installed and gsutil in your path."
  exit 1
fi

# Error out if jsonnet is unavailable.
if ! which jsonnet; then
  echo "The jsonnet utility must be installed and in your path."
  exit 1
fi

# Arrays of arguments are slightly cumbersome but using them ensures that if a
# space ever appears in an arg, then later usage of these values should not
# break in strange ways.
GCP_ARGS=("--project=${PROJECT}" "--quiet")


# VERIFY EXISTENCE OF REQUIRED RESOURCES
#
# Don't proceed if any required resources are missing.
EXISTING_VPC_NETWORK=$(gcloud compute networks describe "${GCE_NETWORK}" \
    --format "value(name)" \
    "${GCP_ARGS[@]}" || true)
if [[ -z "${EXISTING_VPC_NETWORK}" ]]; then
  echo "VPC network ${GCE_NETWORK} does not exist. Please create it manually."
  exit 1
fi

EXISTING_EPOXY_SUBNET=$(gcloud compute networks subnets describe \
    "${GCE_EPOXY_SUBNET}" \
    --region "${GCE_REGION}" \
    --format "value(name)" \
    "${GCP_ARGS[@]}")
if [[ -z "${EXISTING_EPOXY_SUBNET}" ]]; then
  echo "ePoxy subnet does not exist. Please deploy ePoxy before the cluster."
  exit 1
fi

if ! gsutil ls "gs://${!GCS_BUCKET_K8S}"; then
  echo "GCS bucket gs://${!GCS_BUCKET_K8S} does not exist. Please creat it."
  exit 1
fi


# DELETE ANY EXISTING GCP OBJECTS
#
# This script assumes you want to start totally fresh.

# Delete any existing forwarding rule for our external load balancer.
EXISTING_FWD=$(gcloud compute forwarding-rules list \
    --filter "name=${GCE_BASE_NAME} AND region:${GCE_REGION}" \
    --format "value(creationTimestamp)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_FWD}" ]]; then
  gcloud compute forwarding-rules delete "${GCE_BASE_NAME}" \
      --region "${GCE_REGION}" \
      "${GCP_ARGS[@]}"
fi

# Delete any existing target pool for the external load balancer.
EXISTING_TARGET_POOL=$(gcloud compute target-pools list \
    --filter "name=${GCE_BASE_NAME} AND region:${GCE_REGION}" \
    --format "value(creationTimestamp)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "$EXISTING_TARGET_POOL" ]]; then
  gcloud compute target-pools delete "${GCE_BASE_NAME}" \
      --region "${GCE_REGION}" \
      "${GCP_ARGS[@]}"
fi

# Delete any existing HTTP health checks for the external load balanced target
# pool.
EXISTING_HEALTH_CHECK=$(gcloud compute http-health-checks list \
    --filter "name=${GCE_BASE_NAME}" \
    --format "value(name)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_HEALTH_CHECK}" ]]; then
  gcloud compute http-health-checks delete "${GCE_BASE_NAME}" "${GCP_ARGS[@]}"
fi

EXISTING_EXTERNAL_FW=$(gcloud compute firewall-rules list \
    --filter "name=${GCE_BASE_NAME}-external" \
    --format "value(name)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_EXTERNAL_FW}" ]]; then
  gcloud compute firewall-rules delete "${GCE_BASE_NAME}-external" \
      "${GCP_ARGS[@]}"
fi

EXISTING_INTERNAL_FW=$(gcloud compute firewall-rules list \
    --filter "name=${GCE_BASE_NAME}-internal" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_INTERNAL_FW}" ]]; then
  gcloud compute firewall-rules delete "${GCE_BASE_NAME}-internal" \
      "${GCP_ARGS[@]}"
fi

EXISTING_HEALTH_CHECKS_FW=$(gcloud compute firewall-rules list \
    --filter "name=${GCE_BASE_NAME}-health-checks" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_HEALTH_CHECKS_FW}" ]]; then
  gcloud compute firewall-rules delete "${GCE_BASE_NAME}-health-checks" \
      "${GCP_ARGS[@]}"
fi

EXISTING_TOKEN_SERVER_FW=$(gcloud compute firewall-rules list \
    --filter "name=${GCE_BASE_NAME}-token-server" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_TOKEN_SERVER_FW}" ]]; then
  gcloud compute firewall-rules delete "${GCE_BASE_NAME}-token-server" \
      "${GCP_ARGS[@]}"
fi

EXISTING_BMC_STORE_PASSWORD_FW=$(gcloud compute firewall-rules list \
    --filter "name=${GCE_BASE_NAME}-bmc-store-password" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_BMC_STORE_PASSWORD_FW}" ]]; then
  gcloud compute firewall-rules delete "${GCE_BASE_NAME}-bmc-store-password" \
      "${GCP_ARGS[@]}"
fi

EXISTING_NDT_CLOUD_FW=$(gcloud compute firewall-rules list \
    --filter "name=${GCE_BASE_NAME}-ndt-cloud" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_NDT_CLOUD_FW}" ]]; then
  gcloud compute firewall-rules delete "${GCE_BASE_NAME}-ndt-cloud" \
      "${GCP_ARGS[@]}"
fi


# Delete any existing forwarding rule for the token-server ePoxy extension
# internal load balancer.
EXISTING_TOKEN_SERVER_INTERNAL_FWD=$(gcloud compute forwarding-rules list \
    --filter "name=${TOKEN_SERVER_BASE_NAME} AND region:${GCE_REGION}" \
    --format "value(name)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_TOKEN_SERVER_INTERNAL_FWD}" ]]; then
  gcloud compute forwarding-rules delete "${TOKEN_SERVER_BASE_NAME}" \
      --region "${GCE_REGION}" \
      "${GCP_ARGS[@]}"
fi

# Delete any existing backend service for the token-server ePoxy extension
# service.
EXISTING_TOKEN_SERVER_BACKEND_SERVICE=$(gcloud compute backend-services list \
    --filter "name=${TOKEN_SERVER_BASE_NAME} AND region:${GCE_REGION}" \
    --format "value(name)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_TOKEN_SERVER_BACKEND_SERVICE}" ]]; then
  gcloud compute backend-services delete "${TOKEN_SERVER_BASE_NAME}" \
      --region "${GCE_REGION}" \
      "${GCP_ARGS[@]}"
fi

# Delete any existing TCP health check for the token-server ePoxy extension
# service.
EXISTING_TOKEN_SERVER_HEALTH_CHECK=$(gcloud compute health-checks list \
    --filter "name=${TOKEN_SERVER_BASE_NAME}" \
    --format "value(name)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_TOKEN_SERVER_HEALTH_CHECK}" ]]; then
  gcloud compute health-checks delete "${TOKEN_SERVER_BASE_NAME}" "${GCP_ARGS[@]}"
fi

# Delete any existing load balancer IP for the token-server ePoxy extension
# service.
EXISTING_TOKEN_SERVER_INTERNAL_LB_IP=$(gcloud compute addresses list \
    --filter "name=${TOKEN_SERVER_BASE_NAME}-lb AND region:${GCE_REGION}" \
    --format "value(address)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_TOKEN_SERVER_INTERNAL_LB_IP}" ]]; then
  gcloud compute addresses delete "${TOKEN_SERVER_BASE_NAME}-lb" \
      --region "${GCE_REGION}" \
      "${GCP_ARGS[@]}"
fi

# Delete any existing forwarding rule for the bmc-store-password internal load
# balancer.
EXISTING_BMC_STORE_PASSWORD_INTERNAL_FWD=$(gcloud compute forwarding-rules list \
    --filter "name=${BMC_STORE_PASSWORD_BASE_NAME} AND region:${GCE_REGION}" \
    --format "value(name)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_BMC_STORE_PASSWORD_INTERNAL_FWD}" ]]; then
  gcloud compute forwarding-rules delete "${BMC_STORE_PASSWORD_BASE_NAME}" \
      --region "${GCE_REGION}" \
      "${GCP_ARGS[@]}"
fi

# Delete any existing backend service for the bmc-store-password ePoxy
# extension service.
EXISTING_BMC_STORE_PASSWORD_BACKEND_SERVICE=$(gcloud compute backend-services list \
    --filter "name=${BMC_STORE_PASSWORD_BASE_NAME} AND region:${GCE_REGION}" \
    --format "value(name)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_BMC_STORE_PASSWORD_BACKEND_SERVICE}" ]]; then
  gcloud compute backend-services delete "${BMC_STORE_PASSWORD_BASE_NAME}" \
      --region "${GCE_REGION}" \
      "${GCP_ARGS[@]}"
fi

# Delete any existing TCP health check for the bmc-store-password ePoxy
# extension service.
EXISTING_BMC_STORE_PASSWORD_HEALTH_CHECK=$(gcloud compute health-checks list \
    --filter "name=${BMC_STORE_PASSWORD_BASE_NAME}" \
    --format "value(name)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_BMC_STORE_PASSWORD_HEALTH_CHECK}" ]]; then
  gcloud compute health-checks delete "${BMC_STORE_PASSWORD_BASE_NAME}" "${GCP_ARGS[@]}"
fi

# Delete any existing load balancer IP for the bmc-store-password ePoxy
# extension service.
EXISTING_BMC_STORE_PASSWORD_INTERNAL_LB_IP=$(gcloud compute addresses list \
    --filter "name=${BMC_STORE_PASSWORD_BASE_NAME}-lb AND region:${GCE_REGION}" \
    --format "value(address)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_BMC_STORE_PASSWORD_INTERNAL_LB_IP}" ]]; then
  gcloud compute addresses delete "${BMC_STORE_PASSWORD_BASE_NAME}-lb" \
      --region "${GCE_REGION}" \
      "${GCP_ARGS[@]}"
fi

# Delete each GCE instance, along with any instance-groups it was a member of.
for zone in $GCE_ZONES; do
  gce_zone="${GCE_REGION}-${zone}"
  gce_name="master-${GCE_BASE_NAME}-${gce_zone}"
  GCE_ARGS=("--zone=${gce_zone}" "${GCP_ARGS[@]}")

  EXISTING_INSTANCE=$(gcloud compute instances list \
      --filter "name=${gce_name} AND zone:($gce_zone)" \
      --format "value(name)" \
      "${GCP_ARGS[@]}" || true)
  if [[ -n "${EXISTING_INSTANCE}" ]]; then
    gcloud compute instances delete "${gce_name}" "${GCE_ARGS[@]}"
  fi

  delete_instance_group "${gce_name}" "${gce_zone}"

  EXISTING_CLUSTER_NODES=$(gcloud compute instances list \
      --filter "name:${K8S_CLOUD_NODE_BASE_NAME} AND zone:($gce_zone)" \
      --format "value(name)" \
      "${GCP_ARGS[@]}" || true)
  if [[ -n "${EXISTING_CLUSTER_NODES}" ]]; then
    for node_name in ${EXISTING_CLUSTER_NODES}; do
      gcloud compute instances delete "${node_name}" "${GCE_ARGS[@]}"
    done
  fi
done

EXISTING_K8S_SUBNET=$(gcloud compute networks subnets list \
    --network "${GCE_NETWORK}" \
    --filter "name=${GCE_K8S_SUBNET}" \
    --format "value(name)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_K8S_SUBNET}" ]]; then
  gcloud compute networks subnets delete "${GCE_K8S_SUBNET}" \
      --region "${GCE_REGION}" \
      "${GCP_ARGS[@]}"
fi

# If $EXIT_AFTER_DELETE is set to "yes", then exit now.
if [[ "${EXIT_AFTER_DELETE}" == "yes" ]]; then
  echo "EXIT_AFTER_DELETE set to 'yes'. All GCP objects deleted. Exiting."
  exit 0
fi

#
# CREATE NEW CLUSTER
#

# CREATE THE K8S VPC SUBNETWORK
N=$( find_lowest_network_number )
gcloud compute networks subnets create "${GCE_K8S_SUBNET}" \
    --network "${GCE_NETWORK}" \
    --range "10.${N}.0.0/16" \
    --region "${GCE_REGION}" \
    "${GCP_ARGS[@]}"

# EXTERNAL LOAD BALANCER
#
# Create or determine a static IP for the external k8s api-server load balancer.
EXISTING_EXTERNAL_LB_IP=$(gcloud compute addresses list \
    --filter "name=${GCE_BASE_NAME}-lb AND region:${GCE_REGION}" \
    --format "value(address)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_EXTERNAL_LB_IP}" ]]; then
  EXTERNAL_LB_IP="${EXISTING_EXTERNAL_LB_IP}"
else
  gcloud compute addresses create "${GCE_BASE_NAME}-lb" \
      --region "${GCE_REGION}" \
      "${GCP_ARGS[@]}"
  EXTERNAL_LB_IP=$(gcloud compute addresses list \
      --filter "name=${GCE_BASE_NAME}-lb AND region:${GCE_REGION}" \
      --format "value(address)" \
      "${GCP_ARGS[@]}")
fi

# Check the value of the existing IP address associated with the external load
# balancer name. If it's the same as the current/existing IP, then leave DNS
# alone, else delete the existing DNS RR and create a new one.
API_DOMAIN_NAME="api-${GCE_BASE_NAME}"
EXISTING_EXTERNAL_LB_DNS_IP=$(gcloud dns record-sets list \
    --zone "${PROJECT}-measurementlab-net" \
    --name "${API_DOMAIN_NAME}.${PROJECT}.measurementlab.net." \
    --format "value(rrdatas[0])" \
    "${GCP_ARGS[@]}" || true)
if [[ -z "${EXISTING_EXTERNAL_LB_DNS_IP}" ]]; then
  # Add the record.
  gcloud dns record-sets transaction start \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction add \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${API_DOMAIN_NAME}.${PROJECT}.measurementlab.net." \
      --type A \
      --ttl 300 \
      "${EXTERNAL_LB_IP}" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction execute \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
elif [[ "${EXISTING_EXTERNAL_LB_DNS_IP}" != "${EXTERNAL_LB_IP}" ]]; then
  gcloud dns record-sets transaction start \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction remove \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${API_DOMAIN_NAME}.${PROJECT}.measurementlab.net." \
      --type A \
      --ttl 300 \
      "${EXISTING_EXTERNAL_LB_DNS_IP}" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction add \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${API_DOMAIN_NAME}.${PROJECT}.measurementlab.net." \
      --type A \
      --ttl 300 \
      "${EXTERNAL_LB_IP}" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction execute \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
fi

# Create the http-health-check for the nodes in the target pool.
gcloud compute http-health-checks create "${GCE_BASE_NAME}" \
    --port 8080 \
    --request-path "/healthz" \
    "${GCP_ARGS[@]}"

# Create the target pool for our load balancer.
gcloud compute target-pools create "${GCE_BASE_NAME}" \
    --region "${GCE_REGION}" \
    --http-health-check \
    "${GCE_BASE_NAME}" \
    "${GCP_ARGS[@]}"

# Create the forwarding rule using the target pool we just created.
gcloud compute forwarding-rules create "${GCE_BASE_NAME}" \
    --region "${GCE_REGION}" \
    --ports 6443 \
    --address "${GCE_BASE_NAME}-lb" \
    --target-pool "${GCE_BASE_NAME}" \
    "${GCP_ARGS[@]}"

# Create a firewall rule allowing external access to ports:
#   TCP 22: SSH
#   TCP 6443: k8s API server
#   UDP 8272: VXLAN (flannel)
gcloud compute firewall-rules create "${GCE_BASE_NAME}-external" \
    --network "${GCE_NETWORK}" \
    --action "allow" \
    --rules "tcp:22,tcp:6443,udp:8472" \
    --source-ranges "0.0.0.0/0" \
    "${GCP_ARGS[@]}"

# Create firewall rule allowing GCP health checks.
# https://cloud.google.com/load-balancing/docs/health-checks#firewall_rules
gcloud compute firewall-rules create "${GCE_BASE_NAME}-health-checks" \
    --network "${GCE_NETWORK}" \
    --action "allow" \
    --rules "all" \
    --source-ranges "35.191.0.0/16,130.211.0.0/22" \
    --target-tags "${GCE_BASE_NAME}" \
    "${GCP_ARGS[@]}"

# Determine the CIDR range of the epoxy subnet.
EPOXY_SUBNET=$(gcloud compute networks subnets list \
    --network "${GCE_NETWORK}" \
    --filter "name=${GCE_EPOXY_SUBNET} AND region:(${GCE_REGION})" \
    --format "value(ipCidrRange)" \
    "${GCP_ARGS[@]}")
if [[ -z "${EPOXY_SUBNET}" ]]; then
  echo "Could not determine the CIDR range for the ePoxy subnet."
  exit 1
fi

# Create firewall rule allowing the ePoxy server to communicate with the
# token-server extension
gcloud compute firewall-rules create "${GCE_BASE_NAME}-token-server" \
    --network "${GCE_NETWORK}" \
    --action "allow" \
    --rules "tcp:${TOKEN_SERVER_PORT}" \
    --source-ranges "${EPOXY_SUBNET}" \
    "${GCP_ARGS[@]}"

# Create firewall rule allowing the ePoxy server to communicate with the
# bmc-store-password extension.
gcloud compute firewall-rules create "${GCE_BASE_NAME}-bmc-store-password" \
    --network "${GCE_NETWORK}" \
    --action "allow" \
    --rules "tcp:${BMC_STORE_PASSWORD_PORT}" \
    --source-ranges "${EPOXY_SUBNET}" \
    "${GCP_ARGS[@]}"

# Create firewall rule allowing all access to ndt-cloud nodes.
gcloud compute firewall-rules create "${GCE_BASE_NAME}-ndt-cloud" \
    --network "${GCE_NETWORK}" \
    --action "allow" \
    --rules "all" \
    --target-tags "ndt-cloud" \
    "${GCP_ARGS[@]}"


#
# INTERNAL LOAD BALANCING for the token server.
#

# Create a static IP for the token server internal load balancer.
gcloud compute addresses create "${TOKEN_SERVER_BASE_NAME}-lb" \
    --region "${GCE_REGION}" \
    --subnet "${GCE_K8S_SUBNET}" \
    "${GCP_ARGS[@]}"
INTERNAL_TOKEN_SERVER_LB_IP=$(gcloud compute addresses list \
    --filter "name=${TOKEN_SERVER_BASE_NAME}-lb AND region:${GCE_REGION}" \
    --format "value(address)" \
    "${GCP_ARGS[@]}")

# Check the value of the existing IP address associated with the internal load
# balancer name. If it's the same as the current/existing IP, then leave DNS
# alone, else delete the existing DNS RR and create a new one.
TOKEN_SERVER_DOMAIN_NAME="token-server-${GCE_BASE_NAME}"
EXISTING_TOKEN_SERVER_INTERNAL_LB_DNS_IP=$(gcloud dns record-sets list \
    --zone "${PROJECT}-measurementlab-net" \
    --name "${TOKEN_SERVER_DOMAIN_NAME}.${PROJECT}.measurementlab.net." \
    --format "value(rrdatas[0])" \
    "${GCP_ARGS[@]}" || true)
if [[ -z "${EXISTING_TOKEN_SERVER_INTERNAL_LB_DNS_IP}" ]]; then
  # Add the record.
  gcloud dns record-sets transaction start \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction add \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${TOKEN_SERVER_DOMAIN_NAME}.${PROJECT}.measurementlab.net." \
      --type A \
      --ttl 300 \
      "${INTERNAL_TOKEN_SERVER_LB_IP}" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction execute \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
elif [[ "${EXISTING_TOKEN_SERVER_INTERNAL_LB_DNS_IP}" != "${INTERNAL_TOKEN_SERVER_LB_IP}" ]]; then
  gcloud dns record-sets transaction start \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction remove \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${TOKEN_SERVER_DOMAIN_NAME}.${PROJECT}.measurementlab.net." \
      --type A \
      --ttl 300 \
      "${EXISTING_TOKEN_SERVER_INTERNAL_LB_DNS_IP}" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction add \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${TOKEN_SERVER_DOMAIN_NAME}.${PROJECT}.measurementlab.net." \
      --type A \
      --ttl 300 \
      "${INTERNAL_TOKEN_SERVER_LB_IP}" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction execute \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
fi

# Create the TCP health check for the token-server backend service.
gcloud compute health-checks create tcp "${TOKEN_SERVER_BASE_NAME}" \
    --port "${TOKEN_SERVER_PORT}" \
    "${GCP_ARGS[@]}"

# Create the backend service.
gcloud compute backend-services create "${TOKEN_SERVER_BASE_NAME}" \
    --load-balancing-scheme internal \
    --region "${GCE_REGION}" \
    --health-checks "${TOKEN_SERVER_BASE_NAME}" \
    --protocol tcp \
    "${GCP_ARGS[@]}"

# Create the forwarding rule for the token-server load balancer.
gcloud compute forwarding-rules create "${TOKEN_SERVER_BASE_NAME}" \
    --load-balancing-scheme internal \
    --address "${INTERNAL_TOKEN_SERVER_LB_IP}" \
    --ports "${TOKEN_SERVER_PORT}" \
    --network "${GCE_NETWORK}" \
    --subnet "${GCE_K8S_SUBNET}" \
    --region "${GCE_REGION}" \
    --backend-service "${TOKEN_SERVER_BASE_NAME}" \
    "${GCP_ARGS[@]}"

#
# INTERNAL LOAD BALANCING for the bmc-store-password ePoxy extension.
#

# Create a static IP for the extension's internal load balancer.
gcloud compute addresses create "${BMC_STORE_PASSWORD_BASE_NAME}-lb" \
    --region "${GCE_REGION}" \
    --subnet "${GCE_K8S_SUBNET}" \
    "${GCP_ARGS[@]}"
INTERNAL_BMC_STORE_PASSWORD_LB_IP=$(gcloud compute addresses list \
    --filter "name=${BMC_STORE_PASSWORD_BASE_NAME}-lb AND region:${GCE_REGION}" \
    --format "value(address)" \
    "${GCP_ARGS[@]}")

# Check the value of the existing IP address associated with the internal load
# balancer name. If it's the same as the current/existing IP, then leave DNS
# alone, else delete the existing DNS RR and create a new one.
BMC_STORE_PASSWORD_DOMAIN_NAME="bmc-store-password-${GCE_BASE_NAME}"
EXISTING_BMC_STORE_PASSWORD_INTERNAL_LB_DNS_IP=$(gcloud dns record-sets list \
    --zone "${PROJECT}-measurementlab-net" \
    --name "${BMC_STORE_PASSWORD_DOMAIN_NAME}.${PROJECT}.measurementlab.net." \
    --format "value(rrdatas[0])" \
    "${GCP_ARGS[@]}" || true)
if [[ -z "${EXISTING_BMC_STORE_PASSWORD_INTERNAL_LB_DNS_IP}" ]]; then
  # Add the record.
  gcloud dns record-sets transaction start \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction add \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${BMC_STORE_PASSWORD_DOMAIN_NAME}.${PROJECT}.measurementlab.net." \
      --type A \
      --ttl 300 \
      "${INTERNAL_BMC_STORE_PASSWORD_LB_IP}" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction execute \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
elif [[ "${EXISTING_BMC_STORE_PASSWORD_INTERNAL_LB_DNS_IP}" != "${INTERNAL_BMC_STORE_PASSWORD_LB_IP}" ]]; then
  gcloud dns record-sets transaction start \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction remove \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${BMC_STORE_PASSWORD_DOMAIN_NAME}.${PROJECT}.measurementlab.net." \
      --type A \
      --ttl 300 \
      "${EXISTING_BMC_STORE_PASSWORD_INTERNAL_LB_DNS_IP}" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction add \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${BMC_STORE_PASSWORD_DOMAIN_NAME}.${PROJECT}.measurementlab.net." \
      --type A \
      --ttl 300 \
      "${INTERNAL_BMC_STORE_PASSWORD_LB_IP}" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction execute \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
fi

# Create the TCP health check for the bmc-store-password backend service.
gcloud compute health-checks create tcp "${BMC_STORE_PASSWORD_BASE_NAME}" \
    --port "${BMC_STORE_PASSWORD_PORT}" \
    "${GCP_ARGS[@]}"

# Create the backend service.
gcloud compute backend-services create "${BMC_STORE_PASSWORD_BASE_NAME}" \
    --load-balancing-scheme internal \
    --region "${GCE_REGION}" \
    --health-checks "${BMC_STORE_PASSWORD_BASE_NAME}" \
    --protocol tcp \
    "${GCP_ARGS[@]}"

# Create the forwarding rule for the bmc-store-password load balancer.
gcloud compute forwarding-rules create "${BMC_STORE_PASSWORD_BASE_NAME}" \
    --load-balancing-scheme internal \
    --address "${INTERNAL_BMC_STORE_PASSWORD_LB_IP}" \
    --ports "${BMC_STORE_PASSWORD_PORT}" \
    --network "${GCE_NETWORK}" \
    --subnet "${GCE_K8S_SUBNET}" \
    --region "${GCE_REGION}" \
    --backend-service "${BMC_STORE_PASSWORD_BASE_NAME}" \
    "${GCP_ARGS[@]}"

# Determine the internal CIDR of the k8s subnet.
INTERNAL_K8S_SUBNET=$(gcloud compute networks subnets describe ${GCE_K8S_SUBNET} \
    --region ${GCE_REGION} \
    --format "value(ipCidrRange)" \
    "${GCP_ARGS[@]}" || true)
if [[ -z "${INTERNAL_K8S_SUBNET}" ]]; then
  echo "Could not determine the CIDR range for the internal k8s subnet."
  exit 1
fi
# Set up a firewall rule allowing access to anything in the network from
# instances in the internal k8s-master subnet.
gcloud compute firewall-rules create ${GCE_BASE_NAME}-internal \
    --network "${GCE_NETWORK}" \
    --action "allow" \
    --rules "all" \
    --source-ranges "${INTERNAL_K8S_SUBNET}" \
    "${GCP_ARGS[@]}"

#
# Create one GCE instance for each of $GCE_ZONES defined.
#
ETCD_CLUSTER_STATE="new"

idx=0
for zone in $GCE_ZONES; do
  create_master $zone ${REBOOT_DAYS[$idx]}
  idx=$(( idx + 1 ))
done
