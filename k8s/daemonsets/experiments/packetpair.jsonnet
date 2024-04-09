local datatypes = ['pp'];
local exp = import '../templates.jsonnet';
local expName = 'packet';
local services = [
  'packet/pp=http:///packet/pp,https:///packet/pp',
];

exp.Experiment(expName, 1, 'pusher-' + std.extVar('PROJECT_ID'), "none", datatypes) + {
  spec+: {
    template+: {
      metadata+: {
        annotations+: {
          'secret.reloader.stakater.com/reload': 'measurement-lab-org-tls',
        },
      },
      spec+: {
        serviceAccountName: 'heartbeat-experiment',
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
              '-debug=true',
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
            image: 'cristinaleonr/packetpair:v0.0',
            name: 'pp',
            command: [
              '/pp/server',
            ],
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
            ] + [
              exp.VolumeMount(expName + '/' + d) for d in datatypes
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
