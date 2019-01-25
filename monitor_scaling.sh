#!/bin/bash

KUBECTL_ARGS="--kubeconfig ./kube-config"

# Get the count of mlab4 nodes. Each of these nodes should have a pod scheduled
# on them, so the running number of pods for given daemonset should match this
# number once that daemonset is fully deployed.
MLAB4_COUNT=$(kubectl $KUBECTL_ARGS get nodes | grep mlab4 | wc -l)
echo "mlab4 nodes attached to cluster: ${MLAB4_COUNT}"

#
# Add the ndt-server Daemonset
#
kubectl $KUBECTL_ARGS apply -f ./k8s/daemonsets/experiments/ndt-server-with-fast-sidestream.yml > /dev/null
echo "Add ndt-server DaemonSet command returned: ${SECONDS}s"

while true; do
  POD_COUNT=$(kubectl $KUBECTL_ARGS get pods | grep ndt-server | grep Running | wc -l)
  if [[ "${POD_COUNT}" -eq "${MLAB4_COUNT}" ]]; then
    break
  fi
done
echo "All ndt-server pods running: ${SECONDS}s"

# Reset the built-in bash variable SECONDS to zero, so we can restart timing for
# the next operation.
SECONDS=0

#
# Delete the ndt-server DaemonSet
#
kubectl $KUBECTL_ARGS delete daemonset ndt-server > /dev/null
echo "Delete ndt-server DaemonSet command returned: ${SECONDS}s"

while true; do
  POD_COUNT=$(kubectl $KUBECTL_ARGS get pods | grep ndt-server | wc -l)
  if [[ "${POD_COUNT}" -eq "0" ]]; then
    break
  fi
done
echo "All ndt-server pods removed: ${SECONDS}s"
