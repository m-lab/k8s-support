{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: 'node-exporter',
  },
  spec: {
    selector: {
      matchLabels: {
        workload: 'node-exporter',
      },
    },
    template: {
      metadata: {
        annotations: {
          'prometheus.io/scrape': 'true',
          'prometheus.io/scheme': 'https',
        },
        labels: {
          workload: 'node-exporter',
        },
      },
      spec: {
        initContainers: [
          // Pass dot to the datatypes param. node-exporter doesn't have
          // datatypes. Dot will result in "mkdir -p .", which is a no-op.
          exp.setDataDirOwnership('node-exporter', ['.']).initContainer,
        ],
        containers: [
          {
            args: [
              '--collector.disable-defaults',
              '--collector.cpu',
              '--collector.diskstats',
              '--collector.edac',
              '--collector.filesystem',
              '--collector.hwmon',
              '--collector.loadavg',
              '--collector.meminfo',
              '--collector.netdev',
              '--collector.processes',
              '--collector.stat',
              '--collector.textfile',
              '--collector.textfile.directory=/var/spool/node-exporter',
              '--path.procfs=/host/proc',
              '--path.rootfs=/host/root',
              '--path.sysfs=/host/sys',
              '--web.listen-address=127.0.0.1:9100',
            ],
            image: 'prom/node-exporter:v1.3.1',
            name: 'node-exporter',
            resources: {
              limits: {
                cpu: '250m',
                memory: '180Mi',
              },
              requests: {
                cpu: '102m',
                memory: '180Mi',
              },
            },
            volumeMounts: [
              {
                mountPath: '/host/proc',
                name: 'proc',
                readOnly: false,
              },
              {
                mountPath: '/host/sys',
                name: 'sys',
                readOnly: false,
              },
              {
                mountPath: '/host/root',
                mountPropagation: 'HostToContainer',
                name: 'root',
                readOnly: true,
              },
              {
                mountPath: '/var/spool/node-exporter',
                name: 'node-exporter-data',
                readOnly: false,
              },
              {
                mountPath: '/var/run/dbus/system_bus_socket',
                name: 'dbus-socket',
              },
            ],
          },
          {
            args: [
              '--logtostderr',
              '--secure-listen-address=$(IP):9100',
              '--upstream=http://127.0.0.1:9100/',
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
            image: 'quay.io/brancz/kube-rbac-proxy:v0.11.0',
            name: 'kube-rbac-proxy',
            ports: [
              {
                containerPort: 9100,
                hostPort: 9100,
              },
            ],
            resources: {
              limits: {
                cpu: '20m',
                memory: '40Mi',
              },
              requests: {
                cpu: '10m',
                memory: '20Mi',
              },
            },
          },
        ],
        hostNetwork: true,
        hostPID: true,
        serviceAccountName: 'kube-rbac-proxy',
        tolerations: [
          {
            effect: 'NoSchedule',
            key: 'lame-duck',
            operator: 'Exists',
          },
          {
            effect: 'NoSchedule',
            key: 'node-role.kubernetes.io/master',
          },
          {
            effect: 'NoSchedule',
            key: 'node-role.kubernetes.io/control-plane',
          },
        ],
        volumes: [
          {
            hostPath: {
              path: '/proc',
            },
            name: 'proc',
          },
          {
            hostPath: {
              path: '/sys',
            },
            name: 'sys',
          },
          {
            hostPath: {
              path: '/',
            },
            name: 'root',
          },
          {
            hostPath: {
              path: '/cache/data/node-exporter',
              type: 'DirectoryOrCreate',
            },
            name: 'node-exporter-data',
          },
          {
            hostPath: {
              path: '/var/run/dbus/system_bus_socket',
            },
            name: 'dbus-socket',
          },
        ],
      },
    },
    updateStrategy: {
      type: 'RollingUpdate',
    },
  },
}
