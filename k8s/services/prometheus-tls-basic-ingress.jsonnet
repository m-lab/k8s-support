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
        // We generate a single certificate for the OAuth and the basic auth 
        // domains. The reason for this is that LetsEncrypt's CN fields cannot
        // be longer than 64 characters, and the -basicauth is just barely
        // above that. By putting them together, only the first domain is used
        // in the CN field.
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
