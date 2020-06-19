local exp = import '../templates.jsonnet';
local expName = 'disco';
local config = import '../../../config/disco.jsonnet';
local version = 'v0.1.1';

// Only deploy this to mlab-sandbox for now.
if std.extVar('PROJECT_ID') != 'mlab-sandbox' then {} else
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
            command: [
              // Calcuates the local switch FQDN for the -target flag.
              "/bin/sh", "-c",
              "t=s1-${HOSTNAME:6:5}.measurement-lab.org; /disco -target=$t $@", "--",
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
            image: 'measurementlab/' + expName + ':' + version,
            name: expName,
            ports: [
              {
                containerPort: 9990,
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
        hostNetwork: true,
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
