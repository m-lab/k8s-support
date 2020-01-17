local exp = import '../templates.jsonnet';

{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: 'utilization',
    namespace: 'default',
  },
  spec: {
    selector: {
      matchLabels: {
        workload: 'utilization',
      },
    },
    template: {
      metadata: {
        annotations: {
          'prometheus.io/scrape': 'true',
          'prometheus.io/scheme': 'https'
        },
        labels: {
          workload: 'utilization',
        },
      },
      spec: {
        containers: [
          {
            name: 'collectd',
            image: 'measurementlab/utility-support:v2.0.8',
            env: [
              {
                name: 'HOSTNAME',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'spec.nodeName',
                  },
                },
              },
              {
                name: 'COMMUNITY',
                valueFrom: {
                  secretKeyRef: {
                    name: 'snmp-community',
                    key: 'snmp.community',
                  },
                },
              },
            ],
            volumeMounts: [
              {
                mountPath: '/var/spool/node-exporter',
                name: 'node-exporter-data',
                readOnly: false,
              },
              {
                mountPath: '/var/spool/mlab_utility',
                name: 'utilization-data',
                readOnly: false,
              },
            ],
          }] + std.flattenArrays([
            // We want this port to be separate from the ports used by the
            // sidecar services, so we count down from 9990, rather than up.
            exp.Pusher('utilization', 9989, ['switch', 'system'], true, 'pusher-' + std.extVar('PROJECT_ID')),
          ]),
        hostNetwork: true,
        // hostPID: true,
        nodeSelector: {
          'mlab/type': 'platform',
        },
        serviceAccountName: 'kube-rbac-proxy',
        [if std.extVar('PROJECT_ID') != 'mlab-sandbox' then 'terminationGracePeriodSeconds']: 180,
        volumes: [
          {
            name: 'pusher-credentials',
            secret: {
              secretName: 'pusher-credentials',
            },
          },
          {
            name: 'utilization-data',
            hostPath: {
              path: '/cache/data/utilization',
              type: 'DirectoryOrCreate',
            },
          },
          {
            name: 'node-exporter-data',
            hostPath: {
              path: '/cache/data/node-exporter',
              type: 'DirectoryOrCreate',
            },
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
