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
REGION=${GOOGLE_CLOUD_REGION:-us-central1}
ZONE=${GOOGLE_CLOUD_ZONE:-us-central1-c}
GCE_NAME=${K8S_GCE_MASTER:-k8s-platform-master}
IP_NAME=${K8S_GCE_MASTER_IP:-k8s-platform-master-ip}

# Add gcloud to PATH.
# Next line is a pragma directive telling the linter to skip path.bash.inc
# shellcheck source=/dev/null
source "${HOME}/google-cloud-sdk/path.bash.inc"

# Set the project and zone for all future gcloud commands.  This alters the
# surrounding environment, which is okay in Travis and more questionable in a
# shell context.
gcloud config set project "${PROJECT}"
gcloud config set compute/zone "${ZONE}"

EXISTING_INSTANCE=$(gcloud compute instances list --filter "name=${GCE_NAME}" || true)
if [[ -n "${EXISTING_INSTANCE}" ]]; then
  gcloud compute instances delete "${GCE_NAME}" --quiet
fi

EXTERNAL_IP=$(gcloud compute addresses describe "${IP_NAME}" --region="${REGION}" --format="value(address)")

# Create the new GCE instance.
gcloud compute instances create "${GCE_NAME}" \
  --image "ubuntu-1710-artful-v20180405" \
  --image-project "ubuntu-os-cloud" \
  --boot-disk-size "10" \
  --boot-disk-type "pd-standard" \
  --boot-disk-device-name "${GCE_NAME}"  \
  --tags "dmz" \
  --network "epoxy-extension-private-network" \
  --machine-type "n1-standard-2" \
  --address "${EXTERNAL_IP}"

#  Give the instance time to appear.  Make sure it appears twice - there have
#  been multiple instances of it connecting just once and then failing again for
#  a bit.
until gcloud compute ssh "${GCE_NAME}" --command true && \
      sleep 10 && \
      gcloud compute ssh "${GCE_NAME}" --command true; do
  echo Waiting for "${GCE_NAME}" to boot up
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
# Eventually we want this to work on Container Linux as the master. However, it
# is too hard to hack on for a place in which to build an alpha system.  The
# below commands work on Ubuntu.
#
# Commands derived from the "Ubuntu" instructions at
#   https://kubernetes.io/docs/setup/independent/install-kubeadm/
gcloud compute ssh "${GCE_NAME}" <<-\EOF
  sudo -s
  set -euxo pipefail
  apt-get update
  apt-get install -y docker.io

  apt-get update && apt-get install -y apt-transport-https curl
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  echo deb http://apt.kubernetes.io/ kubernetes-xenial main >/etc/apt/sources.list.d/kubernetes.list
  apt-get update
  apt-get install -y kubelet kubeadm kubectl

  systemctl daemon-reload
  systemctl restart kubelet
EOF

# Become root and start everything
gcloud compute ssh "${GCE_NAME}" <<-EOF
  sudo -s
  set -euxo pipefail
  kubeadm init \
    --apiserver-advertise-address ${EXTERNAL_IP} \
    --pod-network-cidr 10.244.0.0/16 \
    --apiserver-cert-extra-sans k8s-platform-master.${PROJECT}.measurementlab.net,${EXTERNAL_IP}
EOF

# Allow the user who installed k8s on the master to call kubectl.  As we
# productionize this process, this code should be deleted.
# For the next steps, we no longer want to be root.
gcloud compute ssh "${GCE_NAME}" <<-\EOF
  set -x
  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
EOF

# Copy the network configs to the server.
# CustomResourceDefinitions need to be defined outside of the file that first
# uses them (as of 2017-6-11) so network-crd.yml is in its own file.
gcloud compute scp network-crd.yml "${GCE_NAME}":.
gcloud compute scp kube-network.yml "${GCE_NAME}":.

# This test pod is for dev convenience.
# TODO: delete this once index2ip works well.
gcloud compute scp test-pod.yml "${GCE_NAME}":.

# Now that kubernetes is started up, set up the network configs.
gcloud compute ssh "${GCE_NAME}" <<-EOF
  sudo -s
  set -euxo pipefail
  pushd /opt/cni/bin
    wget -q https://storage.googleapis.com/k8s-platform-mlab-sandbox/bin/multus
    chmod 755 multus
  popd
  kubectl label node k8s-platform-master mlab/type=cloud
  kubectl apply -f network-crd.yml
  kubectl apply -f kube-network.yml
EOF

# FIXME
# Now that everything is started up, run the cert server. This cert server is
# bad, and we should replace it with a better system ASAP. It replaces a system
# where passwords were checked into source control and also posted publicly.
gcloud compute scp cert_server.py "${GCE_NAME}:"
gcloud compute ssh "${GCE_NAME}" <<-EOF
  sudo -s
  set -euxo pipefail
  apt-get install -y python-httplib2
  python cert_server.py > certlog.log 2>&1 &
  disown
EOF
