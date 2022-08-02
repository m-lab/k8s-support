#!/bin/bash
#
# A script for applying an updated cloud-init config to all project VMs that
# are part of the platform cluster.
# 
# NOTE: Running `cloud-init clean` causes the host's ssh private keys to be
# regenerated, which will causes errors about the host key changing the next
# time you try to ssh into the VM.

PROJECT=${1:? Please provide a GCP project}
CLOUDINIT_FILE=${2:-./cloud-config_node.yml}

# Make sure that the cloud-init config file exists.
if ! [[ -f $CLOUDINIT_FILE ]]; then
  echo "cloud-init config file not found: ${CLOUDINIT_FILE}"
  exit 1
fi

INSTANCES=$(
  gcloud compute instances list \
    --filter "name~^mlab[1-4].*" \
    --project "$PROJECT" \
    --format "csv[no-heading](name, zone)"
)

for instance in $(echo "$INSTANCES"); do
  vm=$(echo "$instance" | cut -d, -f1)
  zone=$(echo "$instance" | cut -d, -f2)

  # Update the "user-data" metadata value for the instance, which is used by
  # cloud-init to configure the VM.
  gcloud compute instances add-metadata $vm \
    --metadata-from-file="user-data=${CLOUDINIT_FILE}" \
    --project "$PROJECT" \
    --zone "$zone"

  # Normally, cloud-init only runs most modules a single time per VM (when it
  # is first created). However, running `cloud-init clean` will clean out all
  # cloud-init configuration data, causing cloud-init to run all modules on the
  # next boot. Shutdown one minute in the future so that the SSH session can
  # exit cleanly.
  echo "Running 'cloud-init clean' and rebooting ${vm}..."
  gcloud compute ssh $vm \
    --quiet \
    --project "$PROJECT" \
    --zone "$zone" -- \
    'sudo cloud-init clean && sudo shutdown -r +1'
done

