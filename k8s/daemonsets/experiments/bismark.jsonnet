local exp = import 'library.jsonnet';

exp.Experiment('bismark', 9, []) + {
  spec+: {
    template+: {
      spec+: {
        containers+: [
          {
            name: 'bismark',
            image: 'measurementlab/bismark-test:v1.0.2',
            ports: [
              {
                // Does Bismark output prometheus metrics on 9090?
                containerPort: 9090,
              },
            ],
          },
        ],
      },
    },
  },
}
