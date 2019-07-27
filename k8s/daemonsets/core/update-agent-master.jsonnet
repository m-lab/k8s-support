// From: https://github.com/coreos/container-linux-update-operator/tree/master/examples/deploy
{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: 'update-agent-master',
    namespace: 'reboot-coordinator',
  },
  spec: {
    selector: {
      matchLabels: {
        workload: 'update-agent-master',
      },
    },
    template: {
      metadata: {
        labels: {
          workload: 'update-agent-master',
        },
      },
      spec: {
        containers: [
          {
            command: [
              '/bin/sh /config/annotate-node.sh mlab-type-master && /bin/update-agent',
            ],
            env: [
              {
                name: 'UPDATE_AGENT_NODE',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'spec.nodeName',
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
            image: 'quay.io/coreos/container-linux-update-operator:v0.7.0',
            name: 'update-agent',
            volumeMounts: [
              {
                mountPath: '/var/run/dbus',
                name: 'var-run-dbus',
              },
              {
                mountPath: '/etc/coreos',
                name: 'etc-coreos',
              },
              {
                mountPath: '/usr/share/coreos',
                name: 'usr-share-coreos',
              },
              {
                mountPath: '/etc/os-release',
                name: 'etc-os-release',
              },
              {
                mountPath: '/config',
                name: 'update-operator-config',
              },
            ],
          },
        ],
        nodeSelector: {
          'node-role.kubernetes.io/master': '',
        },
        serviceAccountName: 'reboot-coordinator',
        tolerations: [
          {
            effect: 'NoSchedule',
            key: 'node-role.kubernetes.io/master',
            operator: 'Exists',
          },
        ],
        volumes: [
          {
            hostPath: {
              path: '/var/run/dbus',
            },
            name: 'var-run-dbus',
          },
          {
            hostPath: {
              path: '/etc/coreos',
            },
            name: 'etc-coreos',
          },
          {
            hostPath: {
              path: '/usr/share/coreos',
            },
            name: 'usr-share-coreos',
          },
          {
            hostPath: {
              path: '/etc/os-release',
            },
            name: 'etc-os-release',
          },
          {
            configMap: {
              name: 'update-operator-config',
            },
            name: 'update-operator-config',
          },
        ],
      },
    },
    updateStrategy: {
      rollingUpdate: {
        maxUnavailable: 1,
      },
      type: 'RollingUpdate',
    },
  },
}
