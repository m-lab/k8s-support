{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: 'dmesg-exporter',
  },
  spec: {
    selector: {
      matchLabels: {
        workload: 'dmesg-exporter',
      },
    },
    template: {
      metadata: {
        annotations: {
          'prometheus.io/scrape': 'true',
          'prometheus.io/scheme': 'http',
        },
        labels: {
          workload: 'dmesg-exporter',
        },
      },
      spec: {
        containers: [
          {
            args: [
              'start',
              '--address=127.0.0.1:9900',
              '--path=/metrics',
            ],
            image: 'cirocosta/dmesg_exporter',
            name: 'dmesg-exporter',
            ports: [
              {
                containerPort: 9900,
                name: 'prometheus',
              },
            ],
            resources: {
              limits: {
                cpu: '100m',
                memory: '100Mi',
              },
              requests: {
                cpu: '50m',
                memory: '50Mi',
              },
            },
            volumeMounts: [
              {
                mountPath: '/dev/kmsg',
                name: 'proc',
                readOnly: true,
              },
            ],
          },
        ],
      },
    },
  },
}
