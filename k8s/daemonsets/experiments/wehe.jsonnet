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
              '-envelope.subject=wehe',
              '-envelope.machine=$(MLAB_NODE_NAME)',
              '-envelope.verify-key=/verify/jwk_sig_EdDSA_locate_20200409.pub',
              // Maximum timeout for a client to hold the envelope open.
              '-timeout=10m',
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
            image: 'measurementlab/access:v0.0.3',
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
              {
                mountPath: '/verify',
                name: 'locate-verify-keys',
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
            image: 'measurementlab/wehe-py3:v0.1.10',
            name: expName,
            /* TODO: enable with k8s v1.18+
            startupProbe+: {
              httpGet: {
                path: '/metrics',
                port: 9090,
              },
              // Allow up to 5min for the service to startup: 30*10.
              failureThreshold: 30,
              periodSeconds: 10,
            },
            */
            livenessProbe+: {
              httpGet: {
                path: '/metrics',
                port: 9090,
              },
              // After startup, liveness should never fail.
              // NOTE: allow several failures until k8s v1.18+.
              // TODO: once startupProbe is available, failureThreshold should be 1.
              failureThreshold: 5,
              timeoutSeconds: 10,
              periodSeconds: 30,
            },
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
          {
            name: 'locate-verify-keys',
            secret: {
              secretName: 'locate-verify-keys',
            },
          },
        ],
      },
    },
  },
}
