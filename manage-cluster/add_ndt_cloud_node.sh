#!/bin/bash
#
# Creates a new ndt-cloud platform cluster node.
#
# NOTE: The argument <cloud-site> should be always end in the letter 'c'. For
# example: den0c, lol2c, etc.

set -euxo pipefail

USAGE="USAGE: $0 <cloud-project> <cloud-site>"
PROJECT=${1:? Please specify a GCP project: ${USAGE}}
CLOUD_SITE=${2:? Please specify a cloud site (ending in 'c'): ${USAGE}}
SITE_REGEX="[a-z]{3}[0-9]c"

# Don't proceed if the site name doesn't match a standard cloud site name.
if ! [[ "${CLOUD_SITE}" =~ $SITE_REGEX ]]; then
  echo "Cloud sites must match the regex [a-z]{3}[0-9]c."
  exit 1
fi

# Source all of the global configuration variables.
source k8s_deploy.conf

# Create a string representing region and zone variable names for this project.
GCE_REGION_VAR="GCE_REGION_${PROJECT//-/_}"
GCE_ZONES_VAR="GCE_ZONES_${PROJECT//-/_}"

# Dereference the region and zones variables.
GCE_REGION="${!GCE_REGION_VAR}"
GCE_ZONES="${!GCE_ZONES_VAR}"

# Grab the first zone in the list of GCE_ZONES.
GCE_ZONE="${GCE_REGION}-$(echo ${GCE_ZONES} | awk '{print $1}')"

GCP_ARGS=("--project=${PROJECT}" "--quiet")
GCE_ARGS=("--zone=${GCE_ZONE}" "${GCP_ARGS[@]}")

GCE_NAME="mlab1-${CLOUD_SITE}-measurement-lab-org"
K8S_NAME="mlab1.${CLOUD_SITE}.measurement-lab.org"

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

./add_k8s_cloud_node.sh -p "${PROJECT}" -n "${GCE_NAME}" -h "${K8S_NAME}" \
    -a "${GCE_NAME}" -t "ndt-cloud" \
    -l "mlab/type=cloud mlab/machine=mlab1 mlab/metro=${CLOUD_SITE::-2} mlab/site=${CLOUD_SITE} mlab/project=${PROJECT}"

