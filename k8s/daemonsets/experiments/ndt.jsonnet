{
    "apiVersion": "extensions/v1beta1",
    "kind": "DaemonSet",
    "metadata": {
        "name": "ndt",
        "namespace": "default"
    },
    "spec": {
        "selector": {
            "matchLabels": {
                "workload": "ndt"
            }
        },
        "template": {
            "metadata": {
                "annotations": {
                    "k8s.v1.cni.cncf.io/networks": "[{ \"name\": \"index2ip-index-2-conf\" }]",
                    "prometheus.io/scrape": "true",
                    "v1.multus-cni.io/default-network": "flannel-experiment-conf"
                },
                "labels": {
                    "workload": "ndt"
                }
            },
            "spec": {
                "containers": [
                    {
                        "args": [
                            "-key=/certs/key.pem",
                            "-cert=/certs/cert.pem",
                            "-uuid-prefix-file=/var/local/uuid/prefix",
                            "-prometheusx.listen-address=:9090"
                        ],
                        "image": "measurementlab/ndt-server:v0.7.0",
                        "name": "ndt-server",
                        "ports": [
                            {
                                "containerPort": 9090
                            }
                        ],
                        "volumeMounts": [
                            {
                                "mountPath": "/certs",
                                "name": "ndt-tls",
                                "readOnly": true
                            },
                            {
                                "mountPath": "/var/local/uuid",
                                "name": "uuid-prefix",
                                "readOnly": true
                            }
                        ]
                    },
                    {
                        "args": [
                            "-prometheusx.listen-address=:9091",
                            "-output=/var/spool/ndt/tcpinfo",
                            "-uuid-prefix-file=/var/local/uuid/prefix"
                        ],
                        "image": "measurementlab/tcp-info:v0.0.8",
                        "name": "tcpinfo",
                        "ports": [
                            {
                                "containerPort": 9091
                            }
                        ],
                        "volumeMounts": [
                            {
                                "mountPath": "/var/spool/ndt/tcpinfo",
                                "name": "tcpinfo-data"
                            },
                            {
                                "mountPath": "/var/local/uuid",
                                "name": "uuid-prefix",
                                "readOnly": true
                            }
                        ]
                    },
                    {
                        "args": [
                            "-prometheusx.listen-address=:9092",
                            "-outputPath=/var/spool/ndt/traceroute",
                            "-uuid-prefix-file=/var/local/uuid/prefix"
                        ],
                        "image": "measurementlab/traceroute-caller:v0.0.5",
                        "name": "traceroute",
                        "ports": [
                            {
                                "containerPort": 9092
                            }
                        ],
                        "volumeMounts": [
                            {
                                "mountPath": "/var/spool/ndt/traceroute/",
                                "name": "traceroute-data"
                            },
                            {
                                "mountPath": "/var/local/uuid",
                                "name": "uuid-prefix",
                                "readOnly": true
                            }
                        ]
                    },
                    {
                        "args": [
                            "-monitoring_address=:9093",
                            "-experiment=ndt",
                            "-archive_size_threshold=50MB",
                            "-directory=/var/spool/ndt",
                            "-datatype=tcpinfo",
                            "-datatype=traceroute"
                        ],
                        "env": [
                            {
                                "name": "GOOGLE_APPLICATION_CREDENTIALS",
                                "value": "/etc/credentials/pusher.json"
                            },
                            {
                                "name": "BUCKET",
                                "valueFrom": {
                                    "configMapKeyRef": {
                                        "key": "bucket",
                                        "name": "pusher-dropbox"
                                    }
                                }
                            },
                            {
                                "name": "MLAB_NODE_NAME",
                                "valueFrom": {
                                    "fieldRef": {
                                        "fieldPath": "spec.nodeName"
                                    }
                                }
                            }
                        ],
                        "image": "measurementlab/pusher:v1.7",
                        "name": "pusher",
                        "ports": [
                            {
                                "containerPort": 9093
                            }
                        ],
                        "volumeMounts": [
                            {
                                "mountPath": "/var/spool/ndt/tcpinfo",
                                "name": "tcpinfo-data"
                            },
                            {
                                "mountPath": "/var/spool/ndt/traceroute/",
                                "name": "traceroute-data"
                            },
                            {
                                "mountPath": "/etc/credentials",
                                "name": "pusher-credentials",
                                "readOnly": true
                            }
                        ]
                    }
                ],
                "initContainers": [
                    {
                        "command": [
                            "sh",
                            "-c",
                            "echo \"nameserver 8.8.8.8\" > /etc/resolv.conf"
                        ],
                        "image": "busybox",
                        "name": "fix-resolv-conf"
                    },
                    {
                        "args": [
                            "-filename=/var/local/uuid/prefix"
                        ],
                        "image": "measurementlab/uuid:v0.1",
                        "name": "set-up-uuid-prefix-file",
                        "volumeMounts": [
                            {
                                "mountPath": "/var/local/uuid",
                                "name": "uuid-prefix"
                            }
                        ]
                    }
                ],
                "nodeSelector": {
                    "mlab/type": "platform"
                },
                "terminationGracePeriodSeconds": 150,
                "volumes": [
                    {
                        "hostPath": {
                            "path": "/cache/data/ndt/tcpinfo",
                            "type": "DirectoryOrCreate"
                        },
                        "name": "tcpinfo-data"
                    },
                    {
                        "hostPath": {
                            "path": "/cache/data/ndt/traceroute",
                            "type": "DirectoryOrCreate"
                        },
                        "name": "traceroute-data"
                    },
                    {
                        "name": "pusher-credentials",
                        "secret": {
                            "secretName": "pusher-credentials"
                        }
                    },
                    {
                        "name": "ndt-tls",
                        "secret": {
                            "secretName": "ndt-tls"
                        }
                    },
                    {
                        "emptyDir": {},
                        "name": "uuid-prefix"
                    }
                ]
            }
        },
        "updateStrategy": {
            "rollingUpdate": {
                "maxUnavailable": 2
            },
            "type": "RollingUpdate"
        }
    }
}
