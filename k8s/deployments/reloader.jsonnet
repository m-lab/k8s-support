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
        annotations: {
          'prometheus.io/scrape': 'true',
          'prometheus.io/scheme': 'http',
        },
        labels: {
          workload: 'reloader',
        },
      },
      spec: {
        containers: [
          {
            args: [
              '--resources-to-ignore=configMaps',
            ],
            env: [
              {
                name: 'KUBERNETES_NAMESPACE',
                value: 'default',
              },
            ],
            image: 'stakater/reloader:v0.0.60',
            imagePullPolicy: 'IfNotPresent',
            name: 'reloader',
            ports: [
              {
                containerPort: 9090,
              },
            ],
          },
        ],
        nodeSelector: {
          'mlab/type': 'virtual',
          'run': 'prometheus-server',
        },
        serviceAccountName: 'reloader',
      },
    },
  },
}

