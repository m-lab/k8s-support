{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: 'cadvisor',
    namespace: 'default',
  },
  spec: {
    selector: {
      matchLabels: {
        workload: 'cadvisor',
      },
    },
    template: {
      metadata: {
        annotations: {
          'prometheus.io/scrape': 'true',
        },
        labels: {
          workload: 'cadvisor',
        },
      },
      spec: {
        containers: [
          {
            args: [
              '-housekeeping_interval=60s',
              '-max_housekeeping_interval=75s',
              '-enable_metrics=cpu,memory,network',
              // Only show stats for docker containers.
              '-docker_only',
              '-store_container_labels=false',
              '-whitelisted_container_labels=io.kubernetes.container.name,io.kubernetes.pod.name,io.kubernetes.pod.namespace,workload',
            ],
            image: 'gcr.io/cadvisor/cadvisor:v0.44.0',
            name: 'cadvisor',
            ports: [
              {
                containerPort: 8080,
                name: 'scrape',
              },
            ],
            volumeMounts: [
              {
                mountPath: '/rootfs',
                name: 'rootfs',
                readOnly: true,
              },
              {
                mountPath: '/var/run',
                name: 'var-run',
                readOnly: true,
              },
              {
                mountPath: '/sys',
                name: 'sys',
                readOnly: true,
              },
              {
                mountPath: '/var/lib/docker',
                name: 'var-lib-docker',
                readOnly: true,
              },
              {
                mountPath: '/dev/disk',
                name: 'dev-disk',
                readOnly: true,
              },
            ],
          },
        ],
        volumes: [
          {
            hostPath: {
              path: '/',
            },
            name: 'rootfs',
          },
          {
            hostPath: {
              path: '/var/run',
            },
            name: 'var-run',
          },
          {
            hostPath: {
              path: '/sys',
            },
            name: 'sys',
          },
          {
            hostPath: {
              path: '/var/lib/docker',
            },
            name: 'var-lib-docker',
          },
          {
            hostPath: {
              path: '/dev/disk',
            },
            name: 'dev-disk',
          },
        ],
      },
    },
    updateStrategy: {
      type: 'RollingUpdate',
    },
  },
}
