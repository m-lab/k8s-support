local datatypes = ['ndtm'];
local exp = import '../templates.jsonnet';
local expName = 'msak';
local services = [
  'demo1/ndtm=ws:///msak/ndtm/download,ws:///msak/ndtm/upload,wss:///msak/ndtm/download,wss:///msak/ndtm/upload',
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
              '-token.verify=false',
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
            image: 'evfirerob/msak:latest',
            name: 'msak',
            command: [
              '/msak/msak-server',
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
          exp.Heartbeat(expName, true, services),
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
