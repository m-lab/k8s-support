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
        },
      ],
    },
  },
}