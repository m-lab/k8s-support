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
        containers: [
          {
            args: [
              '--web.listen-address=127.0.0.1:9100',
              '--path.procfs=/host/proc',
              '--path.sysfs=/host/sys',
              '--path.rootfs=/host/root',
              '--collector.textfile.directory=/var/spool/node-exporter',
              '--collector.filesystem.ignored-mount-points=^/(dev|proc|sys|var/lib/docker/.+)($|/)',
              '--collector.filesystem.ignored-fs-types=^(autofs|binfmt_misc|cgroup|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|mqueue|overlay|proc|procfs|pstore|rpc_pipefs|securityfs|sysfs|tracefs)$',
              '--collector.netstat.fields=^(.*_(InErrors|InErrs)|Ip_Forwarding|Ip(6|Ext)_(InOctets|OutOctets)|Icmp6?_(InMsgs|OutMsgs)|TcpExt_(TCPDSACK.*|Listen.*|Syncookies.*|TCPSynRetrans)|Tcp_(ActiveOpens|InSegs|OutSegs|PassiveOpens|RetransSegs|CurrEstab)|Udp6?_(InDatagrams|OutDatagrams|NoPorts))$',
              '--collector.systemd',
              '--collector.systemd.unit-whitelist=^(setup-after-boot.service|system-cloudinit.+|docker.service|kubelet.service)',
              '--collector.processes',
              '--no-collector.arp',
              '--no-collector.bcache',
              '--no-collector.bonding',
              '--no-collector.conntrack',
              '--no-collector.entropy',
              '--no-collector.filefd',
              '--no-collector.infiniband',
              '--no-collector.ipvs',
              '--no-collector.mdadm',
              '--no-collector.netclass',
              '--no-collector.nfs',
              '--no-collector.nfsd',
              '--no-collector.timex',
              '--no-collector.uname',
              '--no-collector.vmstat',
              '--no-collector.zfs',
            ],
            image: 'quay.io/prometheus/node-exporter',
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
            image: 'quay.io/coreos/kube-rbac-proxy:v0.4.1',
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
            key: 'node-role.kubernetes.io/master',
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
