local exp = import '../templates.jsonnet';
local expName = 'wehe';

exp.Experiment(expName, 5, 'pusher-' + std.extVar('PROJECT_ID'), 'netblock', ['replay']) + {
  spec+: {
    template+: {
      metadata+: {
        annotations+: {
          "secret.reloader.stakater.com/reload": "measurement-lab-org-tls",
        },
      },
      spec+: {
        initContainers+: [
          {
            args: [
              'cp', '/wehe-ca/ca.key', '/wehe-ca/ca.crt', '/wehe/ssl/',
            ],
            image: 'busybox',
            // Wehe expects the ca.key and ca.crt to be in a
            // directory to which it can write the resulting keys
            // produced. Secrets can't be mounted read/write, so
            // before we start we copy those files from the mounted
            // secret (read-only) to a cache directory (read-write).
            name: 'ca-copy',
            volumeMounts: [
              {
                mountPath: '/wehe/ssl/',
                name: 'wehe-ca-cache',
              },
              {
                mountPath: '/wehe-ca/',
                name: 'wehe-ca',
              },
            ],
          },
        ],
        containers+: [
          {
            args: [
              '-envelope.key=/certs/tls.key',
              '-envelope.cert=/certs/tls.crt',
              '-envelope.listen-address=:4443',
              '-envelope.device=net1',
              // TODO: require tokens after clients support envelope.
              '-envelope.token-required=false',
              // Maximum timeout for a client to hold the envelope open.
              '-timeout=10m',
            ],
            image: 'measurementlab/access:v0.0.2',
            name: 'access',
            securityContext: {
              capabilities: {
                add: [
                  'NET_ADMIN',
                ],
              },
            },
            volumeMounts: [
              {
                mountPath: '/certs',
                name: 'measurement-lab-org-tls',
                readOnly: true,
              },
            ],
          },
          {
            args: [
              'wehe.$(MLAB_NODE_NAME)',
              'net1',
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
            image: 'measurementlab/wehe-py3:v0.1.9',
            name: expName,
            volumeMounts: [
              exp.VolumeMount('wehe/replay') + {
                mountPath: '/data/RecordReplay/ReplayDumpsTimestamped',
              },
              {
                mountPath: '/wehe/ssl/',
                name: 'wehe-ca-cache',
              },
            ],
          },
        ],
        volumes+: [
          {
            name: 'measurement-lab-org-tls',
            secret: {
              secretName: 'measurement-lab-org-tls',
            },
          },
          {
            emptyDir: {},
            name: 'wehe-ca-cache',
          },
          {
            name: 'wehe-ca',
            secret: {
              secretName: 'wehe-ca',
            },
          },
        ],
      },
    },
  },
}
