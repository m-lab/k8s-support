local exp = import '../templates.jsonnet';

exp.Experiment('neubot', 10, 'pusher-' + std.extVar('PROJECT_ID'), ['neubot']) + {
  spec+: {
    template+: {
      spec+: {
        containers+: [
            {
              name: 'neubot',
              image: 'neubot/dash:' + exp.dashVersion,
            args: [
              '-datadir=/var/spool/neubot',
              '-prometheusx.listen-address=$(PRIVATE_IP):9990',
            ],
            env: [
              {
                name: 'PRIVATE_IP',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'status.podIP',
                  },
                },
              },
            ],
            volumeMounts: [
              exp.VolumeMount('neubot'),
            ],
            ports: [
              {
                containerPort: 80,
              },
            ],
            livenessProbe+: {
              httpGet: {
                path: '/metrics',
                port: 9990,
              },
              initialDelaySeconds: 5,
              periodSeconds: 30,
            },
          },
        ],
      },
    },
  },
}
