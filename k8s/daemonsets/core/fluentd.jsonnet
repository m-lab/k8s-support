local fluentdConfig = import '../../../config/fluentd.jsonnet';

{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: 'fluentd',
    namespace: 'kube-system',
    labels: {
      'k8s-app': 'fluentd-logging',
      version: 'v1',
    },
  },
  spec: {
    selector: {
      matchLabels: {
        'k8s-app': 'fluentd-logging',
        version: 'v1',
      },
    },
    template: {
      metadata: {
        labels: {
          'k8s-app': 'fluentd-logging',
          version: 'v1',
        },
      },
      spec: {
        serviceAccount: 'fluentd',
        serviceAccountName: 'fluentd',
        tolerations: [
          {
            key: 'node-role.kubernetes.io/master',
            effect: 'NoSchedule',
          },
        ],
        containers: [
          {
            name: 'fluentd',
            image: 'fluent/fluentd-kubernetes-daemonset:v1-debian-stackdriver',
            env: [
              {
                name: 'GOOGLE_APPLICATION_CREDENTIALS',
                value: '/etc/fluent/keys'
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
                name: 'varlog',
                mountPath: '/var/log',
              },
              {
                name: 'varlibdockercontainers',
                mountPath: '/var/lib/docker/containers',
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
        terminationGracePeriodSeconds: 30,
        volumes: [
          {
            name: 'varlog',
            hostPath: {
              path: '/var/log',
            },
          },
          {
            name: 'varlibdockercontainers',
            hostPath: {
              path: '/var/lib/docker/containers',
            },
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
  },
}