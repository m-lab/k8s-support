{
  apiVersion: 'k8s.cni.cncf.io/v1beta2',
  kind: 'MultiNetworkPolicy',
  metadata: {
    name: 'wehe',
    namespace: 'default',
    annotations: {
      'k8s.v1.cni.cncf.io/policy-for': 'index2ip-index-5-conf',
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
            port: 80,
            protocol: 'TCP',
          },
          {
            port: 81,
            protocol: 'TCP',
          },
          {
            port: 443,
            protocol: 'TCP',
          },
          {
            port: 443,
            protocol: 'UDP',
          },
          {
            port: 465,
            protocol: 'TCP',
          },
          {
            port: 853,
            protocol: 'TCP',
          },
          {
            port: 993,
            protocol: 'TCP',
          },
          {
            port: 995,
            protocol: 'TCP',
          },
          {
            port: 1194,
            protocol: 'TCP',
          },
          {
            port: 1701,
            protocol: 'TCP',
          },
          {
            port: 3478,
            protocol: 'UDP',
          },
          {
            port: 3480,
            protocol: 'UDP',
          },
          {
            port: 4443,
            protocol: 'TCP',
          },
          {
            port: 5004,
            protocol: 'UDP',
          },
          {
            port: 5061,
            protocol: 'TCP',
          },
          {
            port: 6881,
            protocol: 'TCP',
          },
          {
            port: 8080,
            protocol: 'TCP',
          },
          {
            port: 8443,
            protocol: 'TCP',
          },
          {
            port: 8801,
            protocol: 'UDP',
          },
          {
            port: 9000,
            protocol: 'UDP',
          },
          {
            port: 9989,
            protocol: 'TCP',
          },
          {
            port: 19305,
            protocol: 'UDP',
          },
          {
            port: 35253,
            protocol: 'TCP',
          },
          {
            port: 49882,
            protocol: 'UDP',
          },
          {
            port: 50002,
            protocol: 'UDP',
          },
          {
            port: 55555,
            protocol: 'TCP',
          },
          {
            port: 55556,
            protocol: 'TCP',
          },
          {
            port: 55557,
            protocol: 'TCP',
          },
          {
            port: 56565,
            protocol: 'TCP',
          },
          {
            port: 56566,
            protocol: 'TCP',
          },
          {
            port: 62065,
            protocol: 'UDP',
          },
          {
            port: 63308,
            protocol: 'UDP',
          },
        ],
      },
    ],
  },
}

