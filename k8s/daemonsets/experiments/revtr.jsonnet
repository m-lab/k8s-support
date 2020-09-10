local exp = import '../templates.jsonnet';

exp.Experiment('revtr', 3, 'pusher-' + std.extVar('PROJECT_ID'), 'none', []) + {
  spec+: {
    template+: {
      spec+: {
        containers+: [
          {
            name: 'revtr',
            image: 'measurementlab/revtrvp:v0.1.4',
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
