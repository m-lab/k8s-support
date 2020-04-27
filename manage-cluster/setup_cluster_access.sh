#!/bin/bash
#
# A small script to assist operators in setting up access to the platform
# cluster in each project from their local machine. Once this script is run on
# an operator's local machine (or any machine, really), each cluster can be
# accessed on an adhoc basis with the following examples.
#
# $ kubectl --context mlab-sandbox get pods -o wide
# $ kubectl --context mlab-staging get nodes
# $ kubectl --context mlab-oti edit ds ndt
#
# Or you can set the current context such that all kubectl commands will use
# that context by default, obviating the need for the --context flag. NOTE:
# when using this method it is not obvious which cluster you are operating
# on, so use caution when making destructive or service-impacting changes.
#
# $ kubectl config get-contexts
# [...]
# $ kubectl config use-context mlab-staging
# $ kubectl get nodes # Lists mlab-staging nodes.

set -euxo pipefail

PROJECTS="mlab-sandbox mlab-staging mlab-oti"
TMP_DIR=$(mktemp --directory)

for project in ${PROJECTS}; do
  kubeconfig="${TMP_DIR}/${project}_admin.confg"
  ca_cert="${TMP_DIR}/${project}_ca.cert"
  user_cert="${TMP_DIR}/${project}_user.cert"
  user_key="${TMP_DIR}/${project}_ca.key"
  api_server=$(kubectl config view --kubeconfig ${kubeconfig} --raw --output \
      jsonpath='{.clusters[?(@.name == "kubernetes")].cluster.server}')

  gsutil cp "gs://k8s-support-${project}/admin.conf" ${kubeconfig}

  kubectl config view --kubeconfig ${kubeconfig} --raw --output \
      jsonpath='{.clusters[?(@.name == "kubernetes")].cluster.certificate-authority-data}' \
      | base64 --decode > ${ca_cert}

  kubectl config view --kubeconfig ${kubeconfig} --raw --output \
      jsonpath='{.users[?(@.name == "kubernetes-admin")].user.client-certificate-data}' \
      | base64 --decode > ${user_cert}

  kubectl config view --kubeconfig ${kubeconfig} --raw --output \
      jsonpath='{.users[?(@.name == "kubernetes-admin")].user.client-key-data}' \
      | base64 --decode > ${user_key}

  kubectl config set-cluster "${project}-cluster" \
      --server ${api_server} \
      --certificate-authority ${ca_cert} \
      --embed-certs=true

  kubectl config set-credentials "${project}-admin" \
      --client-certificate ${user_cert} \
      --client-key ${user_key} \
      --embed-certs=true

  kubectl config set-context ${project} \
      --cluster "${project}-cluster" \
      --user "${project}-admin"
  
done
  
rm -rf ${TMP_DIR}

