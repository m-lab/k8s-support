{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: 'bismark',
    namespace: 'default',
  },
  spec: {
    selector: {
      matchLabels: {
        workload: 'bismark',
      },
    },
    template: {
      metadata: {
        annotations: {
          'k8s.v1.cni.cncf.io/networks': '[{ "name": "index2ip-index-9-conf" }]',
          'prometheus.io/scrape': 'true',
          'v1.multus-cni.io/default-network': 'flannel-experiment-conf',
        },
        labels: {
          workload: 'bismark',
        },
      },
      spec: {
        containers: [
          {
            name: 'bismark',
            image: 'measurementlab/bismark-test:v1.0.0',
            ports: [
              {
                containerPort: 9090,
              },
            ],
            volumeMounts: [
              {
                mountPath: '/var/local/uuid',
                name: 'uuid-prefix',
                readOnly: true,
              },
            ],
          },
          {
            name: 'tcpinfo',
            image: 'measurementlab/tcp-info:v0.0.8',
            args: [
              '-prometheusx.listen-address=:9091',
              '-output=/var/spool/bismark/tcpinfo',
              '-uuid-prefix-file=/var/local/uuid/prefix',
            ],
            ports: [
              {
                containerPort: 9091,
              },
            ],
            volumeMounts: [
              {
                mountPath: '/var/spool/bismark/tcpinfo',
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
            name: 'traceroute',
            image: 'measurementlab/traceroute-caller:v0.0.5',
            args: [
              '-prometheusx.listen-address=:9092',
              '-outputPath=/var/spool/bismark/traceroute',
              '-uuid-prefix-file=/var/local/uuid/prefix',
            ],
            ports: [
              {
                containerPort: 9092,
              },
            ],
            volumeMounts: [
              {
                mountPath: '/var/spool/bismark/traceroute',
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
            name: 'pusher',
            image: 'measurementlab/pusher:v1.8',
            args: [
              '-prometheusx.listen-address=:9093',
              '-experiment=bismark',
              '-archive_size_threshold=50MB',
              '-directory=/var/spool/bismark',
              '-datatype=tcpinfo',
              '-datatype=traceroute',
              '-datatype=legacy',
              '-datatype=bismark',
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
            ports: [
              {
                containerPort: 9093,
              },
            ],
            volumeMounts: [
              {
                mountPath: '/var/spool/bismark/traceroute',
                name: 'traceroute-data',
              },
              {
                mountPath: '/var/spool/bismark/tcpinfo',
                name: 'tcpinfo-data',
              },
              {
                mountPath: '/var/spool/bismark/legacy',
                name: 'legacy-data',
              },
              {
                mountPath: '/etc/credentials',
                name: 'pusher-credentials',
                readOnly: true,
              },
            ],
          },
        ],
        initContainers: [
          // TODO: this is a hack. Remove the hack by fixing the
          // contents of resolv.conf
          {
            name: 'fix-resolv-conf',
            image: 'busybox',
            command: [
              'sh',
              '-c',
              'echo "nameserver 8.8.8.8" > /etc/resolv.conf',
            ],
          },
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
        nodeSelector: {
          'mlab/type': 'platform',
        },
        volumes: [
          {
            hostPath: {
              path: '/cache/data/bismark/traceroute',
              type: 'DirectoryOrCreate',
            },
            name: 'traceroute-data',
          },
          {
            hostPath: {
              path: '/cache/data/bismark/tcpinfo',
              type: 'DirectoryOrCreate',
            },
            name: 'tcpinfo-data',
          },
          {
            hostPath: {
              path: '/cache/data/bismark/legacy',
              type: 'DirectoryOrCreate',
            },
            name: 'legacy-data',
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
      rollingUpdate: {
        maxUnavailable: 2,
      },
      type: 'RollingUpdate',
    },
  },
}
