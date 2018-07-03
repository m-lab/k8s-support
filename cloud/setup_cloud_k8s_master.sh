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
REGION=${GOOGLE_CLOUD_REGION:-us-central1}
ZONE=${GOOGLE_CLOUD_ZONE:-us-central1-c}
GCE_NAME=${K8S_GCE_MASTER:-k8s-platform-master}
IP_NAME=${K8S_GCE_MASTER_IP:-k8s-platform-master-ip}

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

# Arrays of arguments are slightly cumbersome but using them ensures that if a
# space ever appears in an arg, then later usage of these values should not
# break in strange ways.
GCP_ARGS=("--project=${PROJECT}")
GCE_ARGS=("${GCP_ARGS[@]}" "--zone=${ZONE}")

EXISTING_INSTANCE=$(gcloud compute instances list "${GCP_ARGS[@]}" --filter "name=${GCE_NAME}" || true)
if [[ -n "${EXISTING_INSTANCE}" ]]; then
  gcloud compute instances delete "${GCE_ARGS[@]}" "${GCE_NAME}" --quiet
fi

EXTERNAL_IP=$(gcloud compute "${GCP_ARGS[@]}" addresses describe "${IP_NAME}" --region="${REGION}" --format="value(address)")

# Create the new GCE instance.
gcloud compute instances create "${GCE_NAME}" \
  "${GCE_ARGS[@]}" \
  --image "ubuntu-1710-artful-v20180612" \
  --image-project "ubuntu-os-cloud" \
  --boot-disk-size "10" \
  --boot-disk-type "pd-standard" \
  --boot-disk-device-name "${GCE_NAME}"  \
  --network "epoxy-extension-private-network" \
  --tags "dmz" \
  --machine-type "n1-standard-2" \
  --address "${EXTERNAL_IP}"

#  Give the instance time to appear.  Make sure it appears twice - there have
#  been multiple instances of it connecting just once and then failing again for
#  a bit.
until gcloud compute ssh "${GCE_NAME}" "${GCE_ARGS[@]}" --command true && \
      sleep 10 && \
      gcloud compute ssh "${GCE_NAME}" "${GCE_ARGS[@]}" --command true; do
  echo Waiting for "${GCE_NAME}" to boot up
  # Refresh keys in case they changed mid-boot. They change as part of the
  # GCE bootup process, and it is possible to ssh at the precise moment a
  # temporary key works, get that key put in your permanent storage, and have
  # all future communications register as a MITM attack.
  #
  # Same root cause as the need to ssh twice in the loop condition above.
  gcloud compute config-ssh "${GCP_ARGS[@]}"
done

# Become root and install everything.
#
# Eventually we want this to work on Container Linux as the master. However, it
# is too hard to hack on for a place in which to build an alpha system.  The
# below commands work on Ubuntu.
#
# Commands derived from the "Ubuntu" instructions at
#   https://kubernetes.io/docs/setup/independent/install-kubeadm/
gcloud compute ssh "${GCE_ARGS[@]}" "${GCE_NAME}" <<-\EOF
  sudo -s
  set -euxo pipefail
  apt-get update
  apt-get install -y docker.io

  apt-get update && apt-get install -y apt-transport-https curl
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  echo deb http://apt.kubernetes.io/ kubernetes-xenial main >/etc/apt/sources.list.d/kubernetes.list
  apt-get update
  apt-get install -y kubelet kubeadm kubectl

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
	  measurementlab/k8s-token-server:v0.0 -command /ro/usr/bin/kubeadm

  systemctl daemon-reload
  systemctl restart kubelet
EOF

# Become root and start everything
# TODO: fix the pod-network-cidr to be something other than a range which could
# potentially be intruded upon by GCP.
gcloud compute ssh "${GCE_ARGS[@]}" "${GCE_NAME}" <<-EOF
  sudo -s
  set -euxo pipefail
  kubeadm init \
    --apiserver-advertise-address ${EXTERNAL_IP} \
    --pod-network-cidr 192.168.0.0/16 \
    --apiserver-cert-extra-sans k8s-platform-master.${PROJECT}.measurementlab.net,${EXTERNAL_IP}
EOF

# Allow the user who installed k8s on the master to call kubectl.  As we
# productionize this process, this code should be deleted.
# For the next steps, we no longer want to be root.
gcloud compute ssh "${GCE_ARGS[@]}" "${GCE_NAME}" <<-\EOF
  set -x
  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
EOF

# Copy the network configs to the server.
gcloud compute scp "${GCE_ARGS[@]}" --recurse ../network "${GCE_NAME}":network

# This test pod is for dev convenience.
# TODO: delete this once index2ip works well.
gcloud compute scp "${GCE_ARGS[@]}" test-pod.yml "${GCE_NAME}":.

# Now that kubernetes is started up, set up the network configs.
# The CustomResourceDefinition needs to be defined before any resources which
# use that definition, so we apply that config first.
gcloud compute ssh "${GCE_ARGS[@]}" "${GCE_NAME}" <<-EOF
  sudo -s
  set -euxo pipefail
  kubectl annotate node k8s-platform-master flannel.alpha.coreos.com/public-ip-overwrite=${EXTERNAL_IP}
  kubectl label node k8s-platform-master mlab/type=cloud
  kubectl apply -f network/network-crd.yml
  kubectl apply -f network
EOF
