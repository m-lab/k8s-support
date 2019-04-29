{
  apiVersion: 'apps/v1',
  kind: 'Deployment',
  metadata: {
    name: 'reboot-api',
  },
  spec: {
    replicas: 1,
    selector: {
      matchLabels: {
        workload: 'reboot-api',
      },
    },
    template: {
      metadata: {
        labels: {
          workload: 'reboot-api',
        },
      },
      spec: {
        containers: [
          {
            args: [
              '-datastore.project=' + std.extVar('PROJECT_ID'),
              '-reboot.key=/var/secrets/reboot-api-ssh.key',
            ],
            env: [
              {
                name: 'GOOGLE_APPLICATION_CREDENTIALS',
                value: '/var/secrets/reboot-api-credentials.json',
              },
            ],
            image: 'measurementlab/reboot-api:latest',
            name: 'reboot-api',
            resources: {
              limits: {
                cpu: '200m',
                memory: '100Mi',
              },
              requests: {
                cpu: '200m',
                memory: '100Mi',
              },
            },
            volumeMounts: [
              {
                mountPath: '/var/secrets/',
                name: 'credentials',
              },
            ],
          },
        ],
        nodeSelector: {
          'node-role.kubernetes.io/master': '',
        },
        tolerations: [
          {
            effect: 'NoSchedule',
            key: 'node-role.kubernetes.io/master',
          },
        ],
        volumes: [
          // Google credentials to connect to Datastore and the SSH
          // key to log into the nodes are provided through a single
          // Kubernetes secret.
          {
            name: 'credentials',
            secret: {
              secretName: 'reboot-api-credentials',
            },
          },
        ],
      },
    },
  },
}
