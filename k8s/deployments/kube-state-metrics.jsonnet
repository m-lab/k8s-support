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
              '--resources=daemonsets,deployments,nodes,pods,resourcequotas,services',
              '--metric-labels-allowlist=nodes=[mlab/type]',
            ],
            image: 'k8s.gcr.io/kube-state-metrics/kube-state-metrics:v2.2.4',
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
          'run': 'prometheus-server',
        },
        serviceAccountName: 'kube-state-metrics',
      },
    },
  },
}
