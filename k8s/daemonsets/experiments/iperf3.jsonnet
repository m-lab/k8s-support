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
              // TODO: require tokens after clients support envelope.
              '-envelope.token-required=false',
              // Maximum timeout for a client to hold the envelope open.
              '-timeout=2m',
            ],
            image: 'measurementlab/access:v0.0.2',
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
        ],
      },
    },
  },
}
