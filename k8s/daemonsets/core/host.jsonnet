{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: 'host',
  },
  spec: {
    selector: {
      matchLabels: {
        workload: 'host',
      },
    },
    template: {
      metadata: {
        annotations: {
          'prometheus.io/scrape': 'true',
        },
        labels: {
          workload: 'host',
        },
      },
      spec: {
        containers: [
          {
            args: [
              '-datadir=/var/spool/nodeinfo',
              '-wait=1h',
              '-prometheusx.listen-address=127.0.0.1:9990',
              '-config=/etc/nodeinfo/config.json',
            ],
            image: 'measurementlab/nodeinfo:v1.2',
            name: 'nodeinfo',
            volumeMounts: [
              {
                mountPath: '/etc/nodeinfo',
                name: 'nodeinfo-config',
              },
              {
                mountPath: '/var/spool/nodeinfo',
                name: 'nodeinfo-data',
              },
            ],
          },
          {
            args: [
              '--logtostderr',
              '--secure-listen-address=$(IP):9990',
              '--upstream=http://127.0.0.1:9990/',
            ],
            env: [
              {
                name: 'IP',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'status.podIP',
                  },
                },
              },
            ],
            image: 'quay.io/coreos/kube-rbac-proxy:v0.4.1',
            name: 'kube-rbac-proxy-nodeinfo',
            ports: [
              {
                containerPort: 9990,
                hostPort: 9990,
              },
            ],
          },
          {
            args: [
              '-prometheusx.listen-address=127.0.0.1:9991',
              '-sigterm_wait_time=20s',
              '-experiment=host',
              '-archive_size_threshold=50MB',
              '-directory=/var/spool/host',
              '-datatype=biosversion',
              '-datatype=chassisserial',
              '-datatype=ipaddress',
              '-datatype=iproute4',
              '-datatype=iproute6',
              '-datatype=lshw',
              '-datatype=lspci',
              '-datatype=lsusb',
              '-datatype=osrelease',
              '-datatype=tcpinfo',
              '-datatype=traceroute',
              '-datatype=uname',
            ],
            env: [
              {
                name: 'GOOGLE_APPLICATION_CREDENTIALS',
                value: '/etc/credentials/pusher.json',
              },
              {
                name: 'BUCKET',
                valueFrom: {
                  configMapKeyRef: {
                    key: 'bucket',
                    name: 'pusher-dropbox',
                  },
                },
              },
              {
                name: 'MLAB_NODE_NAME',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'spec.nodeName',
                  },
                },
              },
            ],
            image: 'measurementlab/pusher:v1.8',
            name: 'pusher',
            volumeMounts: [
              {
                mountPath: '/var/spool/host',
                name: 'nodeinfo-data',
              },
              {
                mountPath: '/var/spool/host/tcpinfo',
                name: 'tcpinfo-data',
              },
              {
                mountPath: '/var/spool/host/traceroute',
                name: 'traceroute-data',
              },
              {
                mountPath: '/etc/credentials',
                name: 'pusher-credentials',
                readOnly: true,
              },
            ],
          },
          {
            args: [
              '--logtostderr',
              '--secure-listen-address=$(IP):9991',
              '--upstream=http://127.0.0.1:9991/',
            ],
            env: [
              {
                name: 'IP',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'status.podIP',
                  },
                },
              },
            ],
            image: 'quay.io/coreos/kube-rbac-proxy:v0.4.1',
            name: 'kube-rbac-proxy-pusher',
            ports: [
              {
                containerPort: 9991,
                hostPort: 9991,
              },
            ],
          },
          {
            name: 'tcpinfo',
            image: 'measurementlab/tcp-info:v0.0.8',
            args: [
              '-prometheusx.listen-address=127.0.0.1:9091',
              '-output=/var/spool/host/tcpinfo',
              '-uuid-prefix-file=/var/local/uuid/prefix',
            ],
            volumeMounts: [
              {
                mountPath: '/var/spool/host/tcpinfo',
                name: 'tcpinfo-data',
              },
              {
                mountPath: '/var/local/uuid',
                name: 'uuid-prefix',
                readOnly: true,
              },
            ],
          },
          {
            args: [
              '--logtostderr',
              '--secure-listen-address=$(IP):9091',
              '--upstream=http://127.0.0.1:9091/',
            ],
            env: [
              {
                name: 'IP',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'status.podIP',
                  },
                },
              },
            ],
            image: 'quay.io/coreos/kube-rbac-proxy:v0.4.1',
            name: 'kube-rbac-proxy-tcpinfo',
            ports: [
              {
                containerPort: 9091,
                hostPort: 9091,
              },
            ],
          },
          {
            name: 'traceroute',
            image: 'measurementlab/traceroute-caller:v0.0.5',
            args: [
              '-prometheusx.listen-address=127.0.0.1:9092',
              '-outputPath=/var/spool/host/traceroute',
              '-uuid-prefix-file=/var/local/uuid/prefix',
            ],
            volumeMounts: [
              {
                mountPath: '/var/spool/host/traceroute',
                name: 'traceroute-data',
              },
              {
                mountPath: '/var/local/uuid',
                name: 'uuid-prefix',
                readOnly: true,
              },
            ],
          },
          {
            args: [
              '--logtostderr',
              '--secure-listen-address=$(IP):9092',
              '--upstream=http://127.0.0.1:9092/',
            ],
            env: [
              {
                name: 'IP',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'status.podIP',
                  },
                },
              },
            ],
            image: 'quay.io/coreos/kube-rbac-proxy:v0.4.1',
            name: 'kube-rbac-proxy-traceroute',
            ports: [
              {
                containerPort: 9092,
                hostPort: 9092,
              },
            ],
          },
        ],
        initContainers: [
          // Write out the UUID prefix to a well-known location. For
          // more on this, see DESIGN.md in
          // https://github.com/m-lab/uuid/
          {
            name: 'set-up-uuid-prefix-file',
            image: 'measurementlab/uuid:v0.1',
            args: [
              '-filename=/var/local/uuid/prefix',
            ],
            volumeMounts: [
              {
                mountPath: '/var/local/uuid',
                name: 'uuid-prefix',
              },
            ],
          },
        ],
        hostNetwork: true,
        hostPID: true,
        nodeSelector: {
          'mlab/type': 'platform',
        },
        serviceAccountName: 'kube-rbac-proxy',
        volumes: [
          {
            configMap: {
              name: 'nodeinfo-config',
            },
            name: 'nodeinfo-config',
          },
          {
            hostPath: {
              path: '/cache/data/host/nodeinfo',
              type: 'DirectoryOrCreate',
            },
            name: 'nodeinfo-data',
          },
          {
            hostPath: {
              path: '/cache/data/host/tcpinfo',
              type: 'DirectoryOrCreate',
            },
            name: 'tcpinfo-data',
          },
          {
            hostPath: {
              path: '/cache/data/host/traceroute',
              type: 'DirectoryOrCreate',
            },
            name: 'traceroute-data',
          },
          {
            name: 'pusher-credentials',
            secret: {
              secretName: 'pusher-credentials',
            },
          },
          {
            emptyDir: {},
            name: 'uuid-prefix',
          },
        ],
      },
    },
    updateStrategy: {
      type: 'RollingUpdate',
    },
  },
}
