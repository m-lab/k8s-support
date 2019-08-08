local exp = import '../templates.jsonnet';

exp.Experiment('bismark', 9, []) + {
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
