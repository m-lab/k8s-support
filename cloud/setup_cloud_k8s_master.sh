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

PROJECT=${GOOGLE_CLOUD_PROJECT:-mlab-sandbox}
ZONE=${GOOGLE_CLOUD_ZONE:-us-central1-c}
GCE_NAME=${K8S_GCE_MASTER:-k8s-platform-master}

# Add gcloud to PATH.
source "${HOME}/google-cloud-sdk/path.bash.inc"

# Set the project and zone for all future gcloud commands.  This alters the
# surrounding environment, which is okay in Travis and more questionable in a
# shell context.
gcloud config set project $PROJECT
gcloud config set compute/zone $ZONE

EXISTING_INSTANCE=$(gcloud compute instances list --filter "name=${GCE_NAME}")
if [[ -n "${EXISTING_INSTANCE}" ]]; then
  gcloud compute instances delete $GCE_NAME --quiet
fi

# Create the new GCE instance.
gcloud compute instances create $GCE_NAME \
  --image "ubuntu-1604-xenial-v20180323" \
  --image-project "ubuntu-os-cloud" \
  --boot-disk-size "10" \
  --boot-disk-type "pd-standard" \
  --boot-disk-device-name $GCE_NAME  \
  --tags "dmz" \
  --machine-type "n1-standard-2"

#  Give the instance time to appear.  Make sure it appears twice - there have
#  been multiple instances of it connecting just once and then failing again for
#  a bit.
until gcloud compute ssh $GCE_NAME --command true && \
      sleep 10 && \
      gcloud compute ssh $GCE_NAME --command true; do
  echo Waiting for $GCE_NAME to boot up
  # Refresh keys in case they changed mid-boot. They change as part of the
  # GCE bootup process, and it is possible to ssh at the precise moment a
  # temporary key works, get that key put in your permanent storage, and have
  # all future communications register as a MITM attack.
  #
  # Same root cause as the need to ssh twice in the loop condition above.
  gcloud compute config-ssh
done

# Become root and install everything.
#
# Kubeadm-installer has some jank, and seems to leave the shell in a bad state,
# or possibly there is a race condition.  For whatever reason, all problems go
# away if you disconnect and reconnect after running that command.
gcloud compute ssh $GCE_NAME <<-EOF
  sudo -s
  apt-get update -y
  apt-get install -y apt-transport-https
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  echo deb http://apt.kubernetes.io/ kubernetes-xenial main | tee /etc/apt/sources.list.d/kubernetes.list
  apt-get update -y
  apt-get install -y docker.io
  systemctl daemon-reload
  systemctl enable docker
  systemctl restart docker
  docker run -i \
    -v /etc:/rootfs/etc \
    -v /opt:/rootfs/opt \
    -v /usr/bin:/rootfs/usr/bin \
    xakra/kubeadm-installer:0.4.7 ubuntu install || true
EOF

# Find the instance's external IP
EXTERNAL_IP=$(gcloud compute instances list --filter "name=${GCE_NAME}" \
                --format flattened | grep natIP | awk '{print $2}')

# Become root and start everything
gcloud compute ssh $GCE_NAME <<-EOF
  sudo -s
  systemctl daemon-reload
  systemctl enable docker kubelet
  systemctl restart docker kubelet
  kubeadm init --apiserver-advertise-address ${EXTERNAL_IP}
EOF

# Allow the user who installed k8s on the master to call kubectl.  As we
# productionize this process, this code should be deleted.
# For the next steps, we no longer want to be root.
gcloud compute ssh $GCE_NAME <<-EOF
  set -x
  mkdir -p \$HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config
  sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config
EOF
