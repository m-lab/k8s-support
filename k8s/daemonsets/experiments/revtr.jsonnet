local exp = import '../templates.jsonnet';

exp.Experiment('revtr', 3, 'pusher-' + std.extVar('PROJECT_ID'), 'none', [], []) + {
  spec+: {
    template+: {
      spec+: {
        containers+: [
          {
            name: 'revtrvp',
            image: 'measurementlab/revtrvp:v0.3.1',
            args: [
              '/server.crt',
              '/plvp.config',
            ],
            securityContext: {
              capabilities: {
                // The container processes run as nobody:nogroup, but the
                // scamper binary has/needs these capabilities.
                add: [
                  'CHOWN',
                  'DAC_OVERRIDE',
                  'NET_RAW',
                  'SETGID',
                  'SETUID',
                  'SYS_CHROOT',
                ],
                drop: [
                  'all',
                ],
              },
            },
          }
        ],
      }
    }
  }
}
