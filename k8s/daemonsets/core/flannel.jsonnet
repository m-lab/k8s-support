{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: 'flannel',
    namespace: 'kube-system',
  },
  spec: {
    selector: {
      matchLabels: {
        app: 'flannel',
        tier: 'node',
        workload: 'flannel',
      },
    },
    template: {
      metadata: {
        labels: {
          app: 'flannel',
          tier: 'node',
          workload: 'flannel',
        },
      },
      spec: {
        affinity: {
          nodeAffinity: {
            requiredDuringSchedulingIgnoredDuringExecution: {
              nodeSelectorTerms: [
                {
                  matchExpressions: [
                    {
                      key: 'kubernetes.io/os',
                      operator: 'In',
                      values: [
                        'linux',
                      ],
                    },
                  ],
                },
              ],
            },
          },
        },
        containers: [
          {
            args: [
              '--ip-masq',
              '--kube-subnet-mgr',
            ],
            command: [
              '/opt/bin/flanneld',
            ],
            env: [
              {
                name: 'POD_NAME',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'metadata.name',
                  },
                },
              },
              {
                name: 'POD_NAMESPACE',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'metadata.namespace',
                  },
                },
              },
            ],
            image: 'flannel/flannel:' + std.extVar('K8S_FLANNEL_VERSION'),
            name: 'flannel',
            resources: {
              requests: {
                cpu: '100m',
                memory: '50Mi',
              },
            },
            securityContext: {
              privileged: false,
              capabilities: {
                add: [
                  'NET_ADMIN',
                  'NET_RAW',
                ],
                drop: [
                  'all',
                ],
              },
            },
            volumeMounts: [
              {
                mountPath: '/run',
                name: 'run',
              },
              {
                mountPath: '/etc/kube-flannel/',
                name: 'flannel-cfg',
              },
              {
                mountPath: '/run/xtables.lock',
                name: 'xtables-lock',
              },
            ],
          },
        ],
        hostNetwork: true,
        serviceAccountName: 'flannel',
        tolerations: [
          {
            effect: 'NoSchedule',
            operator: 'Exists',
          },
        ],
        volumes: [
          {
            hostPath: {
              path: '/run',
            },
            name: 'run',
          },
          {
            configMap: {
              name: 'kube-flannel-cfg',
            },
            name: 'flannel-cfg',
          },
          {
            hostPath: {
              path: '/run/xtables.lock',
            },
            name: 'xtables-lock',
          },
        ],
      },
    },
    updateStrategy: {
      type: 'RollingUpdate',
    },
  },
}

