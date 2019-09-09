local exp = import '../templates.jsonnet';

exp.Experiment('dash', 10, 'pusher-' + std.extVar('PROJECT_ID'), ['dash']) + {
  spec+: {
    template+: {
      spec+: {
        containers+: [
          {
            name: 'dash',
            image: 'evfirerob/dash:' + exp.dashVersion,
            args: [
              '-datadir=/var/spool/dash',
            ],
            volumeMounts: [
              exp.VolumeMount('dash'),
            ],
            ports: [
              {
                containerPort: 80,
              },
            ],

          },
        ],
      },
    },
  },
}
