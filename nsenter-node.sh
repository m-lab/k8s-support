#!/bin/bash
set -x

node=${1}
nodeName=$(kubectl --context mlab-sandbox get node ${node} -o template --template='{{index .metadata.labels "kubernetes.io/hostname"}}') 
nodeSelector='"nodeSelector": { "kubernetes.io/hostname": "'${nodeName:?}'" },'
podName=nsenter-${node}

kubectl --context mlab-sandbox run ${podName:?} --restart=Never -it --rm --image overriden --overrides '
{
    "spec": {
        "hostPID": true,
            "hostNetwork": true,
                '"${nodeSelector?}"'
                    "tolerations": [{
                            "operator": "Exists"
                                }],
                                    "containers": [
                                          {
                                                    "name": "nsenter",
                                                            "image": "alexeiled/nsenter:2.34",
                                                                    "command": [
                                                                              "/nsenter", "--all", "--target=1", "--", "su", "-"
                                                                                      ],
                                                                                              "stdin": true,
                                                                                                      "tty": true,
                                                                                                              "securityContext": {
                                                                                                                        "privileged": true
                                                                                                                                }
                                                                                                                                      }
                                                                                                                                          ]
                                                                                                                                            }
                                                                                                                                          }' --attach "$@"
