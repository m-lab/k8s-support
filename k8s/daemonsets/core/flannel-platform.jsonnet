{
    "apiVersion": "extensions/v1beta1",
    "kind": "DaemonSet",
    "metadata": {
        "labels": {
            "app": "flannel",
            "tier": "node"
        },
        "name": "kube-flannel-ds-platform",
        "namespace": "kube-system"
    },
    "spec": {
        "template": {
            "metadata": {
                "labels": {
                    "app": "flannel",
                    "tier": "node"
                }
            },
            "spec": {
                "containers": [
                    {
                        "args": [
                            "--ip-masq",
                            "--kube-subnet-mgr"
                        ],
                        "command": [
                            "/opt/bin/flanneld"
                        ],
                        "env": [
                            {
                                "name": "POD_NAME",
                                "valueFrom": {
                                    "fieldRef": {
                                        "fieldPath": "metadata.name"
                                    }
                                }
                            },
                            {
                                "name": "POD_NAMESPACE",
                                "valueFrom": {
                                    "fieldRef": {
                                        "fieldPath": "metadata.namespace"
                                    }
                                }
                            }
                        ],
                        "image": "quay.io/coreos/flannel:"+ std.extVar('K8S_FLANNEL_VERSION') +"-amd64",
                        "name": "kube-flannel",
                        "resources": {
                            "limits": {
                                "cpu": "100m",
                                "memory": "128Mi"
                            },
                            "requests": {
                                "cpu": "100m",
                                "memory": "128Mi"
                            }
                        },
                        "securityContext": {
                            "privileged": true
                        },
                        "volumeMounts": [
                            {
                                "mountPath": "/run",
                                "name": "run"
                            },
                            {
                                "mountPath": "/etc/kube-flannel/",
                                "name": "flannel-cfg"
                            }
                        ]
                    }
                ],
                "hostNetwork": true,
                "initContainers": [
                    {
                        "args": [
                            "-f",
                            "/etc/kube-flannel/platform-node-cni-conf.json",
                            "/etc/cni/net.d/multus-cni.conf"
                        ],
                        "command": [
                            "cp"
                        ],
                        "image": "quay.io/coreos/flannel:"+ std.extVar('K8S_FLANNEL_VERSION') +"-amd64",
                        "name": "install-cni",
                        "volumeMounts": [
                            {
                                "mountPath": "/etc/cni/net.d",
                                "name": "cni"
                            },
                            {
                                "mountPath": "/etc/kube-flannel/",
                                "name": "flannel-cfg"
                            }
                        ]
                    }
                ],
                "nodeSelector": {
                    "beta.kubernetes.io/arch": "amd64",
                    "mlab/type": "platform"
                },
                "serviceAccountName": "flannel",
                "tolerations": [
                    {
                        "effect": "NoSchedule",
                        "operator": "Exists"
                    }
                ],
                "volumes": [
                    {
                        "hostPath": {
                            "path": "/run"
                        },
                        "name": "run"
                    },
                    {
                        "hostPath": {
                            "path": "/etc/cni/net.d"
                        },
                        "name": "cni"
                    },
                    {
                        "configMap": {
                            "name": "kube-flannel-cfg"
                        },
                        "name": "flannel-cfg"
                    }
                ]
            }
        },
        "updateStrategy": {
            "type": "RollingUpdate"
        }
    }
}
