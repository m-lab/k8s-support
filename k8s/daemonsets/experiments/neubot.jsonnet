local exp = import '../templates.jsonnet';

exp.Experiment('neubot', 10, 'pusher-' + std.extVar('PROJECT_ID'), ['dash']) + {
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
              '-http-listen-address=:80',
              '-https-listen-address=:443',
              '-tls-cert=/certs/cert.pem',
              '-tls-key=/certs/key.pem',
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
              {
                mountPath: '/certs',
                name: 'ndt-tls',
                readOnly: true,
              },
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
        volumes+: [
          {
            name: 'ndt-tls',
            secret: {
              secretName: 'ndt-tls',
            },
          },
        ],
      },
    },
  },
}
