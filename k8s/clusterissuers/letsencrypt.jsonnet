{
  apiVersion: 'cert-manager.io/v1',
  kind: 'ClusterIssuer',
  metadata: {
    name: 'letsencrypt',
  },
  spec: {
    acme: {
      email: 'support@measurementlab.net',
      server: 'https://acme-v02.api.letsencrypt.org/directory',
      privateKeySecretRef: {
        name: 'letsencrypt-key',
      },
      solvers: [
        {
          http01: {
            ingress: {
              class: 'nginx',
            },
          },
          selector: {
            dnsNames: [
              'prometheus-platform-cluster.' + std.extVar('PROJECT_ID') + '.measurementlab.net',
              'prometheus-platform-cluster-basicauth.' + std.extVar('PROJECT_ID') + '.measurementlab.net',
            ],
          },
        },
        {
          dns01: {
            cloudDNS: {
              project: std.extVar('PROJECT_ID'),
              serviceAccountSecretRef: {
                name: 'cert-manager-credentials',
                key: 'cert-manager.json',
              },
            },
            cnameStrategy: 'Follow',
          },
          selector: {
            dnsNames: (if std.extVar('PROJECT_ID') == 'mlab-oti' then [
              '*.measurement-lab.org',
            ] else []) + [
              '*.' + std.extVar('PROJECT_ID') + '.measurement-lab.org',
              '*.mlab.' + std.split(std.extVar('PROJECT_ID'), '-')[1] + '.measurement-lab.org',
            ],
          },
        },
      ],
    },
  },
}
