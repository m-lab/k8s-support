{
  apiVersion: 'cert-manager.io/v1alpha2',
  kind: 'ClusterIssuer',
  metadata: {
    name: 'letsencrypt-staging',
  },
  spec: {
    acme: {
      email: 'support@measurementlab.net',
      server: 'https://acme-staging-v02.api.letsencrypt.org/directory',
      privateKeySecretRef: {
        name: 'letsencrypt-staging-key',
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
            ],
          },
        },
        {
          dns01: {
            clouddns: {
              project: std.extVar('PROJECT_ID'),
              serviceAccountSecretRef: {
                name: 'cert-manager-credentials',
                key: 'cert-manager.json',
              },
            },
          },
          selector: {
            dnsNames: if std.extVar('PROJECT_ID') == 'mlab-oti' then [
              '*.measurement-lab.org',
            ] else [] + [
              '*.' + std.extVar('PROJECT_ID') + '.measurement-lab.org',
            ],
          },
        },
      ],
    },
  },
}
