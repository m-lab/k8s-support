local exp = import '../templates.jsonnet';
local expName = 'iperf3';

exp.Experiment(expName, 6, 'pusher-' + std.extVar('PROJECT_ID'), 'netblock', ['test']) + {
  spec+: {
    template+: {
      metadata+: {
        annotations+: {
          'secret.reloader.stakater.com/reload': 'measurement-lab-org-tls',
        },
      },
      spec+: {
        containers+: [
          {
            args: [
              '-envelope.key=/certs/tls.key',
              '-envelope.cert=/certs/tls.crt',
              '-envelope.listen-address=:443',
              '-envelope.device=net1',
              '-envelope.subject=iperf3',
              '-envelope.machine=$(MLAB_NODE_NAME)',
              '-envelope.verify-key=/verify/jwk_sig_EdDSA_locate_20200409.pub',
              // Maximum timeout for a client to hold the envelope open.
              '-timeout=2m',
            ],
            env: [
              {
                name: 'MLAB_NODE_NAME',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'spec.nodeName',
                  },
                },
              },
            ],
            image: 'soltesz/access:v0.4',
            name: 'access',
            securityContext: {
              capabilities: {
                add: [
                  'NET_ADMIN',
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
            ],
          },
          {
            # Start the iperf3 server.
            args: [ '-s' ],
            image: 'soltesz/iperf3:v0.0',
            name: expName,
          },
        ],
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
