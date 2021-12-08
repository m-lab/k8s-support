{
  apiVersion: 'networking.k8s.io/v1',
  kind: 'Ingress',
  metadata: {
    name: 'prometheus-tls',
    namespace: 'default',
    annotations: {
      'kubernetes.io/tls-acme': 'true',
      'kubernetes.io/ingress.class': 'nginx',
      'nginx.ingress.kubernetes.io/auth-url': 'https://prometheus.' + std.extVar('PROJECT_ID') + '.measurementlab.net/oauth2/auth',
      'nginx.ingress.kubernetes.io/auth-signin': 'https://prometheus.' + std.extVar('PROJECT_ID') +
        '.measurementlab.net/oauth2/start?rd=https://prometheus-platform-cluster.' + std.extVar('PROJECT_ID') + '.measurementlab.net$escaped_request_uri',
      'nginx.ingress.kubernetes.io/configuration-snippet': |||
        auth_request_set $user   $upstream_http_x_auth_request_user;
        auth_request_set $email  $upstream_http_x_auth_request_email;
        proxy_set_header X-User  $user;
        proxy_set_header X-Email $email;
      |||,
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
        host: 'prometheus-platform-cluster.' + std.extVar('PROJECT_ID') + '.measurementlab.net',
        http: {
          paths: [
            {
              path: '/',
              backend: {
                service: {
                  name: 'prometheus-tls',
                  port: {
                    number: 9090,
                  },
                },
              },
            },
          ],
        },
      },
    ],
  },
}
