#!/bin/bash
#
# Deploy the NDT-cloud DaemonSet, and all dependencies.

set -uxe

PROJECT=${1:-mlab-sandbox}

# TODO: replace with an allocation of per-user credentials.
gcloud --project ${PROJECT} compute ssh k8s-platform-master \
    --command "sudo cat /etc/kubernetes/admin.conf" > admin.conf

# Report the current daemonsets.
kubectl --kubeconfig ./admin.conf get daemonsets

# TODO: use file names as parameters to the ndt-cloud container.
# Create the ndt certificates secret.
if [[ ! -f certs/cert.pem || ! -f certs/key.pem ]] ; then
    echo "ERROR: could not find measurementlab certs/cert.pem and certs/key.pem files"
	exit 1
fi
kubectl --kubeconfig ./admin.conf create secret generic ndt-certificates \
    "--from-file=certs" \
    --dry-run -o json | kubectl --kubeconfig ./admin.conf apply -f -

if [[ ! -f pusher/pusher-${PROJECT}.json ]] ; then
    echo "ERROR: missing service account credentials for pusher-$PROJECT.json"
	exit 1
fi
kubectl --kubeconfig ./admin.conf create secret generic pusher-credentials \
    --from-file=pusher.json=pusher/pusher-${PROJECT}.json \
    --dry-run -o json | kubectl --kubeconfig ./admin.conf apply -f -


# Create the per-project destination BUCKET name for pusher.
kubectl --kubeconfig ./admin.conf create configmap pusher-dropbox \
    --from-literal=bucket=dropbox-${PROJECT} \
    --dry-run -o json | kubectl --kubeconfig ./admin.conf apply -f -

# Create the ndt-cloud daemonset.
kubectl --kubeconfig ./admin.conf apply \
    -f ../k8s/daemonsets/experiments/ndt-cloud-with-fast-sidestream.yml

# Report the new daemonsets.
kubectl --kubeconfig ./admin.conf get daemonsets
