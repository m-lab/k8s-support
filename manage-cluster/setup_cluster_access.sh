#!/bin/bash
#
# A small script to assist operators in setting up access to the platform
# cluster in each project from their local machine. Once this script is run on
# an operator's local machine (or any machine, really), each cluster can be
# accessed like the following examples.
#
# NOTE: You must source your .bashrc file after running this script.
#
# $ kubectl-mlab-sandbox get pods -o wide
# $ kubectl-mlab-staging get nodes
# $ kubectl-mlab-oti edit ds ndt

PROJECTS="mlab-sandbox mlab-staging mlab-oti"
KUBE_DIR="${HOME}/.kube"

if ! [[ -d $KUBE_DIR ]]; then
  mkdir "${KUBE_DIR}"
fi

for project in ${PROJECTS}; do
  gsutil cp "gs://k8s-support-${project}/admin.conf" "${KUBE_DIR}/kubeconfig.${project}" 
  cat << EOF >> "${HOME}/.bashrc"

function kubectl-${project} {
  kubectl --kubeconfig "${KUBE_DIR}/kubeconfig.${project}" \$@
}

EOF
done
  
