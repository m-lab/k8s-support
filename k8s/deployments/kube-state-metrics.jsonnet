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
            image: 'quay.io/coreos/kube-state-metrics:v1.5.0',
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
          },
          {
            command: [
              '/pod_nanny',
              '--container=kube-state-metrics',
              '--cpu=100m',
              '--extra-cpu=1m',
              '--memory=100Mi',
              '--extra-memory=2Mi',
              '--threshold=5',
              '--deployment=kube-state-metrics',
            ],
            env: [
              {
                name: 'MY_POD_NAME',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'metadata.name',
                  },
                },
              },
              {
                name: 'MY_POD_NAMESPACE',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'metadata.namespace',
                  },
                },
              },
            ],
            image: 'k8s.gcr.io/addon-resizer:1.8.3',
            name: 'addon-resizer',
            resources: {
              limits: {
                cpu: '150m',
                memory: '50Mi',
              },
              requests: {
                cpu: '150m',
                memory: '50Mi',
              },
            },
          },
        ],
        nodeSelector: {
          'mlab/type': 'cloud',
        },
        serviceAccountName: 'kube-state-metrics',
      },
    },
  },
}
