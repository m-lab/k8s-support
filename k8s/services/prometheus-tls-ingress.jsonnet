{
  apiVersion: 'extensions/v1beta1',
  kind: 'Ingress',
  metadata: {
    name: 'prometheus-tls',
    namespace: 'default',
    annotations: {
      'kubernetes.io/tls-acme': 'true',
      'kubernetes.io/ingress.class': 'nginx',
    },
  },
  spec: {
    tls: [
      {
        hosts: [
          'prometheus-platform-cluster.mlab-sandbox.measurementlab.net',
        ],
        secretName: 'prometheus-tls',
      },
    ],
    rules: [
      {
        host: 'prometheus-platform-cluster.mlab-sandbox.measurementlab.net',
        http: {
          paths: [
            {
              path: '/',
              backend: {
                serviceName: 'prometheus-tls',
                servicePort: 9090,
              },
            },
          ],
        },
      },
    ],
  },
}