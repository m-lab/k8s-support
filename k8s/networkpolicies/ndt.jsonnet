{
  apiVersion: 'k8s.cni.cncf.io/v1beta2',
  kind: 'MultiNetworkPolicy',
  metadata: {
    name: 'ndt',
    namespace: 'default',
    annotations: {
      'k8s.v1.cni.cncf.io/policy-for': 'index2ip-index-2-conf',
    },
  },
  spec: {
    namespaceSelector: {},
    podSelector: {},
    policyTypes: [
      'Ingress',
    ],
    ingress: [
      {
        ports: [
          {
            port: 80,
            protocol: 'TCP',
          },
          {
            port: 443,
            protocol: 'TCP',
          },
          {
            port: 3001,
            protocol: 'TCP',
          },
          {
            port: 3010,
            protocol: 'TCP',
          },
          {
            port: 32768,
            endPort: 60999,
            protocol: 'TCP',
          },
        ],
      },
    ],
  },
}
