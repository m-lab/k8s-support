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
      local cniConfig = {
        cniVersion: '0.3.0',
        name: 'flannel',
        type: 'flannel',
        delegate: {
          hairpinMode: true,
          isDefaultGateway: true,
        },
      },
      config: std.toString(cniConfig),
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
      local cniConfig = {
        cniVersion: '0.3.0',
        name: 'flannel',
        type: 'flannel',
        delegate: {
          hairpinMode: true,
          isDefaultGateway: false,
        },
      },
      config: std.toString(cniConfig),
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
      local cniConfig = {
        cniVersion: '0.3.1',
        name: 'ipvlan-index-' + index,
        plugins: [
          {
            type: 'netctl',
            ipam: {
              type: 'index2ip',
              index: index,
            },
            sysctl: {
              'net.ipv6.conf.default.accept_ra': '0',
              'net.ipv6.conf.default.autoconf': '0',
            },
          },
          {
            type: 'ipvlan',
            master: 'eth0',
          },
        ],
      },
      config: std.toString(cniConfig),
    },
  }
  for index in std.range(1, 12)
]
