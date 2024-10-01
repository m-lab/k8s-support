local datatypes = ['pair1','train1','ndt7','annotation2'];
local exp = import '../templates.jsonnet';
local expName = 'pt';
local expVersion = 'v0.1.2';
local services = [
  'pt/ndt7=ws:///v0/ndt7/download,wss:///v0/ndt7/download',
];

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
            image: 'measurementlab/packet-test:' + expVersion,
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
              '-address=:80',
              '-address-secure=:443',
              '-key=/certs/tls.key',
              '-cert=/certs/tls.crt',
              '-token.machine=$(NODE_NAME)',
              '-token.verify-key=/verify/jwk_sig_EdDSA_locate_20200409.pub',
              '-token.verify=true',
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
            image: 'measurementlab/packet-test:' + expVersion,
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
