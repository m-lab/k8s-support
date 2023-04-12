local exp = import '../templates.jsonnet';

exp.Experiment('revtr', 3, 'pusher-' + std.extVar('PROJECT_ID'), 'none', [], []) + {
  spec+: {
    template+: {
      spec+: {
        containers+: [
          {
            name: 'revtrvp',
            image: 'measurementlab/revtrvp:v0.3.0',
            args: [
              '/server.crt',
              '/plvp.config',
            ],
            securityContext: {
              capabilities: {
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
