local exp = import '../templates.jsonnet';

exp.Experiment('revtr', 3, 'pusher-' + std.extVar('PROJECT_ID'), 'none', []) + {
  spec+: {
    template+: {
      spec+: {
        containers+: [
          {
            name: 'revtrvp',
            image: 'measurementlab/revtrvp:v0.2.3',
            args: [
              '/root.crt',
              '/plvp.config',
            ],
          }
        ],
      }
    }
  }
}
