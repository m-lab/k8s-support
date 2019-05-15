{
  apiVersion: 'extensions/v1beta1',
  kind: 'DaemonSet',
  metadata: {
    name: 'ndt',
    namespace: 'default',
  },
  spec: {
    selector: {
      matchLabels: {
        workload: 'ndt',
      },
    },
    template: {
      metadata: {
        annotations: {
          'k8s.v1.cni.cncf.io/networks': '[{ "name": "index2ip-index-2-conf" }]',
          'prometheus.io/scrape': 'true',
          'v1.multus-cni.io/default-network': 'flannel-experiment-conf',
        },
        labels: {
          workload: 'ndt',
        },
      },
      spec: {
        containers: [
          {
            name: 'ndt-server',
            image: 'measurementlab/ndt-server:v0.8.2',
            args: [
              '-key=/certs/key.pem',
              '-cert=/certs/cert.pem',
              '-uuid-prefix-file=/var/local/uuid/prefix',
              '-prometheusx.listen-address=:9090',
              '-datadir=/var/spool/ndt',
            ],
            ports: [
              {
                containerPort: 9090,
              },
            ],
            volumeMounts: [
              {
                mountPath: '/certs',
                name: 'ndt-tls',
                readOnly: true,
              },
              {
                mountPath: '/var/local/uuid',
                name: 'uuid-prefix',
                readOnly: true,
              },
              {
                mountPath: '/var/spool/ndt/legacy',
                name: 'legacy-data',
              },
              {
                mountPath: '/var/spool/ndt/ndt7',
                name: 'ndt7-data',
              },
            ],
          },
          {
            name: 'tcpinfo',
            image: 'measurementlab/tcp-info:v0.0.8',
            args: [
              '-prometheusx.listen-address=:9091',
              '-output=/var/spool/ndt/tcpinfo',
              '-uuid-prefix-file=/var/local/uuid/prefix',
            ],
            ports: [
              {
                containerPort: 9091,
              },
            ],
            volumeMounts: [
              {
                mountPath: '/var/spool/ndt/tcpinfo',
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
              '-outputPath=/var/spool/ndt/traceroute',
              '-uuid-prefix-file=/var/local/uuid/prefix',
            ],
            ports: [
              {
                containerPort: 9092,
              },
            ],
            volumeMounts: [
              {
                mountPath: '/var/spool/ndt/traceroute',
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
              '-experiment=ndt',
              '-archive_size_threshold=50MB',
              '-directory=/var/spool/ndt',
              '-datatype=tcpinfo',
              '-datatype=traceroute',
              '-datatype=legacy',
              '-datatype=ndt7',
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
                mountPath: '/var/spool/ndt/traceroute',
                name: 'traceroute-data',
              },
              {
                mountPath: '/var/spool/ndt/tcpinfo',
                name: 'tcpinfo-data',
              },
              {
                mountPath: '/var/spool/ndt/legacy',
                name: 'legacy-data',
              },
              {
                mountPath: '/var/spool/ndt/ndt7',
                name: 'ndt7-data',
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
        // The default grace period after k8s sends SIGTERM is 30s. We
        // extend the grace period to give time for the following
        // shutdown sequence. After the grace period, kubernetes sends
        // SIGKILL.
        //
        // NDT pod shutdown sequence:
        //
        //  * k8s sends SIGTERM to NDT server
        //  * NDT server enables lame duck status
        //  * monitoring reads lame duck status (60s max)
        //  * mlab-ns updates server status (60s max)
        //  * all currently running tests complete. (30s max)
        //
        // Feel free to change this to a smaller value for speedy
        // sandbox deployments to enable faster compile-run-debug loops,
        // but 60+60+30=150 is what it needs to be for staging and prod.
        terminationGracePeriodSeconds: 150,
        volumes: [
          {
            hostPath: {
              path: '/cache/data/ndt/traceroute',
              type: 'DirectoryOrCreate',
            },
            name: 'traceroute-data',
          },
          {
            hostPath: {
              path: '/cache/data/ndt/tcpinfo',
              type: 'DirectoryOrCreate',
            },
            name: 'tcpinfo-data',
          },
          {
            hostPath: {
              path: '/cache/data/ndt/legacy',
              type: 'DirectoryOrCreate',
            },
            name: 'legacy-data',
          },
          {
            hostPath: {
              path: '/cache/data/ndt/ndt7',
              type: 'DirectoryOrCreate',
            },
            name: 'ndt7-data',
          },
          {
            name: 'pusher-credentials',
            secret: {
              secretName: 'pusher-credentials',
            },
          },
          {
            name: 'ndt-tls',
            secret: {
              secretName: 'ndt-tls',
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
