local expName = 'flooefi';

{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: expName,
    namespace: expName,
  },
  spec: {
    selector: {
      matchLabels: {
        workload: expName,
      },
    },
    template: {
      metadata: {
        annotations: {
          'prometheus.io/scrape': 'true',
          'prometheus.io/scheme': 'http'
        },
        labels: {
          workload: expName,
        },
      },
      spec: {
        containers: [
          {
            env: [
              {
                name: 'DNS_RESOLVERS',
                value: '8.8.8.8,8.8.4.4',
              },
            ],
            image: 'gcr.io/google.com/floonet/flooefi-prod:latest',
            name: expName,
            ports: [
              {
                containerPort: 33465,
              },
            ],
          },
        ],
        nodeSelector: {
          'mlab/type': 'physical',
          'mlab/donated': 'false',
        },
        dnsConfig: {
          options: [
            {
              name: 'ndots',
              value: '2',
            },
          ],
        }
      },
    },
    updateStrategy: {
      rollingUpdate: {
        maxUnavailable: 2,
      },
      type: 'RollingUpdate',
    },
  },
}

