#!/bin/bash

# This program acts as a shim between real CNI plugins (as stored in
# /opt/cni/bin) and the system which calls those plugins.  It is used by putting
# it in a directory (e.g. /opt/shimcni/bin) and then symlinking this script to
# the name of every CNI plugin you want to create a shim for.  e.g.
#   for i in /opt/cni/bin/*; do
#     ln -s /opt/shimcni/bin/shim.sh /opt/shimcni/bin/$(basename "$i")
#   done
#
# Then, whenever one of the files in /opt/shimcni/bin is invoked, a new
# directory will appear in /tmp containing all the parameters required to invoke
# that plugin again (the cmdline, env, stdin) as well as all the output that the
# plugin produced (stdout, stderr, and the exit code).
#
# The hope is that, with this information, it will become easier to debug CNI
# networking problems.

OUTPUT=$(mktemp -d --tmpdir=/tmp "$(date -Iseconds).$(basename $0).XXXXXXX")
echo "$0" "$@" > "${OUTPUT}/cmdline"
env > "${OUTPUT}/env"
cat - \
  | tee "${OUTPUT}/input" \
  | (/opt/cni/bin/$(basename "$0") "$@" 2> "${OUTPUT}/stderr";
     echo $? > "${OUTPUT}/exitcode") \
  | tee "${OUTPUT}/output"
cd "${OUTPUT}" || exit 1
cat \
    <(echo "==CMD==") \
    cmdline \
    <(echo "==ENV==") \
    env \
    <(echo "==STDIN==") \
    input \
    <(echo "==STDOUT==") \
    output \
    <(echo "==STDERR==") \
    stderr \
    <(echo "==EXITCODE==") \
    exitcode \
  > summary
chmod a+rx "${OUTPUT}"
chmod a+r "${OUTPUT}"/*
