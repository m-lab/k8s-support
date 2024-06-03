local datatypes = ['pair1','train1','ndt7'];
local exp = import '../templates.jsonnet';
local expName = 'pt';
local services = [];

exp.Experiment(expName, 6, 'pusher-' + std.extVar('PROJECT_ID'), "none", [], datatypes) + {
  spec+: {
    template+: {
      metadata+: {
        annotations+: {
          'secret.reloader.stakater.com/reload': 'measurement-lab-org-tls',
        },
      },
      spec+: {
        serviceAccountName: 'heartbeat-experiment',
        initContainers+: [
          {
            // Copy the JSON schema where jostler expects it to be.
            name: 'copy-schema',
            image: 'measurementlab/packet-test:latest',
            command: [
              '/bin/sh',
              '-c',
              'cp /packet-test/pair1.json /var/spool/datatypes/pair1.json && ' +
              'cp /packet-test/train1.json /var/spool/datatypes/train1.json && ' +
              'cp /packet-test/ndt7.json /var/spool/datatypes/ndt7.json',
            ],
            volumeMounts: [
              exp.VolumeMountDatatypes(expName),
            ],
          },
        ],
        containers+: [
          {
            args: [
              '-datadir=/var/spool/' + expName,
              '-hostname=$(NODE_NAME)',
            ],
            env: [
              {
                name: 'NODE_NAME',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'spec.nodeName',
                  },
                },
              },
              {
                name: 'PRIVATE_IP',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'status.podIP',
                  },
                },
              },
            ],
            image: 'measurementlab/packet-test:latest',
            name: 'packet-test',
            command: [
              '/packet-test/server',
            ],
            securityContext: {
              capabilities: {
                drop: [
                  'all',
                ],
              },
            },
            volumeMounts: [
              {
                mountPath: '/certs',
                name: 'measurement-lab-org-tls',
                readOnly: true,
              },
              {
                mountPath: '/verify',
                name: 'locate-verify-keys',
                readOnly: true,
              },
              exp.uuid.volumemount,
            ] + [
              exp.VolumeMount(expName + '/' + d) for d in datatypes
            ],
            ports: [
              {
                containerPort: 9990,
              },
            ],
          },
        ] + std.flattenArrays([
          exp.Heartbeat(expName, false, services),
        ]),
        volumes+: [
          {
            name: 'measurement-lab-org-tls',
            secret: {
              secretName: 'measurement-lab-org-tls',
            },
          },
          {
            name: 'locate-verify-keys',
            secret: {
              secretName: 'locate-verify-keys',
            },
          },
          exp.Metadata.volume,
        ],
      },
    },
  },
}
