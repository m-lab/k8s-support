#!/bin/bash
#
# Creates a new ndt-cloud platform cluster node.
#
# NOTE: The argument <cloud-site> should be always end in the letter 'c'. For
# example: den0c, lol2c, etc.

set -euxo pipefail

USAGE="USAGE: $0 <cloud-project> <cloud-site> <gce-zone> [<machine-name>]"
PROJECT=${1:? Please specify a GCP project: ${USAGE}}
CLOUD_SITE=${2:? Please specify a cloud site name: ${USAGE}}
CLOUD_ZONE=${3:? Please specify the GCP zone for this VM: ${USAGE}}
MACHINE_NAME=${4:-""}

if [[ "${PROJECT}" == "mlab-sandbox" ]]; then
  SITE_REGEX="[a-z]{3}[0-9]t"
else
  SITE_REGEX="[a-z]{3}[0-9]{2}"
fi

# Source configuration variables and bootstrap functions.
source k8s_deploy.conf
source bootstraplib.sh

# Don't proceed if the site name doesn't match a standard cloud site name.
if ! [[ "${CLOUD_SITE}" =~ $SITE_REGEX ]]; then
  echo "Cloud sites for project ${PROJECT} must match the regex ${SITE_REGEX}."
  exit 1
fi

# Determine the region based on $CLOUD_ZONE.
GCE_REGION="${CLOUD_ZONE%-*}"
GCP_ARGS=("--project=${PROJECT}" "--quiet")

# If the user passed a MACHINE_NAME argument use that, else, by default, use
# "mlab4" for staging, and mlab1 for everything else.
if [[ -n "${MACHINE_NAME}" ]]; then
  if [[ "${MACHINE_NAME}" =~ ^mlab[1-4]$ ]]; then
    MLAB_MACHINE=$MACHINE_NAME
  else
    echo "Machine name ${MACHINE_NAME} does not match regexp /^mlab[1-4]$/"
    exit 1
  fi
elif [[ "${PROJECT}" == "mlab-staging" ]]; then
  MLAB_MACHINE="mlab4"
else
  MLAB_MACHINE="mlab1"
fi

GCE_NAME="${MLAB_MACHINE}-${CLOUD_SITE}-${PROJECT}-measurement-lab-org"
K8S_NAME="${MLAB_MACHINE}-${CLOUD_SITE}.${PROJECT}.measurement-lab.org"

# Create the static cloud public IP, if it doesn't already exist.
CURRENT_CLOUD_IP=$(gcloud compute addresses list \
    --filter "name=${GCE_NAME} AND region:${GCE_REGION}" \
    --format "value(address)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${CURRENT_CLOUD_IP}" ]]; then
  CLOUD_IP="${CURRENT_CLOUD_IP}"
else
  gcloud compute addresses create "${GCE_NAME}" \
      --region "${GCE_REGION}" \
      "${GCP_ARGS[@]}"
  CLOUD_IP=$(gcloud compute addresses list \
      --filter "name=${GCE_NAME} AND region:${GCE_REGION}" \
      --format "value(address)" \
      "${GCP_ARGS[@]}")
fi

# If a subnet for the region of this VM doesn't already exist, then create it.
EXISTING_SUBNET=$(gcloud compute networks subnets list \
    --filter "name=${GCE_K8S_SUBNET} AND region:( ${GCE_REGION} )" \
    --network "${GCE_NETWORK}" \
    --format "value(name)" \
    "${GCP_ARGS[@]}" || true)
if [[ -z "${EXISTING_SUBNET}" ]]; then
  N=$( find_lowest_network_number )
  gcloud compute networks subnets create "${GCE_K8S_SUBNET}" \
      --network "${GCE_NETWORK}" \
      --range "10.${N}.0.0/16" \
      --region "${GCE_REGION}" \
      --stack-type "IPV4_IPV6" \
      --ipv6-access-type "EXTERNAL" \
      "${GCP_ARGS[@]}"
fi

./add_k8s_virtual_node.sh -p "${PROJECT}" -z "${CLOUD_ZONE}" \
    -n "${GCE_NAME}" -H "${K8S_NAME}" -a "${GCE_NAME}" -t "ndt-cloud" \
    -l "mlab/type=virtual mlab/run=ndt mlab/machine=${MLAB_MACHINE} mlab/metro=${CLOUD_SITE::-2} mlab/site=${CLOUD_SITE} mlab/project=${PROJECT}"
