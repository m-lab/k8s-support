{
  apiVersion: 'cert-manager.io/v1alpha2',
  kind: 'Certificate',
  metadata: {
    name: std.extVar('PROJECT_ID') + '-measurement-lab-org',
    namespace: 'default',
  },
  spec: {
    dnsNames: [
      if std.extVar('PROJECT_ID') == 'mlab-oti' then '*.measurement-lab.org' else '',
      '*.' + std.extVar('PROJECT_ID') + '.measurement-lab.org',
    ],
    issuerRef: {
      group: 'cert-manager.io',
      kind: 'ClusterIssuer',
      name: 'letsencrypt-staging',
    },
    secretName: std.extVar('PROJECT_ID') + '-measurment-lab-org-tls',
  },
}
