{
  apiVersion: 'k8s.cni.cncf.io/v1beta2',
  kind: 'MultiNetworkPolicy',
  metadata: {
    name: 'revtr',
    namespace: 'default',
    annotations: {
      'k8s.v1.cni.cncf.io/policy-for': 'index2ip-index-3-conf',
    },
  },
  spec: {
    podSelector: {
      matchLabels: {
        workload: 'revtr',
      },
    },
    policyTypes: [
      'Ingress',
    ],
    ingress: [
      {
        ports: [
          {
            port: 55557,
            protocol: 'TCP',
          },
        ],
      },
    ],
  },
}

