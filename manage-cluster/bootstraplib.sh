# Helper functions for bootstraping the M-Lab k8s cluster and adding new master
# nodes.

function create_master {
  local zone=$1
  local reboot_day=$2

  gce_zone="${GCE_REGION}-${zone}"
  gce_name="master-${GCE_BASE_NAME}-${gce_zone}"

  GCE_ARGS=("--zone=${gce_zone}" "${GCP_ARGS[@]}")

  GCE_TYPE_VAR="GCE_TYPE_${PROJECT//-/_}"

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
    --subnet "${GCE_K8S_SUBNET}" \
    --can-ip-forward \
    --tags "${GCE_NET_TAGS}" \
    --machine-type "${!GCE_TYPE_VAR}" \
    --address "${EXTERNAL_IP}" \
    --scopes "${GCE_API_SCOPES}" \
    --metadata-from-file "user-data=cloud-config_master.yml" \
    "${GCE_ARGS[@]}"

  #  Give the instance time to appear.  Make sure it appears twice - there have
  #  been multiple instances of it connecting just once and then failing again for
  #  a bit.
  until gcloud compute ssh "${gce_name}" --command true "${GCE_ARGS[@]}" --ssh-flag "-o PasswordAuthentication=no" && \
        sleep 10 && \
        gcloud compute ssh "${gce_name}" --command true "${GCE_ARGS[@]}" --ssh-flag "-o PasswordAuthentication=no"; do
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
      --filter "name=${gce_name} AND zone:(${gce_zone})" \
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

  # Become root, install and configure all the k8s components, and launch the
  # k8s-token-server and gcp-loadbalancer-proxy.
  gcloud compute ssh "${GCE_ARGS[@]}" "${gce_name}" <<-EOF
    set -euxo pipefail
    sudo --login

    # Bash options are not inherited by subshells. Reset them to exit on any error.
    set -euxo pipefail

    # Binaries will get installed in /opt/bin, put it in root's PATH, for both
    # interactive and non-interactve logins.
    echo -e "\nexport PATH=\$PATH:/opt/bin" >> /root/.profile
    echo -e "\nexport PATH=\$PATH:/opt/bin" >> /root/.bashrc

    # Adds /opt/bin to the end of the secure_path sudoers configuration.
    sed -i -e '/secure_path/ s|"$|:/opt/bin"|' /etc/sudoers

    # Write out the reboot day to a file in /etc. The reboot-node.service
    # systemd unit will read the contents of this file to determine when to
    # reboot the node.
    echo -n "${reboot_day}" > /etc/reboot-node-day

    # Install CNI plugins.
    mkdir -p /opt/cni/bin
    curl -L "https://github.com/containernetworking/plugins/releases/download/${K8S_CNI_VERSION}/cni-plugins-linux-amd64-${K8S_CNI_VERSION}.tgz" | tar -C /opt/cni/bin -xz

    # Install crictl.
    mkdir -p /opt/bin
    curl -L "https://github.com/kubernetes-incubator/cri-tools/releases/download/${K8S_CRICTL_VERSION}/crictl-${K8S_CRICTL_VERSION}-linux-amd64.tar.gz" | tar -C /opt/bin -xz

    # Install kubeadm, kubelet and kubectl.
    cd /opt/bin
    curl -L --remote-name-all https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/{kubeadm,kubelet,kubectl}
    chmod +x {kubeadm,kubelet,kubectl}

    # Install kubelet systemd service and enable it.
    curl -sSL "https://raw.githubusercontent.com/kubernetes/kubernetes/${K8S_VERSION}/build/debs/kubelet.service" \
        | sed "s:/usr/bin:/opt/bin:g" > /etc/systemd/system/kubelet.service
    mkdir -p /etc/systemd/system/kubelet.service.d
    curl -sSL "https://raw.githubusercontent.com/kubernetes/kubernetes/${K8S_VERSION}/build/debs/10-kubeadm.conf" \
        | sed "s:/usr/bin:/opt/bin:g" > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

    # Install etcdctl
    curl --location https://github.com/etcd-io/etcd/releases/download/${ETCDCTL_VERSION}/etcd-${ETCDCTL_VERSION}-linux-amd64.tar.gz | tar -xz
    cp etcd-${ETCDCTL_VERSION}-linux-amd64/etcdctl /opt/bin
    rm -rf etcd-${ETCDCTL_VERSION}-linux-amd64

    # Enable and start the kubelet service
    systemctl enable --now kubelet.service
    systemctl daemon-reload
    systemctl restart kubelet
EOF

  # Install gcsfuse and fusermount, then mount the repository's GCS bucket so we
  # can read and/or write the generated CA files to it to persist them in the
  # event we need to recreate a k8s master.
  gcloud compute ssh "${GCE_ARGS[@]}" "${gce_name}" <<EOF
    set -euxo pipefail
    sudo --login

    # Bash options are not inherited by subshells. Reset them to exit on any error.
    set -euxo pipefail

    # Build the gcsfuse binary in a throwaway Docker container. The build
    # artifact will end up directly in /opt/bin due to the volume mount. Also,
    # while in there, install the fuse package so we can extract the fusermount
    # binary
    docker run --rm --volume /opt/bin:/tmp/go/bin --env "GOPATH=/tmp/go" \
        golang:1.13 \
        /bin/bash -c \
        "go get -u github.com/googlecloudplatform/gcsfuse &&
        apt-get update --quiet=2 &&
        apt-get install --yes fuse &&
        cp /bin/fusermount /tmp/go/bin"

    # Create the mount point for the GCS bucket
    mkdir -p ${K8S_PKI_DIR}

    # Mount the GCS bucket. This bucket contains all of the k8s cluster
    # certificate and key files for all components generated by the first
    # master node.
    /opt/bin/gcsfuse --implicit-dirs -o rw,allow_other \
        ${!GCS_BUCKET_K8S} ${K8S_PKI_DIR}

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

  # Copy all config template files to the server.
  gcloud compute scp *.template "${gce_name}":/tmp "${GCE_ARGS[@]}"

  # Evaluate the kubeadm config template with a beastly sed statement.
  gcloud compute ssh "${gce_name}" "${GCE_ARGS[@]}" <<EOF
    set -euxo pipefail
    sudo --login

    # Bash options are not inherited by subshells. Reset them to exit on any error.
    set -euxo pipefail

    # Create the kubeadm config from the template
    sed -e 's|{{PROJECT}}|${PROJECT}|g' \
        -e 's|{{INTERNAL_IP}}|${INTERNAL_IP}|g' \
        -e 's|{{MASTER_NAME}}|${gce_name}|g' \
        -e 's|{{LOAD_BALANCER_NAME}}|api-${GCE_BASE_NAME}|g' \
        -e 's|{{K8S_VERSION}}|${K8S_VERSION}|g' \
        -e 's|{{K8S_CLUSTER_CIDR}}|${K8S_CLUSTER_CIDR}|g' \
        -e 's|{{K8S_SERVICE_CIDR}}|${K8S_SERVICE_CIDR}|g' \
        /tmp/kubeadm-config.yml.template > \
        ./kubeadm-config.yml
EOF

  if [[ "${ETCD_CLUSTER_STATE}" == "new" ]]; then

    gcloud compute ssh "${gce_name}" "${GCE_ARGS[@]}" <<EOF
      set -euxo pipefail
      sudo --login

      # Bash options are not inherited by subshells. Reset them to exit on any error.
      set -euxo pipefail

      # The template variables {{TOKEN}} and {{CA_CERT_HASH}} are not used when
      # creating the initial master node but kubeadm cannot parse the YAML with
      # the variables in the file. Here we simply replace the variables with
      # some meaningless text so that the YAML can be parse. These variables
      # are in the JoinConfiguration section, which isn't used here so the
      # values aren't used and don't matter.
      sed -i -e 's|{{TOKEN}}|NOT_USED|' \
             -e 's|{{CA_CERT_HASH}}|NOT_USED|' \
             kubeadm-config.yml

      kubeadm init --config kubeadm-config.yml

      # Copy the admin KUBECONFIG file to the GCS bucket.
      cp /etc/kubernetes/admin.conf ${K8S_PKI_DIR}

      # Since we don't know which of the CA files already existed in the GCS
      # bucket before creating this first instance (ETCD_CLUSTER_STATE=new),
      # just copy them all back. If they already existed it will be a no-op,
      # and if they didn't then they will now be persisted.
      for f in ${K8S_CA_FILES}; do
        cp /etc/kubernetes/pki/\${f} ${K8S_PKI_DIR}/pki/\${f}
      done
EOF
  else
    # Join the new master node to the existing cluster.
    gcloud compute ssh "${gce_name}" "${GCE_ARGS[@]}" <<EOF
      set -euxo pipefail
      sudo --login

      # Bash options are not inherited by subshells. Reset them to exit on any error.
      set -euxo pipefail

      # Get the join command.
      JOIN_COMMAND=\$(/opt/bin/kubeadm token create --print-join-command)

      # Extract the token from the join command
      TOKEN=\$(echo "\$JOIN_COMMAND" | egrep -o '[0-9a-z]{6}\.[0-9a-z]{16}')
      CA_CERT_HASH=\$(echo "\$JOIN_COMMAND" | egrep -o 'sha256:[0-9a-z]+')

      # Replace a few more variables in the config file.
      sed -i -e "s|{{TOKEN}}|\${TOKEN}|" \
             -e "s|{{CA_CERT_HASH}}|\${CA_CERT_HASH}|" \
             ./kubeadm-config.yml

      # Join the master node to the existing cluster.
      kubeadm join --config kubeadm-config.yml
EOF
  fi

  # Modify a few of the generated static manifests to suit our needs.
  gcloud compute ssh "${gce_name}" "${GCE_ARGS[@]}" <<EOF
    set -euxo pipefail
    sudo --login

    # Bash options are not inherited by subshells. Reset them to exit on any error.
    set -euxo pipefail

    # Modify the --advertise-address flag to point to the external IP,
    # instead of the internal one that kubeadm populated. This is necessary
    # because external nodes (and especially kube-proxy) need to know of the
    # master node by its public IP, even though it is technically running in
    # a private VPC.
    sed -i -re 's|(advertise-address)=.+|\1=${EXTERNAL_IP}|' \
        /etc/kubernetes/manifests/kube-apiserver.yaml

    # Modify the default --listen-metrics-urls flag to listen on the VPC internal
    # IP address (the default is localhost). Sadly, this cannot currently be
    # defined in the configuration file, since the only place to define etcd
    # extraArgs is in the ClusterConfiguration, which applies to the entire
    # cluster, not a single etcd instances in a cluster.
    # https://github.com/kubernetes/kubeadm/issues/2036
    sed -i -re '/listen-metrics-urls/ s|$|,http://${INTERNAL_IP}:2381|' \
        /etc/kubernetes/manifests/etcd.yaml

    # The above modifications to manifests will cause the api-server and etcd
    # to be restarted by the kubelet. Stop and wait here for a little bit to
    # give them time to restart before we continue.
    sleep 60
EOF

  # Configure root's account to be able to easily access kubectl as well as
  # etcdctl. As we productionize this process, this code
  # should be deleted.
  gcloud compute ssh "${gce_name}" "${GCE_ARGS[@]}" <<\EOF
    set -x
    sudo --login

    mkdir -p /root/.kube
    cp -i /etc/kubernetes/admin.conf /root/.kube/config
    chown root:root /root/.kube/config
    bash -c "(cat <<-EOF2
	export ETCDCTL_API=3
	export ETCDCTL_DIAL_TIMEOUT=3s
	export ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
	export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/peer.crt
	export ETCDCTL_KEY=/etc/kubernetes/pki/etcd/peer.key
	export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379
EOF2
    ) | tee -a /root/.profile /root/.bashrc"
EOF

  # Annotate and label the master node.
  gcloud compute ssh "${gce_name}" "${GCE_ARGS[@]}" <<-EOF
    set -euxo pipefail
    sudo --login

    # Bash options are not inherited by subshells. Reset them to exit on any error.
    set -euxo pipefail

    kubectl annotate node ${gce_name} flannel.alpha.coreos.com/public-ip-overwrite=${EXTERNAL_IP}
    kubectl label node ${gce_name} mlab/type=virtual

    # As a final step, unmount the GCS bucket, as it is no longer needed.
    umount ${K8S_PKI_DIR}
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
    cache_control="Cache-Control:private, max-age=0, no-transform"
    gsutil -h "$cache_control" cp setup_k8s.sh gs://${!GCS_BUCKET_EPOXY}/stage3_ubuntu/setup_k8s.sh

    # Apply all configs and workloads to the cluster. This only needs to happen
    # on the first master that is created.
    ./create_k8s_configs.sh "${PROJECT}"
    ./apply_k8s_configs.sh "${PROJECT}"
  fi


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
}

# Delete the GCE instance-group associated with a master node.
function delete_instance_group {
  local name=$1
  local zone=$2
  local existing_instance_group

  existing_instance_group=$(gcloud compute instance-groups list \
      --filter "name=${name} AND zone:($zone)" \
      --format "value(name)" \
      "${GCP_ARGS[@]}" || true)
  if [[ -n "${existing_instance_group}" ]]; then
    gcloud compute instance-groups unmanaged delete "${name}" \
        --zone "${zone}" \
        "${GCP_ARGS[@]}"
  fi
}

# Removes an instance from the k8s master loadbalancer target pool.
function delete_target_pool_instance {
  local name=$1
  local zone=$2
  local existing_instances

  existing_instances=$(gcloud compute target-pools describe "${GCE_BASE_NAME}" \
      --format "value(instances)" \
      --region "${GCE_REGION}" \
      "${GCP_ARGS[@]}" || true)
  if echo "${existing_instances}" | grep "${name}"; then
    gcloud compute target-pools remove-instances "${GCE_BASE_NAME}" \
        --instances "${name}" \
        --instances-zone "${zone}" \
        "${GCP_ARGS[@]}"
  fi
}

# Removes a backend from the token-server backend service.
function delete_token_server_backend {
  local name=$1
  local zone=$2
  local existing_backends

  existing_backends=$(gcloud compute backend-services describe "${TOKEN_SERVER_BASE_NAME}" \
      --format "value(backends)" \
      --region "${GCE_REGION}" \
      "${GCP_ARGS[@]}" || true)
  if echo "${existing_backends}" | grep "${name}"; then
    gcloud compute backend-services remove-backend "${TOKEN_SERVER_BASE_NAME}" \
        --instance-group "${name}" \
        --instance-group-zone "${zone}" \
        --region "${GCE_REGION}" \
        "${GCP_ARGS[@]}"
  fi
}

# Find the lowest network number available for a new subnet.
# Stolen from https://github.com/m-lab/epoxy/blob/master/deploy_epoxy_container.sh#L54
function find_lowest_network_number() {
  local current_sequence=$( mktemp )
  local natural_sequence=$( mktemp )
  local available=$( mktemp )

  # List current network subnets, and extract the second octet from each.
  gcloud compute networks subnets list \
    --network "${GCE_NETWORK}" --format "value(ipCidrRange)" "${GCP_ARGS[@]}" \
    | cut -d. -f2 | sort -n > "${current_sequence}"

  # Generate a natural sequence from 0 to 255.
  seq 0 255 > "${natural_sequence}"

  # Find values present in $natural_sequence but missing from $current_sequence.
  # -1 = suppress lines unique to file 1
  # -3 = suppress lines that appear in both files
  # As a result, only report lines that are unique to "${natural_sequence}".
  comm -1 -3 --nocheck-order \
    "${current_sequence}" "${natural_sequence}" > "${available}"

  # "Return" the first $available value: the lowest available network number.
  head -n 1 "${available}"

  # Clean up temporary files.
  rm -f "${current_sequence}" "${natural_sequence}" "${available}"
}
