local exp = import '../templates.jsonnet';
local expName = 'disco';
local config = import '../../../config/disco.jsonnet';
local version = 'v0.1.13';

{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: expName,
    namespace: 'default',
  },
  spec: {
    selector: {
      matchLabels: {
        workload: expName,
      },
    },
    template: {
      metadata: {
        annotations: {
          'prometheus.io/scrape': 'true',
          'prometheus.io/scheme': 'http'
        },
        labels: {
          workload: expName,
        },
      },
      spec: {
        containers: [
          {
            args: [
              '-datadir=/var/spool/utilization',
              '-write-interval=5m',
              '-prometheusx.listen-address=$(PRIVATE_IP):9990',
              '-metrics=/etc/' + expName + '/metrics.yaml',
            ],
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
              {
                "name": "PRIVATE_IP",
                "valueFrom": {
                  "fieldRef": {
                    "fieldPath": "status.podIP"
                  },
                },
              },
            ],
            image: 'measurementlab/' + expName + ':' + version,
            name: expName,
            ports: [
              {
                containerPort: 9990,
              },
            ],
            volumeMounts: [
              exp.VolumeMount('utilization'),
              {
                mountPath: '/etc/' + expName,
                name: expName + '-config',
                readOnly: true,
              },
            ],
          }] + std.flattenArrays([
            exp.Pusher('utilization', 9995, ['switch'], false, 'pusher-' + std.extVar('PROJECT_ID')),
          ]),
        nodeSelector: {
          'mlab/type': 'physical',
        },
        [if std.extVar('PROJECT_ID') != 'mlab-sandbox' then 'terminationGracePeriodSeconds']: 120,
        volumes: [
          {
            name: 'pusher-credentials',
            secret: {
              secretName: 'pusher-credentials',
            },
          },
          {
            name: 'utilization' + '-data',
            hostPath: {
              path: '/cache/data/utilization',
              type: 'DirectoryOrCreate',
            },
          },
          {
            name: expName + '-config',
            configMap: {
              name: config.metadata.name
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
