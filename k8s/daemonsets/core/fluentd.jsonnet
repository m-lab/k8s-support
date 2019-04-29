{
    "apiVersion": "apps/v1",
    "kind": "DaemonSet",
    "metadata": {
        "labels": {
            "addonmanager.kubernetes.io/mode": "Reconcile",
            "kubernetes.io/cluster-service": "true",
            "version": "v2.0"
        },
        "name": "fluentd"
    },
    "spec": {
        "selector": {
            "matchLabels": {
                "kubernetes.io/cluster-service": "true",
                "version": "v2.0",
                "workload": "fluentd"
            }
        },
        "template": {
            "metadata": {
                "annotations": {
                    "prometheus.io/scrape": "true",
                    "scheduler.alpha.kubernetes.io/critical-pod": ""
                },
                "labels": {
                    "kubernetes.io/cluster-service": "true",
                    "version": "v2.0",
                    "workload": "fluentd"
                }
            },
            "spec": {
                "containers": [
                    {
                        "command": [
                            "/bin/sh",
                            "-c",
                            "mkdir /etc/fluent/config.d && cp /config/* /etc/fluent/config.d/ && sed -i \"s/NODE_HOSTNAME/$NODE_HOSTNAME/\" /etc/fluent/config.d/output.conf && /run.sh $FLUENTD_ARGS"
                        ],
                        "env": [
                            {
                                "name": "FLUENTD_ARGS",
                                "value": "--no-supervisor"
                            },
                            {
                                "name": "GOOGLE_APPLICATION_CREDENTIALS",
                                "value": "/etc/fluent/keys/fluentd.json"
                            },
                            {
                                "name": "NODE_HOSTNAME",
                                "valueFrom": {
                                    "fieldRef": {
                                        "fieldPath": "spec.nodeName"
                                    }
                                }
                            }
                        ],
                        "image": "k8s.gcr.io/fluentd-gcp:2.0.2",
                        "name": "fluentd",
                        "ports": [
                            {
                                "containerPort": 9900,
                                "name": "scrape",
                                "protocol": "TCP"
                            }
                        ],
                        "resources": {
                            "limits": {
                                "memory": "800Mi"
                            },
                            "requests": {
                                "cpu": "100m",
                                "memory": "200Mi"
                            }
                        },
                        "volumeMounts": [
                            {
                                "mountPath": "/var/log",
                                "name": "varlog"
                            },
                            {
                                "mountPath": "/var/lib/docker/containers",
                                "name": "varlibdockercontainers",
                                "readOnly": true
                            },
                            {
                                "mountPath": "/cache/docker",
                                "name": "cachedocker"
                            },
                            {
                                "mountPath": "/host/lib",
                                "name": "libsystemddir",
                                "readOnly": true
                            },
                            {
                                "mountPath": "/config",
                                "name": "config-volume"
                            },
                            {
                                "mountPath": "/etc/fluent/keys",
                                "name": "credentials",
                                "readOnly": true
                            }
                        ]
                    }
                ],
                "dnsPolicy": "Default",
                "terminationGracePeriodSeconds": 30,
                "tolerations": [
                    {
                        "effect": "NoSchedule",
                        "key": "node.alpha.kubernetes.io/ismaster"
                    },
                    {
                        "effect": "NoSchedule",
                        "key": "node-role.kubernetes.io/master"
                    }
                ],
                "volumes": [
                    {
                        "hostPath": {
                            "path": "/var/log"
                        },
                        "name": "varlog"
                    },
                    {
                        "hostPath": {
                            "path": "/var/lib/docker/containers"
                        },
                        "name": "varlibdockercontainers"
                    },
                    {
                        "hostPath": {
                            "path": "/cache/docker"
                        },
                        "name": "cachedocker"
                    },
                    {
                        "hostPath": {
                            "path": "/usr/lib64"
                        },
                        "name": "libsystemddir"
                    },
                    {
                        "configMap": {
                            "name": "fluentd-config"
                        },
                        "name": "config-volume"
                    },
                    {
                        "name": "credentials",
                        "secret": {
                            "secretName": "fluentd-credentials"
                        }
                    }
                ]
            }
        },
        "updateStrategy": {
            "type": "RollingUpdate"
        }
    }
}
