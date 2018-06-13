#!/bin/bash

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
chmod a+r summary
