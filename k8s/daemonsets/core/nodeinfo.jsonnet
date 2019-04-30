{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: 'nodeinfo',
  },
  spec: {
    selector: {
      matchLabels: {
        workload: 'nodeinfo',
      },
    },
    template: {
      metadata: {
        annotations: {
          'prometheus.io/scrape': 'true',
        },
        labels: {
          workload: 'nodeinfo',
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
              '-experiment=nodeinfo',
              '-archive_size_threshold=50MB',
              '-directory=/var/spool/nodeinfo',
              '-datatype=lshw',
              '-datatype=lspci',
              '-datatype=lsusb',
              '-datatype=ipaddress',
              '-datatype=iproute4',
              '-datatype=iproute6',
              '-datatype=uname',
              '-datatype=osrelease',
              '-datatype=biosversion',
              '-datatype=chassisserial',
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
                mountPath: '/var/spool/nodeinfo',
                name: 'nodeinfo-data',
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
              path: '/cache/data/node/nodeinfo',
              type: 'DirectoryOrCreate',
            },
            name: 'nodeinfo-data',
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
