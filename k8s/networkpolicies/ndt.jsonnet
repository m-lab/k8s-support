{
  apiVersion: 'k8s.cni.cncf.io/v1beta1',
  kind: 'MultiNetworkPolicy',
  metadata: {
    name: 'ndt-network-policy',
    namespace: 'default',
    annotations: {
      'k8s.v1.cni.cncf.io/policy-for': 'index2ip-index-2-conf',
    },
  },
  spec: {
    podSelector: {},
    policyTypes: [
      'Ingress',
    ],
    ingress: [
      {
        ports: [
          {
            protocol: 'TCP',
            port: 80,
          },
          {
            protocol: 'TCP',
            port: 443,
          },
        ],
      },
    ],
  },
}
