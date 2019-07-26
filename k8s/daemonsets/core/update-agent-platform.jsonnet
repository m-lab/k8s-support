local exp = import '../templates.jsonnet';

// From: https://github.com/coreos/container-linux-update-operator/tree/master/examples/deploy
{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: 'update-agent-platform',
    namespace: 'reboot-coordinator',
  },
  spec: {
    selector: {
      matchLabels: {
        workload: 'update-agent-platform',
      },
    },
    template: {
      metadata: {
        labels: {
          workload: 'update-agent-platform',
        },
      },
      spec: {
        initContainers: [
          exp.CluoAnnotation('mlab-type-platform'),
        ],
        containers: [
          {
            command: [
              '/bin/update-agent',
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
            ],
          },
        ],
        nodeSelector: {
          'mlab/type': 'platform',
        },
        serviceAccountName: 'reboot-coordinator',
        // Tolerate everything
        tolerations: [
          {
            operator: 'Exists'
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
