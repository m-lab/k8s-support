local datatypes = ['throughput1','latency1'];
local exp = import '../templates.jsonnet';
local expName = 'msak';
local expVersion = 'v0.4.0';
local services = [
  'msak/throughput1=ws:///throughput/v1/download,ws:///throughput/v1/upload,wss:///throughput/v1/download,wss:///throughput/v1/upload',
  'msak/latency1=http:///latency/v1/authorize,https:///latency/v1/authorize,http:///latency/v1/result,https:///latency/v1/result',
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
              'cp /msak/throughput1.json /var/spool/datatypes/throughput1.json && ' +
              'cp /msak/latency1.json /var/spool/datatypes/latency1.json',
            ],
            volumeMounts: [
              exp.VolumeMountDatatypes(expName),
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
