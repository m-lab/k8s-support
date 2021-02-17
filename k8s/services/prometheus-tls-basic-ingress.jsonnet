{
  apiVersion: 'networking.k8s.io/v1beta1',
  kind: 'Ingress',
  metadata: {
    name: 'prometheus-tls-basic',
    namespace: 'default',
    annotations: {
      'kubernetes.io/tls-acme': 'true',
      'kubernetes.io/ingress.class': 'nginx',
      'nginx.ingress.kubernetes.io/auth-type': 'basic',
      'nginx.ingress.kubernetes.io/auth-secret': 'prometheus-htpasswd',
      'nginx.ingress.kubernetes.io/auth-realm': 'Authentication Required',
    },
  },
  spec: {
    tls: [
      {
        hosts: [
          'prometheus-platform-cluster.' + std.extVar('PROJECT_ID') + '.measurementlab.net',
          'prometheus-platform-cluster-basicauth.' + std.extVar('PROJECT_ID') + '.measurementlab.net',
        ],
        secretName: 'prometheus-tls',
      },
    ],
    rules: [
      {
        host: 'prometheus-platform-cluster-basicauth.' + std.extVar('PROJECT_ID') + '.measurementlab.net',
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
