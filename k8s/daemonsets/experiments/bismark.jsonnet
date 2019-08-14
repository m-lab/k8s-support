local exp = import '../templates.jsonnet';

exp.Experiment('bismark', 9, 'pusher-' + std.extVar('PROJECT_ID'), []) + {
  spec+: {
    template+: {
      spec+: {
        containers+: [
          {
            name: 'bismark',
            image: 'measurementlab/bismark-test:v1.0.2',
          },
        ],
        nodeSelector+: {
          'mlab/project': 'mlab-sandbox',
        },
      },
    },
  },
}
