{
    "apiVersion": "apps/v1",
    "kind": "Deployment",
    "metadata": {
        "name": "prometheus-server"
    },
    "spec": {
        "replicas": 1,
        "selector": {
            "matchLabels": {
                "workload": "prometheus-server"
            }
        },
        "strategy": {
            "type": "Recreate"
        },
        "template": {
            "metadata": {
                "annotations": {
                    "prometheus.io/scrape": "true"
                },
                "labels": {
                    "workload": "prometheus-server"
                }
            },
            "spec": {
                "containers": [
                    {
                        "args": [
                            "--config.file=/etc/prometheus/prometheus.yml",
                            "--storage.tsdb.path=/prometheus",
                            "--web.enable-lifecycle"
                        ],
                        "image": "prom/prometheus:v2.4.2",
                        "name": "prometheus",
                        "ports": [
                            {
                                "containerPort": 9090
                            }
                        ],
                        "volumeMounts": [
                            {
                                "mountPath": "/etc/prometheus/",
                                "name": "prometheus-config"
                            },
                            {
                                "mountPath": "/prometheus",
                                "name": "prometheus-storage"
                            },
                            {
                                "mountPath": "/etc/prometheus/tls/",
                                "name": "etcd-tls"
                            }
                        ]
                    },
                    {
                        "args": [
                            "-webhook-url",
                            "http://localhost:9090/-/reload",
                            "-volume-dir",
                            "/etc/prometheus"
                        ],
                        "image": "jimmidyson/configmap-reload:v0.2.2",
                        "name": "configmap-reload",
                        "resources": {
                            "limits": {
                                "cpu": "200m",
                                "memory": "400Mi"
                            },
                            "requests": {
                                "cpu": "200m",
                                "memory": "400Mi"
                            }
                        },
                        "volumeMounts": [
                            {
                                "mountPath": "/etc/prometheus",
                                "name": "prometheus-config"
                            }
                        ]
                    }
                ],
                "hostNetwork": true,
                "nodeSelector": {
                    "mlab/type": "cloud",
                    "run": "prometheus-server"
                },
                "serviceAccountName": "prometheus",
                "volumes": [
                    {
                        "configMap": {
                            "name": "prometheus-config"
                        },
                        "name": "prometheus-config"
                    },
                    {
                        "hostPath": {
                            "path": "/mnt/local/prometheus",
                            "type": "Directory"
                        },
                        "name": "prometheus-storage"
                    },
                    {
                        "name": "etcd-tls",
                        "secret": {
                            "secretName": "etcd-tls"
                        }
                    }
                ]
            }
        }
    }
}
