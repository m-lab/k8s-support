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
        // NOTE: we override the containers to include only those named below.
        // Once this service has a dedicated experiment index assigned, we should
        // update the config to use all sidecar services.
        containers: [
          {
            args: [
              '-config-port=443',
              '-config-name=$(MLAB_NODE_NAME)',
              '-public-port=443',
              '-public-name=$(MLAB_NODE_NAME)',
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
            image: 'soltesz/responsiveness-server:v0.1',
            name: 'responsiveness-server',
            command: [
              '/server/networkqualityd',
            ],
            volumeMounts: [
              {
                mountPath: '/certs',
                name: 'measurement-lab-org-tls',
                readOnly: true,
              },
            ],
          },
        ],
        // Use host network to listen on the machine IP address without
        // registering an experiment index yet.
        hostNetwork: true,
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
