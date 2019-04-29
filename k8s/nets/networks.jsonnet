[
  // The default flannel configuration that gets applied to non-experiment pods.
  // The important difference here is that isDefaultGateway=true.
  {
    apiVersion: 'k8s.cni.cncf.io/v1',
    kind: 'NetworkAttachmentDefinition',
    metadata: {
      name: 'flannel-conf',
    },
    spec: {
      config: '{ "cniVersion": "0.3.0", "type": "flannel", "delegate": { "hairpinMode": true, "isDefaultGateway": true } }',
    },
  },
  // The flannel configuration that gets applied to experiment pods. Only pods
  // with the following annotation will use this configuration:
  // `v1.multus-cni.io/default-network: flannel-experiment-conf`
  {
    apiVersion: 'k8s.cni.cncf.io/v1',
    kind: 'NetworkAttachmentDefinition',
    metadata: {
      name: 'flannel-experiment-conf',
    },
    spec: {
      config: '{ "cniVersion": "0.3.0", "type": "flannel", "delegate": { "hairpinMode": true, "isDefaultGateway": false } }',
    },
  },
] + [
  // The index2ip configuration gets applied to M-Lab experiments. Each
  // experiment has an index (a number 1-12). The code below creates 12
  // network configurations, named "index2ip-index-1-conf" through
  // "index2ip-index-12-conf".
  {
    apiVersion: 'k8s.cni.cncf.io/v1',
    kind: 'NetworkAttachmentDefinition',
    metadata: {
      name: 'index2ip-index-' + index + '-conf',
    },
    spec: {
      config: '{ "cniVersion": "0.2.0", "name": "ipvlan-index-' + index + '", "type": "ipvlan", "master": "eth0", "ipam": { "type": "index2ip", "index": ' + index + '" } }',
    },
  }
  for index in std.range(1, 12)
]
