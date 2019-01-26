#!/bin/bash

# This is a small script which runs a few opertions on the M-Lab k8s platform
# cluster which we expect to be relatively common. It measures how long it takes
# each operation to complete, and constitutes a very, very basic measure of how
# these operations will scale (in terms of time) as the number of globally
# distributed nodes increases.
#
# This script makes use of the bash built-in variable $SECONDS to track how long
# operations take to complete. It only measures to the nearest second, so
# operations that take less than a second to complete may register that they
# took 0 seconds. It is just a very rough measurement, but good enough for this
# purpose.

# NOTE: This script requires that you have a valid kubeconfig file for the
# cluster in the same directory as this script.
KUBECTL_ARGS="--kubeconfig ./kube-config"

# The node on which to run the kubectl-exec command.
KUBECTL_EXEC_NODE="mlab4.bru02"

# Get the count of mlab4 nodes. Each of these nodes should have a pod scheduled
# on them, so the running number of pods for a given daemonset should match this
# number once that daemonset is fully deployed.
MLAB4_COUNT=$(kubectl $KUBECTL_ARGS get nodes | grep mlab4 | wc -l)
echo "mlab4 count: ${MLAB4_COUNT}"

#
# Delete the ndt-server DaemonSet.
#
# Reset the built-in bash variable SECONDS.
SECONDS=0

echo -n "Deleted ndt DaemonSet in: "
kubectl $KUBECTL_ARGS delete daemonset ndt > /dev/null
DEL_CMD_SECS="${SECONDS}"
echo "${DEL_CMD_SECS}"

echo -n "All pods gone in: "
while true; do
  POD_COUNT=$(kubectl $KUBECTL_ARGS get pods | grep ndt | wc -l)
  if [[ "${POD_COUNT}" -eq "0" ]]; then
    break
  fi
  # Loosen the loop just a tiny bit.
  sleep 1
done
DEL_DONE_SECS="${SECONDS}"
echo "${DEL_DONE_SECS}"


#
# Create the ndt Daemonset
#
# Reset the built-in bash variable SECONDS.
SECONDS=0

echo -n "Created ndt DaemonSet in: "
kubectl $KUBECTL_ARGS apply -f \
    ./k8s/daemonsets/experiments/ndt.yml > /dev/null
APPLY_CMD_SECS="${SECONDS}"
echo "${APPLY_CMD_SECS}"

echo -n "All pods in Running state in: "
while true; do
  POD_COUNT=$(kubectl $KUBECTL_ARGS get pods | grep ndt | \
      grep Running | wc -l)
  if [[ "${POD_COUNT}" -eq "${MLAB4_COUNT}" ]]; then
    break
  fi
  # Loosen the loop just a tiny bit.
  sleep 1
done
APPLY_RUNNING_SECS="${SECONDS}"
echo "${APPLY_RUNNING_SECS}"

#
# Time basic kubectl-exec command to a specific ndt pod.
#
KUBECTL_EXEC_POD=$(kubectl $KUBECTL_ARGS get pods -o wide | grep ndt | \
    grep $KUBECTL_EXEC_NODE | awk '{print $1}')

# Reset the built-in bash variable SECONDS.
SECONDS=0

echo -n "Ran kubectl-exec on ndt pod on ${KUBECTL_EXEC_NODE} in: "
kubectl $KUBECTL_ARGS exec $KUBECTL_EXEC_POD -c ndt-server /bin/ls > /dev/null
KUBECTL_EXEC_SECS="${SECONDS}"
echo "${KUBECTL_EXEC_SECS}"

echo -e "\nmlab4_cnt, delete_cmd, delete_done, apply_cmd, apply_running," \
        "kubectl_exec"
echo "${MLAB4_COUNT}, ${DEL_CMD_SECS}, ${DEL_DONE_SECS}, ${APPLY_CMD_SECS}," \
     "${APPLY_RUNNING_SECS}, ${KUBECTL_EXEC_SECS}"
