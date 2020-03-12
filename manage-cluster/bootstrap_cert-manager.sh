#!/bin/bash
#
# bootstrap_cert-manager.sh is a small script that will create the necessary
# GCP service account and IAM role binding to allow the cert-manager
# deployment to insert TXT records into our Cloud DNS zones for the purposes of
# validating ACME DNS01 verification for LetsEncrypt TLS certificates.

set -euxo pipefail

USAGE="$0 <cloud project>"
PROJECT=${1:?Please provide the cloud project: ${USAGE}}

# Source all of the global configuration variables.
source k8s_deploy.conf

GCS_BUCKET_K8S="GCS_BUCKET_K8S_${PROJECT//-/_}"

# Make sure that a service accounts exists for cert-manager. If it doesn't,
# then create it, generate a JSON key and upload it to GCS.
EXISTING_CERTMANAGER_SA=$(gcloud iam service-accounts list \
    --filter "name:${K8S_CERTMANAGER_DNS01_SA}" \
    --project "${PROJECT}" || true)
if [[ -z "${EXISTING_CERTMANAGER_SA}" ]]; then
  gcloud iam service-accounts create "${K8S_CERTMANAGER_DNS01_SA}" \
      --display-name "${K8S_CERTMANAGER_DNS01_SA}" \
      --project "${PROJECT}"
  gcloud iam service-accounts keys create "${K8S_CERTMANAGER_SA_KEY}" \
      --iam-account "${K8S_CERTMANAGER_DNS01_SA}@${PROJECT}.iam.gserviceaccount.com"
  gsutil cp "${K8S_CERTMANAGER_SA_KEY}" "gs://${!GCS_BUCKET_K8S}/${K8S_CERTMANAGER_SA_KEY}"
fi

EXISTING_DNS_ADMIN_ROLE_BINDING=$(gcloud projects get-iam-policy "${PROJECT}" \
    --flatten "bindings[].members" \
    --filter "bindings.members:serviceAccount:${K8S_CERTMANAGER_DNS01_SA} AND bindings.role=roles/dns.admin" \
    || true)
if [[ -z "${EXISTING_DNS_ADMIN_ROLE_BINDING}" ]]; then
  gcloud projects add-iam-policy-binding "${PROJECT}" \
      --member "serviceAccount:${K8S_CERTMANAGER_DNS01_SA}@${PROJECT}.iam.gserviceaccount.com" \
      --role roles/dns.admin
fi