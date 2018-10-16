#!/bin/bash
#
# setup_cloud_k8s_master.sh sets up the master node in GCE for k8s in the cloud.
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

GCE_BASE_NAME="k8s-platform-master"
GCE_IMAGE_FAMILY="ubuntu-1804-lts"
GCE_IMAGE_PROJECT="ubuntu-os-cloud"
GCE_DISK_SIZE="100"
GCE_DISK_TYPE="pd-standard"
GCE_NETWORK="k8s-platform-master"
GCE_SUBNET="${GCE_NETWORK}"
GCE_NET_TAGS="k8s-platform-master" # Comma separate list
GCE_TYPE="n1-standard-4"

K8S_VERSION="1.12.0"
K8S_CA_FILES="ca.crt ca.key sa.key sa.pub front-proxy-ca.crt front-proxy-ca.key etcd/ca.crt etcd/ca.key"
K8S_PKI_DIR="/tmp/kubernetes-pki"
K8S_CLUSTER_CIDR="10.244.0.0/16"
K8S_SERVICE_CIDR="10.96.0.0/12"

TOKEN_SERVER_BASE_NAME="token-server"
TOKEN_SERVER_PORT="8800"

# Whether this script should exit after deleting all existing GCP resources
# associated with creating this k8s cluster. This could be useful, for example,
# if you want to change various object names, but don't want to have to
# manually hunt down all the old objects all over the GCP console. For
# example, many objects names are based on the variable $GCE_BASE_NAME. If you
# were to assign another value to that variable and run this script, any old,
# existing objects will not be removed, and will linger orphaned in the GCP
# project. One way to use this would be to set the following to "yes", run this
# script, _then_ change any base object names, reset this to "no" and run this
# script.
DELETE_ONLY="no"

# Depending on the GCP project we use different regions and zones.
case $PROJECT in
  mlab-sandbox)
    GCE_REGION="us-east1"
    GCE_ZONES="b c d"
    ;;
  mlab-staging)
    GCE_REGION="us-central1"
    GCE_ZONES="a b c"
    ;;
  mlab-oti)
    GCE_REGION="us-east4"
    GCE_ZONES="a b c"
    ;;
  *)
    echo "Unknown GCP project: ${PROJECT}."
    exit 1
esac

# NOTE: GCP currently only offers tcp/udp network load balacing on a regional level.
# If we want more redundancy than GCP zones offer, then we'll need to figure out
# some way to use a proxying load balancer.
#
# The external load balancer will always be located in the first specified zone.
EXTERNAL_LB_ZONE="${GCE_REGION}-$(echo ${GCE_ZONES} | awk '{print $1}')"

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

# Arrays of arguments are slightly cumbersome but using them ensures that if a
# space ever appears in an arg, then later usage of these values should not
# break in strange ways.
GCP_ARGS=("--project=${PROJECT}" "--quiet")

#
# DELETE ANY EXISTING OBJECTS
#
# This script assumes you want to start totally fresh.

# Delete any existing forwarding rule for our external load balancer.
EXISTING_FWD=$(gcloud compute forwarding-rules list \
    --filter "name=${GCE_BASE_NAME} AND region:${GCE_REGION}" \
    --format "value(creationTimestamp)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_FWD}" ]]; then
  gcloud compute forwarding-rules delete "${GCE_BASE_NAME}" \
      --region "${GCE_REGION}" "${GCP_ARGS[@]}"
fi

# Delete any existing target pool for the external load balancer.
EXISTING_TARGET_POOL=$(gcloud compute target-pools list \
    --filter "name=${GCE_BASE_NAME} AND region:${GCE_REGION}" \
    --format "value(creationTimestamp)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "$EXISTING_TARGET_POOL" ]]; then
  gcloud compute target-pools delete "${GCE_BASE_NAME}" \
      --region "${GCE_REGION}" "${GCP_ARGS[@]}"
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

# Delete any existing forwarding rule for the internal load balancer.
EXISTING_INTERNAL_FWD=$(gcloud compute forwarding-rules list \
    --filter "name=${TOKEN_SERVER_BASE_NAME} AND region:${GCE_REGION}" \
    --format "value(name)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_INTERNAL_FWD}" ]]; then
  gcloud compute forwarding-rules delete "${TOKEN_SERVER_BASE_NAME}" \
      --region "${GCE_REGION}" \
      "${GCP_ARGS[@]}"
fi

# Delete any existing backend service for the token-server.
EXISTING_BACKEND_SERVICE=$(gcloud compute backend-services list \
    --filter "name=${TOKEN_SERVER_BASE_NAME} AND region:${GCE_REGION}" \
    --format "value(name)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_BACKEND_SERVICE}" ]]; then
  gcloud compute backend-services delete "${TOKEN_SERVER_BASE_NAME}" \
      --region "${GCE_REGION}" \
      "${GCP_ARGS[@]}"
fi

# Delete any existing  TCP health check for the token-server service.
EXISTING_TOKEN_HEALTH_CHECK=$(gcloud compute health-checks list \
    --filter "name=${TOKEN_SERVER_BASE_NAME}" \
    --format "value(name)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_TOKEN_HEALTH_CHECK}" ]]; then
  gcloud compute health-checks delete "${TOKEN_SERVER_BASE_NAME}" "${GCP_ARGS[@]}"
fi

# Delete each GCE instance, along with any instance-groups it was a member of.
for zone in $GCE_ZONES; do
  gce_zone="${GCE_REGION}-${zone}"
  gce_name="${GCE_BASE_NAME}-${gce_zone}"
  GCE_ARGS=("--zone=${gce_zone}" "${GCP_ARGS[@]}")

  EXISTING_INSTANCE=$(gcloud compute instances list \
      --filter "name=${gce_name} AND zone:${gce_zone}" \
      --format "value(name)" \
      "${GCP_ARGS[@]}" || true)
  if [[ -n "${EXISTING_INSTANCE}" ]]; then
    gcloud compute instances delete "${gce_name}" "${GCE_ARGS[@]}"
  fi

  EXISTING_INSTANCE_GROUP=$(gcloud compute instance-groups list \
      --filter "name=${gce_name} AND zone:${gce_zone}" \
      --format "value(name)" \
      "${GCP_ARGS[@]}" || true)
  if [[ -n "${EXISTING_INSTANCE_GROUP}" ]]; then
    gcloud compute instance-groups unmanaged delete "${gce_name}" \
        --zone "${gce_zone}" \
        "${GCP_ARGS[@]}"
  fi
done

# If $DELETE_ONLY is set to "yes", then exit now.
if [[ "${DELETE_ONLY}" == "yes" ]]; then
  echo "DELETE_ONLY set to 'yes'. All GCP objects deleted. Exiting."
  exit 0
fi

#
# CREATE NEW CLUSTER
#

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
EXISTING_EXTERNAL_LB_DNS_IP=$(gcloud dns record-sets list \
    --zone "${PROJECT}-measurementlab-net" \
    --name "${GCE_BASE_NAME}.${PROJECT}.measurementlab.net." \
    --format "value(rrdatas[0])" \
    "${GCP_ARGS[@]}" || true)
if [[ -z "${EXISTING_EXTERNAL_LB_DNS_IP}" ]]; then
  # Add the record.
  gcloud dns record-sets transaction start \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction add \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${GCE_BASE_NAME}.${PROJECT}.measurementlab.net." \
      --type A \
      --ttl 300 \
      "${EXTERNAL_IP}" \
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
      --name "${GCE_BASE_NAME}.${PROJECT}.measurementlab.net." \
      --type A \
      --ttl 300 \
      "${EXISTING_EXTERNAL_LB_DNS_IP}" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction add \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${GCE_BASE_NAME}.${PROJECT}.measurementlab.net." \
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
    --network "${GCE_BASE_NAME}" \
    --action "allow" \
    --rules "tcp:22,tcp:6443;udp:8472" \
    --source-ranges "0.0.0.0/0" \
    "${GCP_ARGS[@]}"

#
# INTERNAL LOAD BALANCING for the token server.
#

# Create a static IP for the GCE instance, or use the one that already exists.
EXISTING_INTERNAL_LB_IP=$(gcloud compute addresses list \
    --filter "name=${TOKEN_SERVER_BASE_NAME}-lb AND region:${GCE_REGION}" \
    --format "value(address)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_INTERNAL_LB_IP}" ]]; then
  INTERNAL_LB_IP="${EXISTING_INTERNAL_LB_IP}"
else
  gcloud compute addresses create "${TOKEN_SERVER_BASE_NAME}-lb" \
      --region "${GCE_REGION}" \
      --subnet "${GCE_SUBNET}" \
      "${GCP_ARGS[@]}"
  INTERNAL_LB_IP=$(gcloud compute addresses list \
      --filter "name=${TOKEN_SERVER_BASE_NAME}-lb AND region:${GCE_REGION}" \
      --format "value(address)" \
      "${GCP_ARGS[@]}")
fi

# Check the value of the existing IP address associated with the internal load
# balancer name. If it's the same as the current/existing IP, then leave DNS
# alone, else delete the existing DNS RR and create a new one.
EXISTING_INTERNAL_LB_DNS_IP=$(gcloud dns record-sets list \
    --zone "${PROJECT}-measurementlab-net" \
    --name "${TOKEN_SERVER_BASE_NAME}.${PROJECT}.measurementlab.net." \
    --format "value(rrdatas[0])" \
    "${GCP_ARGS[@]}" || true)
if [[ -z "${EXISTING_INTERNAL_LB_DNS_IP}" ]]; then
  # Add the record.
  gcloud dns record-sets transaction start \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction add \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${TOKEN_SERVER_BASE_NAME}.${PROJECT}.measurementlab.net." \
      --type A \
      --ttl 300 \
      "${INTERNAL_LB_IP}" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction execute \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
elif [[ "${EXISTING_INTERNAL_LB_DNS_IP}" != "${INTERNAL_LB_IP}" ]]; then
  gcloud dns record-sets transaction start \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction remove \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${TOKEN_SERVER_BASE_NAME}.${PROJECT}.measurementlab.net." \
      --type A \
      --ttl 300 \
      "${EXISTING_INTERNAL_LB_DNS_IP}" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction add \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${TOKEN_SERVER_BASE_NAME}.${PROJECT}.measurementlab.net." \
      --type A \
      --ttl 300 \
      "${INTERNAL_LB_IP}" \
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
    --address "${INTERNAL_LB_IP}" \
    --ports "${TOKEN_SERVER_PORT}" \
    --network "${GCE_NETWORK}" \
    --region "${GCE_REGION}" \
    --backend-service "${TOKEN_SERVER_BASE_NAME}" \
    "${GCP_ARGS[@]}"

# Create a firewall rule allowing access to anything from internal sources
# from the subnet.
INTERNAL_SUBNET=$(gcloud compute networks subnets describe ${GCE_BASE_NAME} \
    --region ${GCE_REGION} \
    --format "value(ipCidrRange)" \
    "${GCP_ARGS[@]}" || true)
if [[ -z "${INTERNAL_SUBNET}" ]]; then
  echo "Could not determine the CIDR range for the internal subnet."
  exit 1
fi

EXISTING_INTERNAL_FW=$(gcloud compute firewall-rules list \
    --filter "name=${GCE_BASE_NAME}-internal" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_INTERNAL_FW}" ]]; then
  gcloud compute firewall-rules delete "${GCE_BASE_NAME}-internal" \
      "${GCP_ARGS[@]}"
fi
gcloud compute firewall-rules create ${GCE_BASE_NAME}-internal \
    --network "${GCE_BASE_NAME}" \
    --action "allow" \
    --rules "all" \
    --source-ranges "${INTERNAL_SUBNET}" \
    "${GCP_ARGS[@]}"

# Create one GCE instance for each of $GCE_ZONES defined.
#
ETCD_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER=""
FIRST_INSTANCE_NAME=""
FIRST_INSTANCE_IP=""

for zone in $GCE_ZONES; do

  gce_zone="${GCE_REGION}-${zone}"
  gce_name="${GCE_BASE_NAME}-${gce_zone}"

  GCE_ARGS=("--zone=${gce_zone}" "${GCP_ARGS[@]}")

  # Create a static IP for the GCE instance, or use the one that already exists.
  EXISTING_IP=$(gcloud compute addresses list \
      --filter "name=${gce_name} AND region:${GCE_REGION}" \
      --format "value(address)" \
      "${GCP_ARGS[@]}" || true)
  if [[ -n "${EXISTING_IP}" ]]; then
    EXTERNAL_IP="${EXISTING_IP}"
  else
    gcloud compute addresses create "${gce_name}" \
        --region "${GCE_REGION}" \
        "${GCP_ARGS[@]}"
    EXTERNAL_IP=$(gcloud compute addresses list \
        --filter "name=${gce_name} AND region:${GCE_REGION}" \
        --format "value(address)" \
        "${GCP_ARGS[@]}")
  fi

  # Check the value of the existing IP address in DNS associated with this GCE
  # instance. If it's the same as the current/existing IP, then leave DNS alone,
  # else delete the existing DNS RR and create a new one.
  EXISTING_DNS_IP=$(gcloud dns record-sets list \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${gce_name}.${PROJECT}.measurementlab.net." \
      --format "value(rrdatas[0])" \
      "${GCP_ARGS[@]}" || true)
  if [[ -z "${EXISTING_DNS_IP}" ]]; then
    # Add the record.
    gcloud dns record-sets transaction start \
        --zone "${PROJECT}-measurementlab-net" \
        "${GCP_ARGS[@]}"
    gcloud dns record-sets transaction add \
        --zone "${PROJECT}-measurementlab-net" \
        --name "${gce_name}.${PROJECT}.measurementlab.net." \
        --type A \
        --ttl 300 \
        "${EXTERNAL_IP}" \
        "${GCP_ARGS[@]}"
    gcloud dns record-sets transaction execute \
        --zone "${PROJECT}-measurementlab-net" \
        "${GCP_ARGS[@]}"
  elif [[ "${EXISTING_DNS_IP}" != "${EXTERNAL_IP}" ]]; then
    # Add the record, deleting the existing one first.
    gcloud dns record-sets transaction start \
        --zone "${PROJECT}-measurementlab-net" \
        "${GCP_ARGS[@]}"
    gcloud dns record-sets transaction remove \
        --zone "${PROJECT}-measurementlab-net" \
        --name "${gce_name}.${PROJECT}.measurementlab.net." \
        --type A \
        --ttl 300 \
        "${EXISTING_DNS_IP}" \
        "${GCP_ARGS[@]}"
    gcloud dns record-sets transaction add \
        --zone "${PROJECT}-measurementlab-net" \
        --name "${gce_name}.${PROJECT}.measurementlab.net." \
        --type A \
        --ttl 300 \
        "${EXTERNAL_IP}" \
        "${GCP_ARGS[@]}"
    gcloud dns record-sets transaction execute \
        --zone "${PROJECT}-measurementlab-net" \
        "${GCP_ARGS[@]}"
  fi

  # Create the GCE instance.
  #
  # TODO (kinkade): In its current form, the service account associated with
  # this GCE instance needs full access to a single GCS storage bucket for the
  # purposes of moving around CA cert files, etc. Currently the instance is
  # granted the "storage-full" scope, which is far more permissive than we
  # ultimately want.
  gcloud compute instances create "${gce_name}" \
    --image-family "${GCE_IMAGE_FAMILY}" \
    --image-project "${GCE_IMAGE_PROJECT}" \
    --boot-disk-size "${GCE_DISK_SIZE}" \
    --boot-disk-type "${GCE_DISK_TYPE}" \
    --boot-disk-device-name "${gce_name}"  \
    --network "${GCE_NETWORK}" \
    --tags "${GCE_NET_TAGS}" \
    --machine-type "${GCE_TYPE}" \
    --address "${EXTERNAL_IP}" \
    --scopes "storage-full" \
    "${GCE_ARGS[@]}"

  #  Give the instance time to appear.  Make sure it appears twice - there have
  #  been multiple instances of it connecting just once and then failing again for
  #  a bit.
  until gcloud compute ssh "${gce_name}" --command true "${GCE_ARGS[@]}" && \
        sleep 10 && \
        gcloud compute ssh "${gce_name}" --command true "${GCE_ARGS[@]}"; do
    echo Waiting for "${gce_name}" to boot up.
    # Refresh keys in case they changed mid-boot. They change as part of the
    # GCE bootup process, and it is possible to ssh at the precise moment a
    # temporary key works, get that key put in your permanent storage, and have
    # all future communications register as a MITM attack.
    #
    # Same root cause as the need to ssh twice in the loop condition above.
    gcloud compute config-ssh "${GCP_ARGS[@]}"
  done

  # Get the instances internal IP address.
  INTERNAL_IP=$(gcloud compute instances list \
      --filter "name=${gce_name} AND zone:${gce_zone}" \
      --format "value(networkInterfaces[0].networkIP)" \
      "${GCP_ARGS[@]}" || true)

  # If this is the first instance being created, it must be added to the target
  # pool now, else creating the initial cluster will fail. Subsequent instances
  # will be added later in this process.
  if [[ "${ETCD_CLUSTER_STATE}" == "new" ]]; then
    gcloud compute target-pools add-instances "${GCE_BASE_NAME}" \
        --instances "${gce_name}" \
        --instances-zone "${gce_zone}" \
        "${GCP_ARGS[@]}"
  fi

  # Create an instance group for our internal load balancer, add this GCE
  # instance to the group, then attach the instance group to our backend
  # service.
  gcloud compute instance-groups unmanaged create "${gce_name}" \
      --zone "${gce_zone}" \
      "${GCP_ARGS[@]}"
  gcloud compute instance-groups unmanaged add-instances "${gce_name}" \
      --instances "${gce_name}" \
      --zone "${gce_zone}" \
      "${GCP_ARGS[@]}"
  gcloud compute backend-services add-backend "${TOKEN_SERVER_BASE_NAME}" \
      --instance-group "${gce_name}" \
      --instance-group-zone "${gce_zone}" \
      --region "${GCE_REGION}" \
      "${GCP_ARGS[@]}"

  # We need to record the name and IP of the first instance we instantiate
  # because its name and IP will be needed when joining later instances to the
  # cluster.
  if [[ "${ETCD_CLUSTER_STATE}" == "new" ]]; then
    FIRST_INSTANCE_NAME="${gce_name}"
    FIRST_INSTANCE_IP="${INTERNAL_IP}"
  fi

  # Become root and install everything.
  #
  # Eventually we want this to work on Container Linux as the master. However, it
  # is too hard to hack on for a place in which to build an alpha system.  The
  # below commands work on Ubuntu.
  #
  # Some of the following is derived from the "Ubuntu" instructions at
  #   https://kubernetes.io/docs/setup/independent/install-kubeadm/
  gcloud compute ssh "${GCE_ARGS[@]}" "${gce_name}" <<-EOF
    sudo -s
    set -euxo pipefail
    apt-get update
    apt-get install -y docker.io
    systemctl enable docker.service

    apt-get update && apt-get install -y apt-transport-https curl
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    echo deb http://apt.kubernetes.io/ kubernetes-xenial main >/etc/apt/sources.list.d/kubernetes.list
    apt-get update
    apt-get install -y kubelet=${K8S_VERSION}-00 kubeadm=${K8S_VERSION}-00 kubectl=${K8S_VERSION}-00 etcd-client

    # Run the k8s-token-server (supporting the ePoxy Extension API), such that:
    #
    #   1) the host root (/) is mounted read-only in the container as /ro
    #   2) the host etc (/etc) is mounted read-only as the container's /etc
    #
    # The first gives access the kubeadm command.
    # The second gives kubeadm read access to /etc/kubernetes/admin.conf.
    docker run --detach --publish 8800:8800 \
        --volume /etc:/etc:ro \
        --volume /:/ro:ro \
        --restart always \
        --name token-server \
        measurementlab/k8s-token-server:v0.0 -command /ro/usr/bin/kubeadm

    # See the README in this directory for information on this container and why
    # we use it.
    docker run --detach --publish 8080:8080 --network host --restart always \
        --name exechealthz -- \
        measurementlab/exechealthz-stretch:v1.2 \
          -port 8080 -period 3s -latency 2s \
          -cmd "wget -O- --no-check-certificate https://localhost:6443/healthz"

    # Create a suitable cloud-config file for the cloud provider.
    echo -e "[Global]\nproject-id = ${PROJECT}\n" > /etc/kubernetes/cloud.conf

    # Sets the kublet's cloud provider config to gce and points to a suitable config file.
    sed -i '/KUBELET_KUBECONFIG_ARGS=/ \
        s|"$| --cloud-provider=gce --cloud-config=/etc/kubernetes/cloud.conf"|' \
        /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

    # We have run up against "no space left on device" errors, when clearly
    # there is plenty of free disk space. It seems this could likely be related
    # to this:
    # https://github.com/kubernetes/kubernetes/issues/7815#issuecomment-124566117
    # To be sure we don't hit the limit of fs.inotify.max_user_watches, increase
    # it from the default of 8192.
    echo fs.inotify.max_user_watches=131072 >> /etc/sysctl.conf
    sysctl -p

    systemctl daemon-reload
    systemctl restart kubelet
EOF

  # Setup GCSFUSE, then mount the repository's GCS bucket so we can read and/or
  # write the generated CA files to it to persist them in the event we need to
  # recreate a k8s master.
  gcloud compute ssh "${GCE_ARGS[@]}" "${gce_name}" <<EOF
    sudo -s
    set -euxo pipefail

    export GCSFUSE_REPO=gcsfuse-\$(lsb_release -c -s)
    echo "deb http://packages.cloud.google.com/apt \$GCSFUSE_REPO main" \
      | tee /etc/apt/sources.list.d/gcsfuse.list
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg \
      | apt-key add -

    # Install the gcsfuse package.
    apt-get update
    apt-get install gcsfuse

    # Create the directory where the project's GCS bucket will be mounted, and
    # mount it.
    mkdir -p ${K8S_PKI_DIR}
    echo "k8s-platform-master-${PROJECT} ${K8S_PKI_DIR} gcsfuse rw,user,allow_other,implicit_dirs" >> /etc/fstab
    mount ${K8S_PKI_DIR}

    # Make sure that the necessary subdirectories exist. Separated into two
    # steps due to limitations of gcsfuse.
    # https://github.com/GoogleCloudPlatform/gcsfuse/blob/master/docs/semantics.md#implicit-directories
    mkdir -p ${K8S_PKI_DIR}/pki/
    mkdir -p ${K8S_PKI_DIR}/pki/etcd/

    # If there are any files in the bucket's pki directory, copy them to
    # /etc/kubernetes/pki, creating that directory first, if it didn't already
    # exist.
    mkdir -p /etc/kubernetes/pki
    cp -a ${K8S_PKI_DIR}/pki/* /etc/kubernetes/pki

    # Copy the admin KUBECONFIG file from the bucket, if it exists.
    cp ${K8S_PKI_DIR}/admin.conf /etc/kubernetes/ 2> /dev/null || true
EOF

  # Copy the kubeadm config template to the server.
  gcloud compute scp kubeadm-config.yml.template "${gce_name}": "${GCE_ARGS[@]}"

  # The etcd config 'initial-cluster:' is additive as we continue to add new
  # instances to the cluster.
  if [[ "${ETCD_CLUSTER_STATE}" == "new" ]]; then
    ETCD_INITIAL_CLUSTER="${gce_name}=https://${INTERNAL_IP}:2380"
  else
    ETCD_INITIAL_CLUSTER="${ETCD_INITIAL_CLUSTER},${gce_name}=https://${INTERNAL_IP}:2380"
  fi

  # Many of the following configurations were gleaned from:
  # https://kubernetes.io/docs/setup/independent/high-availability/

  # Evaluate the kubeadm config template with a beastly sed statement.
  gcloud compute ssh "${gce_name}" "${GCE_ARGS[@]}" <<EOF
    # Create the kubeadm config from the template
    sed -e 's|{{PROJECT}}|${PROJECT}|g' \
        -e 's|{{INTERNAL_IP}}|${INTERNAL_IP}|g' \
        -e 's|{{EXTERNAL_IP}}|${EXTERNAL_IP}|g' \
        -e 's|{{MASTER_NAME}}|${gce_name}|g' \
        -e 's|{{LOAD_BALANCER_NAME}}|${GCE_BASE_NAME}|g' \
        -e 's|{{ETCD_CLUSTER_STATE}}|${ETCD_CLUSTER_STATE}|g' \
        -e 's|{{ETCD_INITIAL_CLUSTER}}|${ETCD_INITIAL_CLUSTER}|g' \
        -e 's|{{K8S_VERSION}}|${K8S_VERSION}|g' \
        -e 's|{{K8S_CLUSTER_CIDR}}|${K8S_CLUSTER_CIDR}|g' \
        -e 's|{{K8S_SERVICE_CIDR}}|${K8S_SERVICE_CIDR}|g' \
        ./kubeadm-config.yml.template > \
        ./kubeadm-config.yml
EOF

  if [[ "${ETCD_CLUSTER_STATE}" == "new" ]]; then
    gcloud compute ssh "${gce_name}" "${GCE_ARGS[@]}" <<EOF
      sudo -s
      set -euxo pipefail

      kubeadm init --config kubeadm-config.yml

      # Copy the admin KUBECONFIG file to the GCS bucket.
      cp /etc/kubernetes/admin.conf ${K8S_PKI_DIR}

      # Since we don't know which of the CA files already existed the GCS bucket
      # before creating this first instance (ETCD_CLUSTER_STATE=new), just copy
      # them all back. If they already existed it will be a no-op, and if they
      # didn't then they will now be persisted.
      for f in ${K8S_CA_FILES}; do
        cp /etc/kubernetes/pki/\${f} ${K8S_PKI_DIR}/pki/\${f}
      done
EOF
  else
    gcloud compute ssh "${gce_name}" "${GCE_ARGS[@]}" <<EOF
      sudo -s
      set -euxo pipefail

      # Bootstrap the kubelet
      kubeadm alpha phase certs all --config kubeadm-config.yml
      kubeadm alpha phase kubelet config write-to-disk --config kubeadm-config.yml
      kubeadm alpha phase kubelet write-env-file --config kubeadm-config.yml
      kubeadm alpha phase kubeconfig kubelet --config kubeadm-config.yml
      systemctl start kubelet

      # Add the instance to the etcd cluster
      export KUBECONFIG=/etc/kubernetes/admin.conf
      kubectl exec -n kube-system etcd-${FIRST_INSTANCE_NAME} -- etcdctl \
          --ca-file /etc/kubernetes/pki/etcd/ca.crt \
          --cert-file /etc/kubernetes/pki/etcd/peer.crt \
          --key-file /etc/kubernetes/pki/etcd/peer.key \
          --endpoints=https://${FIRST_INSTANCE_IP}:2379 \
          member add ${gce_name} https://${INTERNAL_IP}:2380
      kubeadm alpha phase etcd local --config kubeadm-config.yml

      # Deploy the control plane components and mark the node as a master
      kubeadm alpha phase kubeconfig all --config kubeadm-config.yml
      kubeadm alpha phase controlplane all --config kubeadm-config.yml
      kubeadm alpha phase mark-master --config kubeadm-config.yml
EOF
  fi

  # Allow the user who installed k8s on the master to call kubectl.  As we
  # productionize this process, this code should be deleted.
  # For the next steps, we no longer want to be root.
  gcloud compute ssh "${gce_name}" "${GCE_ARGS[@]}" <<-\EOF
    set -x
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    # Allow root to run kubectl also.
    sudo mkdir -p /root/.kube
    sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config
    sudo chown $(id -u):$(id -g) /root/.kube/config
EOF

  if [[ "${ETCD_CLUSTER_STATE}" == "new" ]]; then
    # Update the node setup script with the current CA certificate hash.
    #
    # https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-join/#token-based-discovery-with-ca-pinning
    ca_cert_hash=$(gcloud compute ssh "${gce_name}" "${GCE_ARGS[@]}" \
        --command "openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
                   openssl rsa -pubin -outform der 2>/dev/null | \
                   openssl dgst -sha256 -hex | sed 's/^.* //'")
    sed -e "s/{{CA_CERT_HASH}}/${ca_cert_hash}/" ../node/setup_k8s.sh.template > setup_k8s.sh
    gsutil cp setup_k8s.sh gs://epoxy-${PROJECT}/stage3_coreos/setup_k8s.sh
  fi

  # Evaluate the common.yml.template network config template file.
  sed -e "s|{{K8S_CLUSTER_CIDR}}|${K8S_CLUSTER_CIDR}|g" \
      ./network/common.yml.template > ./network/common.yml

  # Copy the network configs to the server.
  gcloud compute scp --recurse network "${gce_name}":network "${GCE_ARGS[@]}"

  # This test pod is for dev convenience.
  # TODO: delete this once index2ip works well.
  gcloud compute scp "${GCE_ARGS[@]}" test-pod.yml "${gce_name}":.

  # Now that kubernetes is started up, set up the network configs.
  # The CustomResourceDefinition needs to be defined before any resources which
  # use that definition, so we apply that config first.
  gcloud compute ssh "${gce_name}" "${GCE_ARGS[@]}" <<-EOF
    sudo -s
    set -euxo pipefail
    kubectl annotate node ${gce_name} flannel.alpha.coreos.com/public-ip-overwrite=${EXTERNAL_IP}
    kubectl label node ${gce_name} mlab/type=cloud
    kubectl apply -f network/crd.yml
    kubectl apply -f network

    # Work around a known issue with --cloud-provider=gce and CNI plugins.
    # https://github.com/kubernetes/kubernetes/issues/44254
    kubectl proxy --port 8888 &
    curl http://localhost:8888/api/v1/nodes/${gce_name}/status > a.json
    cat a.json | tr -d '\n' | sed 's/{[^}]\+NetworkUnavailable[^}]\+}/{"type": "NetworkUnavailable","status": "False","reason": "RouteCreated","message": "Manually set through k8s API."}/g' > b.json
    curl -X PUT http://localhost:8888/api/v1/nodes/${gce_name}/status -H "Content-Type: application/json" -d @b.json
    kill %1
EOF

  # Now that the instance should be functional, add it to our load balancer target pool.
  if [[ "${ETCD_CLUSTER_STATE}" == "existing" ]]; then
    gcloud compute target-pools add-instances "${GCE_BASE_NAME}" \
        --instances "${gce_name}" \
        --instances-zone "${gce_zone}" \
        "${GCP_ARGS[@]}"
  fi

  # After the first iteration of this loop, the cluster state becomes "existing"
  # for all other iterations, since the first iteration bootstraps the cluster,
  # while subsequent ones expand the existing cluster.
  ETCD_CLUSTER_STATE="existing"

done
