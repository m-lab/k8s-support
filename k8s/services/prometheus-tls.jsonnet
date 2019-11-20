{
  apiVersion: 'v1',
  kind: 'Service',
  metadata: {
    name: 'prometheus-tls',
  },
  spec: {
    ports: [
      {
        port: 9090,
        protocol: 'TCP',
        targetPort: 9090,
      },
    ],
    selector: {
      workload: 'prometheus-server',
    },
  },
}