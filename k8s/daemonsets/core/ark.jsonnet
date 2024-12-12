local expName = 'ark';

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
          'k8s.v1.cni.cncf.io/networks': [
            {
              name: 'index2ip-index-4-conf',
            },
          ],
          'prometheus.io/scrape': 'true',
          'prometheus.io/scheme': 'http',
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
                name: 'ARK_AUTH_TOKEN',
                value: 'replaceme',
              },
              {
                name: 'ARK_PROMETHEUS_EXPORTER',
                value: '1',
              },
              {
                name: 'DISABLE_ARK_ACTIVITY_TEAM',
                value: '1'
              },
              {
                name: 'DISABLE_ARK_ACTIVITY_V6',
                value: '1'
              },
              {
                name: 'SCAMPER_REMOTE',
                value: ''
              },
            ],
            image: 'caida/ark:latest',
            name: expName,
            ports: [
              {
                containerPort: 8000,
              },
            ],
            volumeMounts: [
              {
                mountPath: '/etc/ark',
                name: 'ark',
              },
            ],
          },
        ],
        nodeSelector: {
          'mlab/type': 'physical',
        },
        volumes: [
          {
            emptyDir: {},
            name: 'ark',
          },
        ]
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

