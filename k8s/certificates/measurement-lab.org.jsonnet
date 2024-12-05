{
  apiVersion: 'cert-manager.io/v1',
  kind: 'Certificate',
  metadata: {
    name: std.extVar('PROJECT_ID') + '-measurement-lab-org',
    namespace: 'default',
  },
  spec: {
    dnsNames: (if std.extVar('PROJECT_ID') == 'mlab-oti' then [
      '*.measurement-lab.org',
      '*.mlab.autojoin.measurement-lab.org',
    ] else []) + [
      '*.' + std.extVar('PROJECT_ID') + '.measurement-lab.org',
      '*.mlab.' + std.split(std.extVar('PROJECT_ID'), '-')[1] + '.measurement-lab.org',
    ],
    issuerRef: {
      group: 'cert-manager.io',
      kind: 'ClusterIssuer',
      name: 'letsencrypt',
    },
    secretName: 'measurement-lab-org-tls',
  },
}
