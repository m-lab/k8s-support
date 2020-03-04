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
              '--address=$(PRIVATE_IP):9900',
              '--path=/metrics',
            ],
            image: 'cirocosta/dmesg_exporter:0.0.1',
            name: 'dmesg-exporter',
            env: [
              {
                name: 'PRIVATE_IP',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'status.podIP',
                  },
                },
              },
            ],
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
                name: 'kmsg',
                readOnly: true,
              },
            ],
            // This exporter needs to access /dev/kmsg on the host, which
            // requires it to be privileged.
            securityContext: {
              privileged: true,
            },
          },
        ],
        volumes: [
          {
            name: 'kmsg',
            hostPath: {
              path: '/dev/kmsg',
            },
          },
        ],
      },
    },
  },
}
