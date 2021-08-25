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
        cniVersion: '0.2.0',
        name: 'ipvlan-index-' + index,
        plugins: [
          {
            type: 'ipvlan',
            master: 'eth0',
            ipam: {
              type: 'index2ip',
              index: index,
            },
          },
          // For now, the tuning plugin needs to be run after ipvlan. This is
          // because the index2ip plugin is still using CNI spec v0.2.0, and
          // does not properly handle the 'prevResult' field. Putting tuning
          // first, which we would like to do, results in the error: 'Required
          // "prevResult" missing'. If a plugin is passed a 'prevResult' field,
          // then it _must_ output the field, which the index2ip plugin surely
          // does not do. Ultimately, we want tuning first, so that sysctls get
          // set before the ipvlan interface is even created. See this issue:
          // https://github.com/m-lab/index2ip/issues/8
          //
          // TODO(kinkade): when the above issue is resolved, move tuning to be
          // the first plugin in the list.
          {
            type: 'tuning',
            sysctl: {
              'net.ipv6.conf.net1.accept_ra': '0',
              'net.ipv6.conf.net1.autoconf': '0',
            },
          },
        ],
      },
      config: std.toString(cniConfig),
    },
  }
  for index in std.range(1, 12)
]
