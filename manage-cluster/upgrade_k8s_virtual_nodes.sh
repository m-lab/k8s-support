#!/bin/bash
#
# Upgrades k8s components on all virtual nodes that are not master nodes.

set -euxo pipefail

usage() {
  echo "USAGE: $0 <project> <kubeconfig>"
}

PROJECT=$1
KUBECONFIG=${2:-}

if [[ -z $PROJECT ]]; then
  echo "Please specify the GCP project."
  usage
  exit 1
fi

# Source all the global configuration variables.
source k8s_deploy.conf

GCS_BUCKET_K8S="GCS_BUCKET_K8S_${PROJECT//-/_}"

# If a KUBECONFIG wasn't passed as an argument to the script, then attempt to
# fetch it from GCS.
if [[ -z "${KUBECONFIG}" ]]; then
  gsutil cp "gs://${!GCS_BUCKET_K8S}/admin.conf" .
  KUBECONFIG="./admin.conf"
fi
export KUBECONFIG=$KUBECONFIG

# Get a list of all the virtual nodes in the cluster that are not master nodes.
NODES=$(
  kubectl get nodes \
      --selector 'mlab/type=virtual,!node-role.kubernetes.io/control-plane' \
      --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}'
)

UPGRADE_NODES=""
for node in $NODES; do
  CURRENT_VERSION=$(
    kubectl get node $node -o jsonpath='{.status.nodeInfo.kubeletVersion}{"\n"}'
  )
  # If the node is already at the right version, then continue.
  if [[ $CURRENT_VERSION == $K8S_VERSION ]]; then
    continue
  else
    UPGRADE_NODES="${UPGRADE_NODES} ${node}"
  fi
done

set +x
echo -e "\n\n##### NODES TO BE UPGRADED #####"
for node in $UPGRADE_NODES; do
  echo $node
done
echo -e "\n"

# Issue a warning to the user and only continue if they agree.
cat <<EOF
WARNING: this script is going to attempt to upgrade all of the virtual nodes
listed above in the ${PROJECT} kubernetes platform cluster to version
${K8S_VERSION}.

Are you sure you want to continue? [y/N]:
EOF
read keepgoing
if [[ "${keepgoing}" != "y" ]]; then
  exit 0
fi
set -x

for node in $UPGRADE_NODES; do
  # Replace the dots in the hostname with dashes.
  node="${node//./-}"
  # Determine the zone of the node.
  ZONE=$(gcloud compute instances list --filter "name=${node}" \
      --project ${PROJECT} \
      --format "value(zone)")
  # Ssh to the node, update all the k8s binaries.
  gcloud compute ssh "${node}" --project "${PROJECT}" --zone "${ZONE}" <<EOF
    set -euxo pipefail
    sudo -s
  
    # Bash options are not inherited by subshells. Reset them to exit on any error.
    set -euxo pipefail
  
    # Stop the kubelet
    systemctl stop kubelet

    # Update CNI plugins.
    mkdir -p /opt/cni/bin
    curl -L "https://github.com/containernetworking/plugins/releases/download/${K8S_CNI_VERSION}/cni-plugins-linux-amd64-${K8S_CNI_VERSION}.tgz" | tar -C /opt/cni/bin -xz
  
    # Update crictl.
    mkdir -p /opt/bin
    curl -L "https://github.com/kubernetes-incubator/cri-tools/releases/download/${K8S_CRICTL_VERSION}/crictl-${K8S_CRICTL_VERSION}-linux-amd64.tar.gz" | tar -C /opt/bin -xz
  
    # Update kubeadm, kubelet and kubectl.
    cd /opt/bin
    curl -L --remote-name-all https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/{kubeadm,kubelet,kubectl}
    chmod +x {kubeadm,kubelet,kubectl}

    # Start the kubelet again.
    systemctl start kubelet
EOF
done
