local exp = import '../templates.jsonnet';
local expName = 'responsiveness';

exp.ExperimentNoIndex(expName, 'pusher-' + std.extVar('PROJECT_ID'), "none", [], true) + {
  spec+: {
    template+: {
      metadata+: {
        annotations+: {
          'secret.reloader.stakater.com/reload': 'measurement-lab-org-tls',
        },
      },
      spec+: {
        containers+: [
          {
            args: [
              '-base-port=443',
              '-public-name=$(MLAB_NODE_NAME)',
              '-domain=$(MLAB_NODE_NAME)',
              '-cert-file=/certs/tls.crt',
              '-key-file=/certs/tls.key',
              '-listen-addr=0.0.0.0',
            ],
            env: [
              {
                name: 'MLAB_NODE_NAME',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'spec.nodeName',
                  },
                },
              },
            ],
            image: 'soltesz/responsiveness-server:v0.0',
            name: 'responsiveness-server',
            volumeMounts: [
              {
                mountPath: '/certs',
                name: 'measurement-lab-org-tls',
                readOnly: true,
              },
            ],
          },
        ],
        hostNetwork: true,
        hostPID: true,
        volumes+: [
          {
            name: 'measurement-lab-org-tls',
            secret: {
              secretName: 'measurement-lab-org-tls',
            },
          },
        ],
      },
    },
  },
}
