// This file/config is for Flannel
local netConf = {
  Network: std.extVar('K8S_CLUSTER_CIDR'),
  SubnetLen: 26,
  Backend: {
    Type: 'vxlan',
  },
};

// This is the CNI config needed for the virtual machines.
local virtualCNIConf = {
  name: 'cbr0',
  plugins: [
    {
      type: 'flannel',
      delegate: {
        hairpinMode: true,
        isDefaultGateway: true,
        forceAddress: true,
      },
    },
    {
      type: 'portmap',
      capabilities: {
        portMappings: true,
      },
    },
  ],
};

// This is the CNI config needed for the physical nodes.
// It should not contain any index2ip stuff. It is the backup config for when
// multus isn't working or a pod is not tagged with any network annotations.
local physicalCNIConf = {
  name: 'multus-network',
  type: 'multus',
  kubeconfig: '/etc/kubernetes/kubelet.conf',
  multusNamespace: 'default',
  clusterNetwork: 'flannel-conf',
};

{
  kind: 'ConfigMap',
  apiVersion: 'v1',
  metadata: {
    name: 'kube-flannel-cfg',
    namespace: 'kube-system',
    labels: {
      tier: 'node',
      app: 'flannel',
    },
  },
  data: {
    'net-conf.json': std.toString(netConf),
    'virtual-cni-conf.json': std.toString(virtualCNIConf),
    'physical-cni-conf.json': std.toString(physicalCNIConf),
  },
}
