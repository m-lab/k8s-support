// From: https://github.com/coreos/container-linux-update-operator/tree/master/examples/deploy
{
  apiVersion: 'apps/v1',
  kind: 'Deployment',
  metadata: {
    name: 'update-operator-platform',
    namespace: 'reboot-coordinator',
  },
  spec: {
    replicas: 1,
    selector: {
      matchLabels: {
        workload: 'update-operator-platform',
      },
    },
    strategy: {
      type: 'RollingUpdate',
    },
    template: {
      metadata: {
        labels: {
          workload: 'update-operator-platform',
        },
      },
      spec: {
        containers: [
          {
            args: [
              '-before-reboot-annotations=mlab-type-platform',
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
          'mlab/type': 'cloud',
          run: 'prometheus-server',
        },
        serviceAccountName: 'reboot-coordinator',
        tolerations: [
          {
            operator: 'Exists',
          },
        ],
      },
    },
  },
}
