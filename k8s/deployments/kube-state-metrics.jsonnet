{
  apiVersion: 'apps/v1',
  kind: 'Deployment',
  metadata: {
    name: 'kube-state-metrics',
    namespace: 'kube-system',
  },
  spec: {
    replicas: 1,
    selector: {
      matchLabels: {
        workload: 'kube-state-metrics',
      },
    },
    strategy: {
      type: 'Recreate',
    },
    template: {
      metadata: {
        annotations: {
          'prometheus.io/scrape': 'true',
        },
        labels: {
          workload: 'kube-state-metrics',
        },
      },
      spec: {
        containers: [
          {
            args: [
              '--collectors=daemonsets,deployments,nodes,pods,resourcequotas,services',
            ],
            image: 'quay.io/coreos/kube-state-metrics:v1.9.7',
            name: 'kube-state-metrics',
            ports: [
              {
                containerPort: 8080,
                name: 'http-metrics',
              },
              {
                containerPort: 8081,
                name: 'telemetry',
              },
            ],
            readinessProbe: {
              httpGet: {
                path: '/healthz',
                port: 8080,
              },
              initialDelaySeconds: 5,
              timeoutSeconds: 5,
            },
            // Resources based on:
            // https://github.com/kubernetes/kube-state-metrics#resource-recommendation
            resources: {
              limits: {
                cpu: '1',
                memory: '1500Mi',
              },
            },
          },
        ],
        nodeSelector: {
          'mlab/type': 'virtual',
        },
        serviceAccountName: 'kube-state-metrics',
      },
    },
  },
}
