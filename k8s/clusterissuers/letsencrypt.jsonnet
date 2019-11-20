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
        },
      ],
    },
  },
}