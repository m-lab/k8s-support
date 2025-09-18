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
          'k8s.v1.cni.cncf.io/networks': '[{ "name": "index2ip-index-7-conf" }]',
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
            args: [
              '--floo_client_debug_string=$(HOSTNAME)',
            ],
            env: [
              {
                name: 'DNS_RESOLVERS',
                value: '8.8.8.8,8.8.4.4',
              },
              {
                name: 'HOSTNAME',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'spec.nodeName',
                  },
                },
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
