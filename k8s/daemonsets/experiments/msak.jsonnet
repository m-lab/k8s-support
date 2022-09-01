local datatypes = ['ndtm'];
local exp = import '../templates.jsonnet';
local expName = 'msak';

exp.ExperimentNoIndex(expName, 'pusher-' + std.extVar('PROJECT_ID'), "none", datatypes, true) + {
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
              '-ws_addr=:8080',
              '-wss_addr=:4443',
              '-cert=/certs/tls.crt',
              '-key=/certs/tls.key',
              '-datadir=/var/spool/' + expName,
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
            image: 'evfirerob/msak:latest',
            name: 'msak',
            command: [
              '/msak/msak-server',
            ],
            volumeMounts: [
              {
                mountPath: '/certs',
                name: 'measurement-lab-org-tls',
                readOnly: true,
              },
            ] + [
              exp.VolumeMount(expName + '/' + d) for d in datatypes
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
