// From: https://github.com/coreos/container-linux-update-operator/tree/master/examples/deploy
{
  apiVersion: 'apps/v1',
  kind: 'Deployment',
  metadata: {
    name: 'update-operator',
    namespace: 'reboot-coordinator',
  },
  spec: {
    replicas: 1,
    selector: {
      matchLabels: {
        workload: 'update-operator',
      },
    },
    strategy: {
      type: 'RollingUpdate',
    },
    template: {
      metadata: {
        labels: {
          workload: 'update-operator',
        },
      },
      spec: {
        containers: [
          {
            args: [
              '-reboot-window-start=Tue 15:00',
              '-reboot-window-length=2h',
            ],
            command: [
              '/bin/update-operator',
            ],
            env: [
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
            name: 'update-operator',
          },
        ],
        nodeSelector: {
          'node-role.kubernetes.io/master': '',
        },
        tolerations: [
          {
            effect: 'NoSchedule',
            key: 'node-role.kubernetes.io/master',
            operator: 'Exists',
          },
        ],
      },
    },
  },
}
