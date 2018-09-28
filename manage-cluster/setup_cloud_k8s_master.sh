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
GCE_BASE_NAME=k8s-platform-master
GCE_IMAGE_FAMILY="ubuntu-1804-lts"
GCE_IMAGE_PROJECT="ubuntu-os-cloud"
GCE_DISK_SIZE="10"
GCE_DISK_TYPE="pd-standard"
GCE_NETWORK="epoxy-extension-private-network"
GCE_NET_TAGS="dmz" # Comma separate list
GCE_TYPE="n1-standard-2"
# NOTE: GCP currently only offers tcp/udp network load balacing on a regional level.
# If we want more redundancy than GCP zones offer, then we'll need to figure out
# some way to use a proxying load balancer.
GCE_ZONES="us-central1-a us-central1-b us-central1-c"
GCE_LB_ZONE="us-central1-c"
K8S_VERSION="1.11.1"
K8S_CA_FILES="ca.crt ca.key sa.key sa.pub front-proxy-ca.crt front-proxy-ca.key etcd/ca.crt etcd/ca.key"
K8S_PKI_DIR="/tmp/kubernetes-pki"

# Delete any temporary files and dirs from a previous run.
rm -rf setup_k8s.sh transaction.yaml

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

# Create an IP for the load balancer and store the address.
EXISTING_LB_IP=$(gcloud compute addresses list \
    --filter "name=${GCE_BASE_NAME} AND region:${GCE_LB_ZONE%-*}" \
    --format "value(address)" "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_LB_IP}" ]]; then
  LOAD_BALANCER_IP=$EXISTING_LB_IP
else
  gcloud compute addresses create "${GCE_BASE_NAME}" \
      --region "${GCE_LB_ZONE%-*}" "${GCP_ARGS[@]}"
  LOAD_BALANCER_IP=$(gcloud compute addresses list \
      --filter "name=${GCE_BASE_NAME} AND region:${GCE_LB_ZONE%-*}" \
      --format "value(address)" "${GCP_ARGS[@]}")
fi

# Check the value of the existing IP address associated with the load balancer
# IP's name. If it's the same as the current/existing IP, then leave DNS alone,
# else delete the existing DNS RR and create a new one.
EXISTING_LB_DNS_IP=$(gcloud dns record-sets list \
    --zone "${PROJECT}-measurementlab-net" \
    --name "${GCE_BASE_NAME}.${PROJECT}.measurementlab.net." \
    --format "value(rrdatas[0])" "${GCP_ARGS[@]}")

if [[ "${EXISTING_LB_DNS_IP}" != "${EXISTING_LB_IP}" ]]; then
  gcloud dns record-sets transaction start \
      --zone "${PROJECT}-measurementlab-net" "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction remove \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${GCE_BASE_NAME}.${PROJECT}.measurementlab.net." \
      --type A --ttl 300 "${EXISTING_LB_DNS_IP}" "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction add \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${GCE_BASE_NAME}.${PROJECT}.measurementlab.net." \
      --type A --ttl 300 "${LOAD_BALANCER_IP}" "${GCP_ARGS[@]}"
  gcloud dns record-sets transaction execute \
      --zone "${PROJECT}-measurementlab-net" "${GCP_ARGS[@]}"
fi

# Delete any existing forwarding rule. We do this before working with the
# target pool because any existing target pool cannot be deleted when an
# existing fowarding rule is using it.
EXISTING_FWD=$(gcloud compute forwarding-rules list \
    --filter "name=${GCE_BASE_NAME} AND region:${GCE_LB_ZONE%-*}" \
    --format "value(creationTimestamp)" "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_FWD}" ]]; then
  gcloud compute forwarding-rules delete "${GCE_BASE_NAME}" \
      --region "${GCE_LB_ZONE%-*}" "${GCP_ARGS[@]}"
fi

# Create a target pool for the load balancer. If one already exists, then delete
# it and recreate it, since we don't know which GCE instances were attached to
# the existing one. And delete and recreate the http-health-check prior to
# [re]creating the new target pool.
EXISTING_TP=$(gcloud compute target-pools list \
    --filter "name=${GCE_BASE_NAME} AND region:${GCE_LB_ZONE%-*}" \
    --format "value(creationTimestamp)" "${GCP_ARGS[@]}" || true)
if [[ -n "$EXISTING_TP" ]]; then
  gcloud compute target-pools delete "${GCE_BASE_NAME}" \
      --region "${GCE_LB_ZONE%-*}" "${GCP_ARGS[@]}"
fi

# [Re]create the http-health-check for the nodes in the target pool.
EXISTING_HEALTH_CHECK=$(gcloud compute http-health-checks list \
    --filter "name=${GCE_BASE_NAME}" "${GCP_ARGS[@]}" || true)
if [[ -n "${EXISTING_HEALTH_CHECK}" ]]; then
  gcloud compute http-health-checks delete "${GCE_BASE_NAME}" "${GCP_ARGS[@]}"
fi
gcloud compute http-health-checks create "${GCE_BASE_NAME}" \
    --port 8080 --request-path "/healthz" "${GCP_ARGS[@]}"

gcloud compute target-pools create "${GCE_BASE_NAME}" \
    --region "${GCE_LB_ZONE%-*}" --http-health-check "${GCE_BASE_NAME}" \
    "${GCP_ARGS[@]}"

# [Re]create the forwarding rule using the target pool we just create.
gcloud compute forwarding-rules create "${GCE_BASE_NAME}" \
    --region "${GCE_LB_ZONE%-*}" --ports 6443 --address "${GCE_BASE_NAME}" \
    --target-pool "${GCE_BASE_NAME}" "${GCP_ARGS[@]}"

#
# Create one GCE instance for each of $GCE_ZONES defined.
#
ETCD_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER=""
FIRST_INSTANCE_NAME=""
FIRST_INSTANCE_IP=""

for zone in $GCE_ZONES; do

  GCE_ARGS=("--zone=${zone}" "${GCP_ARGS[@]}")

  gce_name="${GCE_BASE_NAME}-${zone}"

  # If an existing GCE instance with this name exists, delete it and recreate
  # it. If this script is being run then we want to start fresh.
  EXISTING_INSTANCE=$(gcloud compute instances list \
      --filter "name=${gce_name} AND zone:${zone}" \
      --format "value(creationTimestamp)" "${GCP_ARGS[@]}" || true)
  if [[ -n "${EXISTING_INSTANCE}" ]]; then
    gcloud compute instances delete "${gce_name}" "${GCE_ARGS[@]}"
  fi

  # Create a static IP for the GCE instance, or use the one that already exists.
  EXISTING_IP=$(gcloud compute addresses list \
      --filter "name=${gce_name} AND region:${zone%-*}" \
      --format "value(address)" "${GCP_ARGS[@]}" || true)
  if [[ -n "${EXISTING_IP}" ]]; then
    EXTERNAL_IP="${EXISTING_IP}"
  else
    gcloud compute addresses create "${gce_name}" --region "${zone%-*}" \
        "${GCP_ARGS[@]}"
    EXTERNAL_IP=$(gcloud compute addresses list \
        --filter "name=${gce_name} AND region:${zone%-*}" \
        --format "value(address)" "${GCP_ARGS[@]}")
  fi

  # Check the value of the existing IP address in DNS associated with this GCE
  # instance. If it's the same as the current/existing IP, then leave DNS alone,
  # else delete the existing DNS RR and create a new one.
  EXISTING_DNS_IP=$(gcloud dns record-sets list \
      --zone "${PROJECT}-measurementlab-net" \
      --name "${gce_name}.${PROJECT}.measurementlab.net." \
      --format "value(rrdatas[0])" "${GCP_ARGS[@]}" || true)

  if [[ -z "${EXISTING_DNS_IP}" ]]; then
    # Add the record.
    gcloud dns record-sets transaction start \
        --zone "${PROJECT}-measurementlab-net" "${GCP_ARGS[@]}"
    gcloud dns record-sets transaction add \
        --zone "${PROJECT}-measurementlab-net" \
        --name "${gce_name}.${PROJECT}.measurementlab.net." \
        --type A --ttl 300 "${EXTERNAL_IP}" "${GCP_ARGS[@]}"
    gcloud dns record-sets transaction execute \
        --zone "${PROJECT}-measurementlab-net" "${GCP_ARGS[@]}"
  elif [[ "${EXISTING_DNS_IP}" != "${EXTERNAL_IP}" ]]; then
    # Add the record, deleting the existing one first.
    gcloud dns record-sets transaction start \
        --zone "${PROJECT}-measurementlab-net" "${GCP_ARGS[@]}"
    gcloud dns record-sets transaction remove \
        --zone "${PROJECT}-measurementlab-net" \
        --name "${gce_name}.${PROJECT}.measurementlab.net." \
        --type A --ttl 300 "${EXISTING_DNS_IP}" "${GCP_ARGS[@]}"
    gcloud dns record-sets transaction add \
        --zone "${PROJECT}-measurementlab-net" \
        --name "${gce_name}.${PROJECT}.measurementlab.net." \
        --type A --ttl 300 "${EXTERNAL_IP}" "${GCP_ARGS[@]}"
    gcloud dns record-sets transaction execute \
        --zone "${PROJECT}-measurementlab-net" "${GCP_ARGS[@]}"
  fi

  # [Re]create the new GCE instance.
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
      --filter "name=${gce_name} AND zone:${zone}" \
      --format "value(networkInterfaces[0].networkIP)" "${GCP_ARGS[@]}")

  # If this is the first instance being create, it must be added to the target
  # pool now, else creating the initial cluster will fail. Subsequent instances
  # will be added much later.
  if [[ "${ETCD_CLUSTER_STATE}" == "new" ]]; then
    gcloud compute target-pools add-instances "${GCE_BASE_NAME}" \
        --instances "${gce_name}" --instances-zone "${zone}" "${GCP_ARGS[@]}"
  fi

  # We need to record the name and IP of the first instance we instantiate
  # because its name and IP will be needed when joining later instances to the
  # cluster created by the instantiation of the first instance.
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
    apt-get install -y kubelet=${K8S_VERSION}-00 kubeadm=${K8S_VERSION}-00 kubectl=${K8S_VERSION}-00

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
        --name token_server \
        measurementlab/k8s-token-server:v0.0 -command /ro/usr/bin/kubeadm

    # Our k8s api servers only run over HTTPS, but currently the TCP network
    # load balancer in GCP only supports HTTP health checks. This runs a
    # container that will expose an HTTP port and will run an HTTPS request on
    # the api-server on the localhost.
    # https://cloud.google.com/load-balancing/docs/network/: "Network Load
    # Balancing relies on legacy HTTP Health checks for determining instance
    # health. Even if your service does not use HTTP, you'll need to at least
    # run a basic web server on each instance that the health check system can
    # query."
    # https://github.com/kubernetes/kubernetes/issues/43784#issuecomment-415090237
    #
    # The official exec-healthz images (k8s.gcr.io/exechealthz:1.2) uses the
    # golang:1.10-alpine image which doesn't include openssl, so https doesn't
    # work. The image fetched below is a custom one I (kinkade) built using the
    # golang:1.10-stretch base image instead, which does have openssl installed.
    # Ugh.
    docker run --detach --publish 8080:8080 --network host --restart always \
        --name exechealthz -- \
        measurementlab/exechealthz-stretch:v1.2 \
          -port 8080 -period 3s -latency 2s \
          -cmd "wget -O- --no-check-certificate https://localhost:6443/healthz"

    # Create a suitable cloud-config file for the cloud provider.
    echo -e "[Global]\nproject-id = ${PROJECT}\n" > /etc/kubernetes/cloud.conf

    # Sets the kublet's cloud provider config to gce and points to a suitable config file.
    sed -ie '/KUBELET_KUBECONFIG_ARGS=/ \
        s|"$| --cloud-provider=gce --cloud-config=/etc/kubernetes/cloud.conf"|' \
        /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

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
    cp /tmp/kubernetes-pki/admin.conf /etc/kubernetes/ 2> /dev/null || true
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

  # Become root and start everything
  # TODO: fix the pod-network-cidr to be something other than a range which could
  # potentially be intruded upon by GCP.
  #
  # Many of the following configurations were gleaned from:
  # https://kubernetes.io/docs/setup/independent/high-availability/
  if [[ "${ETCD_CLUSTER_STATE}" == "new" ]]; then
    gcloud compute ssh "${GCE_ARGS[@]}" "${gce_name}" <<EOF
      sudo -s
      set -euxo pipefail

      # Create the kubeadm config from the template
      sed -e 's|{{PROJECT}}|${PROJECT}|g' \
          -e 's|{{INTERNAL_IP}}|${INTERNAL_IP}|g' \
          -e 's|{{MASTER_NAME}}|${gce_name}|g' \
          -e 's|{{LOAD_BALANCER_NAME}}|${GCE_BASE_NAME}|g' \
          -e 's|{{ETCD_CLUSTER_STATE}}|${ETCD_CLUSTER_STATE}|g' \
          -e 's|{{ETCD_INITIAL_CLUSTER}}|${ETCD_INITIAL_CLUSTER}|g' \
          -e 's|{{K8S_VERSION}}|${K8S_VERSION}|g' \
          ./kubeadm-config.yml.template > \
          ./kubeadm-config.yml

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

      # Create the kubeadm config from the template
      sed -e 's|{{PROJECT}}|${PROJECT}|g' \
          -e 's|{{INTERNAL_IP}}|${INTERNAL_IP}|g' \
          -e 's|{{MASTER_NAME}}|${gce_name}|g' \
          -e 's|{{LOAD_BALANCER_NAME}}|${GCE_BASE_NAME}|g' \
          -e 's|{{ETCD_CLUSTER_STATE}}|${ETCD_CLUSTER_STATE}|g' \
          -e 's|{{ETCD_INITIAL_CLUSTER}}|${ETCD_INITIAL_CLUSTER}|g' \
          -e 's|{{K8S_VERSION}}|${K8S_VERSION}|g' \
          ./kubeadm-config.yml.template > \
          ./kubeadm-config.yml

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
    ca_cert_hash=$(openssl x509 -pubkey -in pki/ca.crt | \
        openssl rsa -pubin -outform der 2>/dev/null | 
        openssl dgst -sha256 -hex | sed 's/^.* //')
    sed -e "s/{{CA_CERT_HASH}}/${ca_cert_hash}/" ../node/setup_k8s.sh.template > setup_k8s.sh
    gsutil cp setup_k8s.sh gs://epoxy-mlab-sandbox/stage3_coreos/setup_k8s.sh
  fi

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
EOF

  # Now that the instance should be functional, add it to our load balancer target pool.
  if [[ "${ETCD_CLUSTER_STATE}" == "existing" ]]; then
    gcloud compute target-pools add-instances "${GCE_BASE_NAME}" \
        --instances "${gce_name}" --instances-zone "${zone}" "${GCP_ARGS[@]}"
  fi

  # After the first iteration of this loop, the cluster state becomes "existing"
  # for all other iterations, since the first iteration bootstraps the cluster,
  # while subsequent ones expand the existing cluster.
  ETCD_CLUSTER_STATE="existing"

done
