{
  apiVersion: 'apps/v1',
  kind: 'Deployment',
  metadata: {
    name: 'reloader',
  },
  spec: {
    replicas: 1,
    revisionHistoryLimit: 2,
    selector: {
      matchLabels: {
        workload: 'reloader',
      },
    },
    template: {
      metadata: {
        labels: {
          workload: 'reloader',
        },
      },
      spec: {
        containers: [
          {
            image: 'stakater/reloader:v0.0.60',
            imagePullPolicy: 'IfNotPresent',
            name: 'reloader',
          },
        ],
        serviceAccountName: 'reloader',
      },
    },
  },
}

