// NOTE: This file is not named *-staging for having anything to do with the
// mlab-staging project, but instead denotes that this ClusterIssuer uses the
// LetsEncrypt staging endpoint instead of the production one, which has looser
// limits and is better for testing, though it doesn't produce globally valid
// TLS certs.
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
            cnameStrategy: 'Follow',
          },
          selector: {
            dnsNames: (if std.extVar('PROJECT_ID') == 'mlab-oti' then [
              '*.measurement-lab.org',
            ] else []) + [
              '*.' + std.extVar('PROJECT_ID') + '.measurement-lab.org',
            ],
          },
        },
      ],
    },
  },
}
