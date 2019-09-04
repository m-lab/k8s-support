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
              // TODO: enable longer retention once persistent volumes are available.
              //  "--storage.tsdb.retention=2880h",
            ],
            image: 'prom/prometheus:v2.4.2',
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
                mountPath: '/etc/prometheus/tls/',
                name: 'prometheus-etcd-tls',
              },
            ],
          },
        ],
        // TODO: use native k8s service entry points, if possible.
        hostNetwork: true,
        nodeSelector: {
          'mlab/type': 'cloud',
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
          // TODO: use native k8s persistent volume claims, if possible.
          {
            hostPath: {
              path: '/mnt/local/prometheus',
              type: 'Directory',
            },
            name: 'prometheus-storage',
          },
          {
            name: 'prometheus-etcd-tls',
            secret: {
              secretName: 'prometheus-etcd-tls',
            },
          },
        ],
      },
    },
  },
}
