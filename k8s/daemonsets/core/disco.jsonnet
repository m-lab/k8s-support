local exp = import '../templates.jsonnet';
local expName = 'disco';
local discoConfig = import '../../../config/disco.jsonnet';

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
              '-datadir=/var/spool/' + expName,
              '-write-interval=5m',
              '-prometheusx.listen-address=127.0.0.1:9990',
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
            ],
            image: 'measurementlab/' + expName + ':v0.1.0',
            name: expName,
            ports: [
              {
                containerPorts: 9990,
              },
            ],
            volumeMounts: [
              exp.VolumeMount(expName),
              {
                mountPath: '/etc/' + expName,
                name: expName + '-config',
                readOnly: true,
              },
            ],
          }] + std.flattenArrays([
            exp.Pusher(expName, 9995, ['switch'], false, 'pusher-' + std.extVar('PROJECT_ID')),
          ]),
        nodeSelector: {
          'mlab/type': 'physical',
        },
        volumes: [
          {
            name: 'pusher-credentials',
            secret: {
              secretName: 'pusher-credentials',
            },
          },
          {
            name: expName + '-data',
            hostPath: {
              path: '/cache/data/' + expName,
              type: 'DirectoryOrCreate',
            },
          },
          {
            name: expName + '-config',
            configMap: {
              name: discoConfig.metadata.name
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
