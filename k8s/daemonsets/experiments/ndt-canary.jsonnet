local datatypes = ['ndt5', 'ndt7'];
local exp = import '../templates.jsonnet';
local expName = 'ndt';
local services = [
  'ndt/ndt7=ws:///ndt/v7/download,ws:///ndt/v7/upload,wss:///ndt/v7/download,wss:///ndt/v7/upload',
  'ndt/ndt5=ws://:3001/ndt_protocol,wss://:3010/ndt_protocol',
];

exp.Experiment(expName, 2, 'pusher-' + std.extVar('PROJECT_ID'), "none", datatypes, []) + {
  metadata+: {
    name: expName + '-canary',
  },
  spec+: {
    selector+: {
      matchLabels+: {
        workload: expName + '-canary',
      },
    },
    template+: {
      metadata+: {
        annotations+: {
          "secret.reloader.stakater.com/reload": "measurement-lab-org-tls",
        },
        labels+: {
          workload: expName + '-canary',
        },
      },
      spec+: {
        nodeSelector+: {
          'mlab/ndt-version': 'canary',
          'mlab/type': 'virtual',
        },
        serviceAccountName: 'heartbeat-experiment',
        containers+: [
          {
            name: 'ndt-server',
            image: 'measurementlab/ndt-server:' + exp.ndtCanaryVersion,
            // The max-rate flag value is stored in a file on the host
            // filesystem, created by the systemd max-rate.service.
            command: [
              '/bin/sh',
              '-c',
              '/ndt-server -txcontroller.max-rate=$(cat /metadata/iface-max-rate) $@',
              '--',
            ],
            args: [
              '-uuid-prefix-file=' + exp.uuid.prefixfile,
              '-prometheusx.listen-address=$(PRIVATE_IP):9990',
              '-datadir=/var/spool/' + expName,
              '-txcontroller.device=net1',
              '-htmldir=html/mlab',
              '-key=/certs/tls.key',
              '-cert=/certs/tls.crt',
              '-token.machine=$(NODE_NAME)',
              '-token.verify-key=/verify/jwk_sig_EdDSA_locate_20200409.pub',
              '-ndt7.token.required=true',
              '-label=type=virtual',
              '-label=deployment=canary',
            ],
            env: [
              {
                name: 'PRIVATE_IP',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'status.podIP',
                  },
                },
              },
              {
                name: 'NODE_NAME',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'spec.nodeName',
                  },
                },
              },
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
              exp.Metadata.volumemount,
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
