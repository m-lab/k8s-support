local prometheusConfig = import '../../config/prometheus.jsonnet';

{
  apiVersion: 'apps/v1',
  kind: 'Deployment',
  metadata: {
    name: 'prometheus-server',
  },
  spec: {
    replicas: 1,
    selector: {
      matchLabels: {
        workload: 'prometheus-server',
      },
    },
    strategy: {
      // This must be Recreate, because you can't do a RollingUpdate on a
      // single-replica ReplicaSet that can only deploy to one very
      // specific node.
      type: 'Recreate',
    },
    template: {
      metadata: {
        annotations: {
          // Tell prometheus service discovery to scrape the pod
          // containers.
          'prometheus.io/scrape': 'true',
        },
        labels: {
          workload: 'prometheus-server',
        },
      },
      spec: {
        containers: [
          {
            args: [
              '--config.file=/etc/prometheus/prometheus.yml',
              '--storage.tsdb.path=/prometheus',
              '--web.enable-lifecycle',
              '--web.external-url=https://prometheus-platform-cluster.' + std.extVar('PROJECT_ID') + '.measurementlab.net',
              '--storage.tsdb.retention.time=2880h',
            ],
            image: 'prom/prometheus:v2.24.1',
            name: 'prometheus',
            ports: [
              {
                containerPort: 9090,
              },
            ],
            volumeMounts: [
              {
                mountPath: '/etc/prometheus/',
                name: 'prometheus-config',
              },
              {
                mountPath: '/prometheus',
                name: 'prometheus-storage',
              },
              {
                mountPath: '/etc/alertmanager/',
                name: 'alertmanager-basicauth',
              },
            ],
          },
        ],
        // TODO: use native k8s service entry points, if possible.
        hostNetwork: true,
        nodeSelector: {
          'mlab/type': 'virtual',
          run: 'prometheus-server',
        },
        serviceAccountName: 'prometheus',
        volumes: [
          {
            configMap: {
              name: prometheusConfig.metadata.name,
            },
            name: 'prometheus-config',
          },
          {
            name: 'alertmanager-basicauth',
            secret: {
              secretName: 'alertmanager-basicauth',
            },
          },
          // TODO: use native k8s persistent volume claims, if possible.
          {
            hostPath: {
              path: '/mnt/local/prometheus',
              type: 'Directory',
            },
            name: 'prometheus-storage',
          },
        ],
      },
    },
  },
}
