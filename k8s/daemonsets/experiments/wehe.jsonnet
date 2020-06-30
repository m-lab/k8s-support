local exp = import '../templates.jsonnet';
local expName = 'wehe';

exp.Experiment(expName, 5, 'pusher-' + std.extVar('PROJECT_ID'), 'netblock', ['replay']) + {
  spec+: {
    template+: {
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
              'wehe.$(MLAB_NODE_NAME)',
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
            image: 'measurementlab/wehe-py3:v0.1.0',
            name: expName,
            volumeMounts: [
              {
                mountPath: '/data',
                name: 'wehe-data',
              },
              {
                mountPath: '/wehe/ssl/',
                name: 'wehe-ca-cache',
              },
            ],
          },
        ] + std.flattenArrays([
          exp.Pusher(expName, 9995, ['replay'], false, 'pusher-' + std.extVar('PROJECT_ID')),
        ]),
        [if std.extVar('PROJECT_ID') != 'mlab-sandbox' then 'terminationGracePeriodSeconds']: 180,
        volumes+: [
          {
            name: 'pusher-credentials',
            secret: {
              secretName: 'pusher-credentials',
            },
          },
          {
            hostPath: {
              path: '/cache/data/' + expName,
              type: 'DirectoryOrCreate',
            },
            name: expName + '-data',
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
