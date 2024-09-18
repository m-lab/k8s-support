#!/bin/bash

set -euxo pipefail

USAGE="$0 <project>"
PROJECT=${1:?Please provide the GCP project (e.g., mlab-sandbox): ${USAGE}}

# Include global configs.
source k8s_deploy.conf

# Issue a warning to the user and only continue if they agree.
cat <<EOF
  WARNING: this script is going to upgrade the _entire_ ${PROJECT} kubernetes
  API cluster to version ${K8S_VERSION}. Problems could occur. Be 100% sure you
  have read the changelogs to be sure there are no breaking changes for the
  current configuration. Also be sure to the specific kubeadm documentation for
  upgrading from the existing version to the new version, as sometimes a couple
  manual steps are required first. Also be sure you have read the kubeadm
  documentation for recovering from a failed state.

  Are you sure you want to continue? [y/N]:
EOF
read keepgoing
if [[ "${keepgoing}" != "y" ]]; then
  exit 0
fi

GCE_REGION_VAR="GCE_REGION_${PROJECT//-/_}"
GCE_REGION="${!GCE_REGION_VAR}"
GCE_ZONES_VAR="GCE_ZONES_${PROJECT//-/_}"
GCE_ZONES="${!GCE_ZONES_VAR}"

GCP_ARGS=("--project=${PROJECT}" "--quiet")

# Set up project GCS bucket variables.
GCS_BUCKET_K8S="GCS_BUCKET_K8S_${PROJECT//-/_}"

UPGRADE_STATE="new"

for zone in $GCE_ZONES; do
  gce_zone="${GCE_REGION}-${zone}"
  gce_name="api-${GCE_BASE_NAME}-${gce_zone}"

  GCE_ARGS=("--zone=${gce_zone}" "${GCP_ARGS[@]}")

  # The GCP internal DNS name of the machine.
  INTERNAL_DNS="${gce_name}.${gce_zone}.c.${PROJECT}.internal"

  # Get the instance's internal IP address.
  INTERNAL_IP=$(gcloud compute instances describe "${gce_name}" \
      --format "value(networkInterfaces[0].networkIP)" \
      "${GCE_ARGS[@]}" || true)

  # Get the instance's external IP address.
  EXTERNAL_IP=$(gcloud compute instances describe "${gce_name}" \
      --format "value(networkInterfaces[0].accessConfigs.natIP)" \
      "${GCE_ARGS[@]}" || true)

  if [[ "${UPGRADE_STATE}" == "new" ]]; then
    UPGRADE_COMMAND="apply ${K8S_VERSION} --config ./kubeadm-config.yml --force --certificate-renewal=true"
  else
    UPGRADE_COMMAND="node"
  fi

  # Evaluate the kubeadm config template with a beastly sed statement.
  gcloud compute ssh "${gce_name}" "${GCE_ARGS[@]}" <<EOF
    set -euxo pipefail
    sudo -s

    # Bash options are not inherited by subshells. Reset them to exit on any error.
    set -euxo pipefail

    # All k8s binaries are located in /opt/bin
    export PATH=\$PATH:/opt/bin

    # Use latest cluster version of admin kubeconfig for all API calls, since
    # the version located at /root/.kube/config could possibly be old and
    # expired.
    export KUBECONFIG=/etc/kubernetes/admin.conf

    # Fetch the cluster_data attribute to extract the API address.
    cluster_data=\$(
      curl --header "Metadata-Flavor: Google" --silent \
      "http://metadata.google.internal/computeMetadata/v1/instance/attributes/cluster_data"
    )
    api_load_balancer=\$(echo "\${cluster_data}" | jq --raw-output '.cluster_attributes.api_load_balancer')

    # Create the kubeadm config from the template
    sed -e 's|{{PROJECT}}|${PROJECT}|g' \
        -e 's|{{INTERNAL_IP}}|${INTERNAL_IP}|g' \
        -e 's|{{INTERNAL_DNS}}|${INTERNAL_DNS}|g' \
        -e 's|{{MACHINE_NAME}}|${gce_name}|g' \
        -e "s|{{API_LOAD_BALANCER}}|\$api_load_balancer|g" \
        -e 's|{{K8S_VERSION}}|${K8S_VERSION}|g' \
        -e 's|{{CLUSTER_CIDR}}|${K8S_CLUSTER_CIDR}|g' \
        -e 's|{{SERVICE_CIDR}}|${K8S_SERVICE_CIDR}|g' \
        /opt/mlab/conf/kubeadm-config.yml.template > \
        ./kubeadm-config.yml

    # The template variables {{TOKEN}}, {{CA_CERT_HASH}} and {{CERT_KEY}} are
    # not used when upgrading k8s on a node.  Here we simply replace the
    # variables with some meaningless text so that the YAML can be parsed.
    sed -i -e 's|{{TOKEN}}|NOT_USED|' \
           -e 's|{{CA_CERT_HASH}}|NOT_USED|' \
           -e 's|{{CERT_KEY}}|NOT_USED|' \
           kubeadm-config.yml

    # Drain the node of most workloads, except DaemonSets, since some of those
    # are critical for the node to even be part of the cluster (e.g., flannel).
    # The flag --delete-emptydir-data causes the command to "continue even if
    # there are pods using emptyDir". In our case, the CoreDNS pods use
    # emptyDir volumes, but we don't care about the data in there.
    kubectl drain $gce_name --ignore-daemonsets --delete-emptydir-data=true

    # Upgrade CNI plugins.
    curl -L "https://github.com/containernetworking/plugins/releases/download/${K8S_CNI_VERSION}/cni-plugins-linux-amd64-${K8S_CNI_VERSION}.tgz" | tar -C /opt/cni/bin -xz

    # Upgrade crictl.
    curl -L "https://github.com/kubernetes-sigs/cri-tools/releases/download/${K8S_CRICTL_VERSION}/crictl-${K8S_CRICTL_VERSION}-linux-amd64.tar.gz" | tar -C /opt/bin -xz

    # Upgrade kubeadm.
    pushd /opt/bin
    curl -L --remote-name-all https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubeadm
    chmod +x kubeadm
    popd

    # Tell kubeadm to upgrade all k8s components.
    kubeadm upgrade $UPGRADE_COMMAND

    # If this is the first API server being upgraded (i.e., UPGRADE_STATE=new),
    # copy the updated admin.conf cluster credentials file to the k8s-support
    # bucket for the project.
    if [[ $UPGRADE_STATE == "new" ]]; then
      gsutil cp /etc/kubernetes/admin.conf ${!GCS_BUCKET_K8S}/admin.conf
    fi

    # Stop the kubelet before we overwrite it, else curl may give "Text file
    # busy" error and fail to download the file.
    systemctl stop kubelet

    # Upgrade kubelet and kubectl.
    pushd /opt/bin
    curl -L --remote-name-all https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/{kubelet,kubectl}
    chmod +x {kubelet,kubectl}
    popd

    # Modify the --advertise-address flag to point to the external IP,
    # instead of the internal one that kubeadm populated. This is necessary
    # because external nodes (and especially kube-proxy) need to know of the
    # API node by its public IP, even though it is technically running in
    # a private VPC.
    sed -i -re 's|(advertise-address)=.+|\1=${EXTERNAL_IP}|' \
        /etc/kubernetes/manifests/kube-apiserver.yaml

    # Modify the default --listen-metrics-urls flag to listen on the VPC internal
    # IP address (the default is localhost). Sadly, this cannot currently be
    # defined in the configuration file, since the only place to define etcd
    # extraArgs is in the ClusterConfiguration, which applies to the entire
    # cluster, not a single etcd instances in a cluster.
    # https://github.com/kubernetes/kubeadm/issues/2036
    #
    # Only append a new listen-metrics-url on the internal interface if it
    # doesn't already exist. This is a workaround to a bug in kubeadm which can
    # cause an upgrade to not be idempotent:
    # https://github.com/kubernetes/kubeadm/issues/2058
    if ! grep listen-metrics-urls /etc/kubernetes/manifests/etcd.yaml | grep ${INTERNAL_IP}; then
      sed -i -re '/listen-metrics-urls/ s|$|,http://${INTERNAL_IP}:2381|' \
          /etc/kubernetes/manifests/etcd.yaml
    fi

    # Restart the kubelet.
    systemctl start kubelet

    # The above modifications to manifests should cause the api-server and etcd
    # to be restarted by the kubelet. Stop and wait here for a little bit to
    # give them time to restart before we continue.
    sleep 60

    # Mark the node schedulable again.
    kubectl uncordon $gce_name

    # Verify that the running api-server is actually upgraded.
    API_VERSION=\$(kubectl get pod kube-apiserver-${gce_name} -n kube-system \
        -o jsonpath='{.spec.containers[0].image}' | cut -d: -f2)
    if [[ \$API_VERSION != $K8S_VERSION ]]; then
      echo "Expected running kube-apiserver version ${K8S_VERSION}, but got \$API_VERSION."
      exit 1
    fi

    # Verify that the running kube-controller is actually upgraded.
    CONTROLLER_VERSION=\$(kubectl get pod kube-controller-manager-${gce_name} \
        -n kube-system -o jsonpath='{.spec.containers[0].image}' | cut -d: -f2)
    if [[ \$CONTROLLER_VERSION != $K8S_VERSION ]]; then
      echo "Expected running kube-controller-manager version ${K8S_VERSION}, but got \$CONTROLLER_VERSION."
      exit 1
    fi

    # Verify that the running kube-scheduler is actually upgraded.
    SCHEDULER_VERSION=\$(kubectl get pod kube-scheduler-${gce_name} \
        -n kube-system -o jsonpath='{.spec.containers[0].image}' | cut -d: -f2)
    if [[ \$SCHEDULER_VERSION != $K8S_VERSION ]]; then
      echo "Expected running kube-scheduler version ${K8S_VERSION}, but got \$SCHEDULER_VERSION."
      exit 1
    fi

    # Verify that k8s knows the kubelet is upgraded to the expected version.
    KUBELET_VERSION=\$(kubectl get node $gce_name \
        -o jsonpath='{.status.nodeInfo.kubeletVersion}')
    if [[ \$KUBELET_VERSION != $K8S_VERSION ]]; then
      echo "Expected kubelet version ${K8S_VERSION}, but got \$KUBELET_VERSION."
      exit 1
    fi

    # Verify that the kubeadm-config ConfigMap reflects the desired version.
    KUBEADM_CFG_VERSION=\$(kubectl describe cm kubeadm-config -n kube-system \
        | grep kubernetesVersion | cut -d' ' -f2)
    if [[ \$KUBEADM_CFG_VERSION != $K8S_VERSION ]]; then
      echo "Expected kubeadm-config ConfigMap version ${K8S_VERSION}, but got \$KUBEADM_CFG_VERSION."
      exit 1
    fi
EOF
  UPGRADE_STATE="existing"
done
