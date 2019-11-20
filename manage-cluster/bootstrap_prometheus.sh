#!/bin/bash
#
# bootstrap_prometheus.sh is a companion to bootstrap_k8s_master_cluster.sh and
# k8s/daemonsets/core/prometheus.yml config that creates additional GCP objects
# for a public load balancer with "CLIENT_IP" session affinity and persistent
# storage.
#
# USAGE:
#
#  * Run bootstrap_k8s_master_cluster.sh
#  * Run bootstrap_prometheus.sh
#  * Apply k8s/deployment/prometheus.yml


set -euxo pipefail

USAGE="$0 <cloud project>"
PROJECT=${1:?Please provide the cloud project: ${USAGE}}

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

# The type of GCE VM which will be deployed.
case $PROJECT in
  mlab-sandbox)
    MACHINE_TYPE="n1-standard-2";;
  mlab-staging)
    MACHINE_TYPE="n1-standard-8";;
  mlab-oti)
    MACHINE_TYPE="n1-highmem-16";;
  *)
    echo "Unknown GCP project: ${PROJECT}"
    exit 1
esac

# Prometheus public IP
CURRENT_PROMETHEUS_IP=$(gcloud compute addresses list \
    --filter "name=${PROM_BASE_NAME} AND region:${GCE_REGION}" \
    --format "value(address)" \
    "${GCP_ARGS[@]}" || true)
if [[ -n "${CURRENT_PROMETHEUS_IP}" ]]; then
  PROMETHEUS_IP="${CURRENT_PROMETHEUS_IP}"
else
  gcloud compute addresses create "${PROM_BASE_NAME}" \
      --region "${GCE_REGION}" \
      "${GCP_ARGS[@]}"
  PROMETHEUS_IP=$(gcloud compute addresses list \
      --filter "name=${PROM_BASE_NAME} AND region:${GCE_REGION}" \
      --format "value(address)" \
      "${GCP_ARGS[@]}")
fi

# Check the value of the existing IP address associated with Prometheus. If
# it's the same as the current/existing IP, then leave DNS
# alone, else delete the existing DNS RR and create a new one.
CURRENT_PROMETHEUS_DNS_IP=$(gcloud dns record-sets list \
    --zone "${PROJECT}-measurementlab-net" \
    --name "${PROM_BASE_NAME}.${PROJECT}.measurementlab.net." \
    --format "value(rrdatas[0])" \
    "${GCP_ARGS[@]}" || true)
if [[ -z "${CURRENT_PROMETHEUS_DNS_IP}" ]]; then
  # Add the record.
  gcloud dns record-sets transaction start \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction add \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${PROM_BASE_NAME}.${PROJECT}.measurementlab.net." \
      --type A \
      --ttl 300 \
      "${PROMETHEUS_IP}" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction execute \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"

elif [[ "${CURRENT_PROMETHEUS_DNS_IP}" != "${PROMETHEUS_IP}" ]]; then
  # Update the record.
  gcloud dns record-sets transaction start \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction remove \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${PROM_BASE_NAME}.${PROJECT}.measurementlab.net." \
      --type A \
      --ttl 300 \
      "${CURRENT_PROMETHEUS_DNS_IP}" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction add \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${PROM_BASE_NAME}.${PROJECT}.measurementlab.net." \
      --type A \
      --ttl 300 \
      "${PROMETHEUS_IP}" \
      "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction execute \
      --zone "${PROJECT}-measurementlab-net" \
      "${GCP_ARGS[@]}"
fi

#######################################################
# DELETE THINGS
#######################################################
# Delete in the reverse order of creation.

# firewall
gcloud compute firewall-rules delete "${PROM_BASE_NAME}-external" \
    "${GCP_ARGS[@]}" || :

gcloud compute instances delete "${PROM_BASE_NAME}" \
    "${GCE_ARGS[@]}" || :

# If $EXIT_AFTER_DELETE is set to "yes", then exit now.
if [[ "${EXIT_AFTER_DELETE}" == "yes" ]]; then
  echo "EXIT_AFTER_DELETE set to 'yes'. All GCP objects deleted. Exiting."
  exit 0
fi

#######################################################
# CREATE THINGS
#######################################################

# Create the new node
./add_k8s_cloud_node.sh -p "${PROJECT}" \
    -m "${MACHINE_TYPE}" \
    -n "${PROM_BASE_NAME}" \
    -a "${PROM_BASE_NAME}" \
    -l "run=prometheus-server" \
    -t "${PROM_BASE_NAME}"

# Create a firewall rule allowing external access to ports:
#   TCP 22: SSH
#   TCP 9090: k8s API server
#   TCP 80/443: nginx-ingress
gcloud compute firewall-rules create "${PROM_BASE_NAME}-external" \
    --network "${GCE_NETWORK}" \
    --action "allow" \
    --rules "tcp:22,tcp:9090,tcp:80,tcp:443" \
    --source-ranges "0.0.0.0/0" \
    --target-tags "${PROM_BASE_NAME}" \
    "${GCP_ARGS[@]}"

# The name and mount point of the GCE persistent disk.
DISK_NAME="${PROM_BASE_NAME}-${GCE_ZONE}"
DISK_MOUNT_POINT="/mnt/local"

# We don't ever delete the persistent disk in an automated way, but instead
# reuse it if it already exists. If you want to start from scratch, then delete
# the disk manually before running this.
EXISTING_DISK=$(gcloud compute disks list \
    --filter "name=${DISK_NAME}" \
    --format "value(name)" \
    "${GCP_ARGS[@]}")
if [[ -z "${EXISTING_DISK}" ]]; then
  # Attempt to create disk and ignore errors.
  gcloud compute disks create \
      "${DISK_NAME}" \
      --size "200GB" \
      --type "pd-ssd" \
      --labels "${PROM_BASE_NAME}=true" \
      "${GCE_ARGS[@]}" || :
fi

# NOTE: while promising, --device-name doesn't seem to do what it sounds like.
# NOTE: we assume the disk and instance already exist.
gcloud compute instances attach-disk \
    "${PROM_BASE_NAME}" \
    --disk "${DISK_NAME}" \
    "${GCE_ARGS[@]}" || :

# Verify that the disk is mounted and formatted.
gcloud compute ssh "${PROM_BASE_NAME}" "${GCE_ARGS[@]}" <<EOF
  set -euxo pipefail
  sudo -s

  # Shell options are not inherted by subprocesses.
  set -euxo pipefail

  if [[ ! -d ${DISK_MOUNT_POINT} ]]; then
      echo 'Creating ${DISK_MOUNT_POINT}'
      mkdir -p ${DISK_MOUNT_POINT}
  fi

  # TODO: find a better way to discovery the device-name.
  # TODO: make formatting conditional on a hard reset.
  if ! blkid /dev/sdb ; then
    mkfs.ext4 /dev/sdb
  fi

  # Create a systemd service that will remount this disk on future reboots.
  systemd_service_name="mount_gce_disk.service"
  if [[ ! -f "/etcd/systemd/systemd/\${systemd_service_name}" ]]; then
    sudo bash -c "(cat <<-EOF2
		[Unit]
		Description = Mount GCE disk ${DISK_NAME}
		[Service]
		Type=oneshot
		RemainAfterExit=yes
		ExecStart=/usr/bin/mount /dev/sdb ${DISK_MOUNT_POINT}
		ExecStop=/usr/bin/umount ${DISK_NAME}
		[Install]
		WantedBy = multi-user.target
EOF2
    ) >> /etc/systemd/system/\${systemd_service_name}"
    systemctl enable --now "\${systemd_service_name}"
    systemctl start "\${systemd_service_name}"
  fi

  if [[ ! -d /mnt/local/prometheus ]]; then
      echo 'Creating /mnt/local/prometheus'
      mkdir -p /mnt/local/prometheus
      # Create with permissions for prometheus.
      # TODO: replace with native k8s persistent volumes, if possible.
      chown nobody:nogroup /mnt/local/prometheus/
  fi
EOF
