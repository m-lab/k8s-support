local data = {
  name: 'generic-veth',
  cniVersion: '0.3.1',
  plugins: [
    {
      type: 'netctl',
      log_level: 'info',
      datastore_type: 'kubernetes',
      mtu: '1440,q',
      ipam: {
        type: 'index2ip',
      },
      policy: {
        type: 'k8s',
      },
      kubernetes: {
        kubeconfig: '/etc/cni/net.d/00-multus.conf',
      },
    },
    {
      type: 'ipvlan',
      master: 'eth0',
    },
    {
      type: 'cilium-cni',
    },
  ],
};

{
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: {
    name: 'cilium-cni-configuration',
    namespace: 'kube-system',
  },
  data: {
    'cni-config': std.toString(data),
  },
}

