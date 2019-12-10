local fluentdConfig = import '../../../config/fluentd.jsonnet';

{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    labels: {
      'addonmanager.kubernetes.io/mode': 'Reconcile',
      'kubernetes.io/cluster-service': 'true',
      version: 'v2.0',
    },
    name: 'fluentd',
  },
  spec: {
    selector: {
      matchLabels: {
        'kubernetes.io/cluster-service': 'true',
        version: 'v2.0',
        workload: 'fluentd',
      },
    },
    template: {
      metadata: {
        annotations: {
          'prometheus.io/scrape': 'true',
          // This annotation ensures that fluentd does not get evicted
          // if the node supports critical pod annotation based
          // priority scheme. Note that this does not guarantee
          // admission on the nodes (#40573).
          'scheduler.alpha.kubernetes.io/critical-pod': '',
        },
        labels: {
          'kubernetes.io/cluster-service': 'true',
          version: 'v2.0',
          workload: 'fluentd',
        },
      },
      spec: {
        containers: [
          {
            env: [
              {
                name: 'FLUENTD_ARGS',
                value: '--no-supervisor',
              },
              {
                name: 'GOOGLE_APPLICATION_CREDENTIALS',
                value: '/etc/fluent/keys/fluentd.json',
              },
              {
                name: 'NODE_HOSTNAME',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'spec.nodeName',
                  },
                },
              },
            ],
            image: 'fluent/fluentd-kubernetes-daemonset:v1.7.4-debian-stackdriver-1.1',
            name: 'fluentd',
            ports: [
              {
                containerPort: 9900,
                name: 'scrape',
                protocol: 'TCP',
              },
            ],
            resources: {
              limits: {
                memory: '800Mi',
              },
              requests: {
                cpu: '100m',
                memory: '200Mi',
              },
            },
            volumeMounts: [
              {
                mountPath: '/var/log',
                name: 'varlog',
              },
              {
                mountPath: '/var/lib/docker/containers',
                name: 'varlibdockercontainers',
                readOnly: true,
              },
              {
                mountPath: '/cache/docker',
                name: 'cachedocker',
              },
              {
                mountPath: '/host/lib',
                name: 'libsystemddir',
                readOnly: true,
              },
              {
                mountPath: '/config',
                name: 'config-volume',
              },
              {
                mountPath: '/etc/fluent/keys',
                name: 'credentials',
                readOnly: true,
              },
            ],
          },
        ],
        dnsPolicy: 'Default',
        terminationGracePeriodSeconds: 30,
        tolerations: [
          {
            effect: 'NoSchedule',
            key: 'node.alpha.kubernetes.io/ismaster',
          },
          {
            effect: 'NoSchedule',
            key: 'node-role.kubernetes.io/master',
          },
        ],
        volumes: [
          {
            hostPath: {
              path: '/var/log',
            },
            name: 'varlog',
          },
          {
            hostPath: {
              path: '/var/lib/docker/containers',
            },
            name: 'varlibdockercontainers',
          },
          {
            hostPath: {
              path: '/cache/docker',
            },
            name: 'cachedocker',
          },
          {
            hostPath: {
              path: '/usr/lib64',
            },
            name: 'libsystemddir',
          },
          {
            configMap: {
              name: fluentdConfig.metadata.name,
            },
            name: 'config-volume',
          },
          {
            name: 'credentials',
            secret: {
              secretName: 'fluentd-credentials',
            },
          },
        ],
      },
    },
    updateStrategy: {
      type: 'RollingUpdate',
    },
  },
}
