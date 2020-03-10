{
  apiVersion: 'cert-manager.io/v1alpha2',
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
            dnsNames: [
              '*.measurement-lab.org',
              '*.' + std.extVar('PROJECT_ID') + '.measurement-lab.org',
            ],
          },
        },
      ],
    },
  },
}
