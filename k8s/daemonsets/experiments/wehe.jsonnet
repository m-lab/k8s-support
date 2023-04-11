local exp = import '../templates.jsonnet';
local expName = 'wehe';
local services = [
  'wehe/replay=wss://:4443/v0/envelope/access',
];

exp.Experiment(expName, 5, 'pusher-' + std.extVar('PROJECT_ID'), 'netblock', ['replay'], []) + {
  spec+: {
    template+: {
      metadata+: {
        annotations+: {
          "secret.reloader.stakater.com/reload": "measurement-lab-org-tls",
        },
      },
      spec+: {
        serviceAccountName: 'heartbeat-experiment',
        initContainers+: [
          {
            args: [
              'cp', '/wehe-ca/ca.key', '/wehe-ca/ca.crt', '/wehe/ssl/',
            ],
            image: 'busybox:1.34',
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
              '-envelope.max-clients=5',
              '-envelope.subject=wehe',
              '-envelope.machine=$(MLAB_NODE_NAME)',
              '-envelope.verify-key=/verify/jwk_sig_EdDSA_locate_20200409.pub',
              '-envelope.token-required=true',
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
            image: 'measurementlab/access:v0.0.10',
            name: 'access',
            securityContext: {
              capabilities: {
                add: [
                  'NET_ADMIN',
                  'NET_RAW',
                ],
                drop: [
                  'all',
                ],
              },
              runAsUser: 0,
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
            // Advertise the prometheus port so it can be discovered by Prometheus.
            ports: [
              {
                containerPort: 9990,
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
                name: 'MPLCONFIGDIR',
                value: '/tmp/matplotlib',
              },
              {
                name: 'MLAB_NODE_NAME',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'spec.nodeName',
                  },
                },
              },
            ],
            image: 'measurementlab/wehe-py3:v0.2.9',
            livenessProbe+: {
              httpGet: {
                path: '/metrics',
                port: 9090,
              },
              // After startup, liveness should never fail.
              initialDelaySeconds: 300, // TODO: eliminate with k8s v1.18+.
              failureThreshold: 1,
              timeoutSeconds: 10,
              periodSeconds: 30,
            },
            name: expName,
            // Advertise the prometheus port so it can be discovered by Prometheus.
            ports: [
              {
                // Replay server
                containerPort: 9090,
              },
              {
                // Analyzer server
                containerPort: 9091,
              },
            ],
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
            volumeMounts: [
              exp.VolumeMount('wehe/replay'),
              {
                mountPath: '/wehe/ssl/',
                name: 'wehe-ca-cache',
              },
            ],
          },
        ] + std.flattenArrays([
          exp.Heartbeat(expName, false, services),
        ]),
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
