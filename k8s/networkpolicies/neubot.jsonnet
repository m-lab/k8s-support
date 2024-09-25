{
  apiVersion: 'k8s.cni.cncf.io/v1beta2',
  kind: 'MultiNetworkPolicy',
  metadata: {
    name: 'neubot',
    namespace: 'default',
    annotations: {
      'k8s.v1.cni.cncf.io/policy-for': 'index2ip-index-10-conf',
    },
  },
  spec: {
    podSelector: {
      matchLabels: {
        workload: 'neubot',
      },
    },
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
        ],
      },
    ],
  },
}

