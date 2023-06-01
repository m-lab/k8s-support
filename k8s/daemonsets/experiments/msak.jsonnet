local datatypes = ['ndt8'];
local exp = import '../templates.jsonnet';
local expName = 'msak';
local expVersion = 'v0.1.0';
local services = [
  'msak/ndt8=ws:///ndt/v8/download,ws:///ndt/v8/upload,wss:///ndt/v8/download,wss:///ndt/v8/upload',
];

exp.Experiment(expName, 1, 'pusher-' + std.extVar('PROJECT_ID'), "none", [], datatypes) + {
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
            image: 'measurementlab/msak:' + expVersion,
            command: [
              '/bin/sh',
              '-c',
              'cp /msak/ndt8.json /var/spool/datatypes/ndt8.json',
            ],
            volumeMounts: [
              {
                mountPath: '/var/spool/datatypes',
                name: 'var-spool-datatypes',
                readOnly: false,
              },
            ],
          },
        ],
        containers+: [
          {
            args: [
              '-ws_addr=:80',
              '-wss_addr=:443',
              '-cert=/certs/tls.crt',
              '-key=/certs/tls.key',
              '-datadir=/var/spool/' + expName,
              '-token.machine=$(NODE_NAME)',
              '-token.verify-key=/verify/jwk_sig_EdDSA_locate_20200409.pub',
              '-token.verify=true',
              '-uuid-prefix-file=' + exp.uuid.prefixfile,
              '-prometheusx.listen-address=$(PRIVATE_IP):9990',
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
            image: 'measurementlab/msak:' + expVersion,
            name: 'msak',
            command: [
              '/msak/msak-server',
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
          {
            args: [
              '-addr=:4443',
              '-cert=/certs/tls.crt',
              '-key=/certs/tls.key',
              '-hostname=msak-$(NODE_NAME)',
              '-www=/app/www',
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
            ],
            image: 'soltesz/speedtest-webtransport-go:v0.0.1',
            name: 'speedtest-webtransport',
            volumeMounts: [
              {
                mountPath: '/certs',
                name: 'measurement-lab-org-tls',
                readOnly: true,
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
        ],
      },
    },
  },
}
