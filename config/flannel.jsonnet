// This file/config is for Flannel
local netConf = {
  Network: std.extVar('K8S_CLUSTER_CIDR'),
  SubnetLen: 26,
  Backend: {
    Type: 'vxlan',
  },
};

// This is the CNI config needed for the cloud machines.
local cloudCNIConf = {
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

// This is the CNI config needed for the platform nodes.
// It should not contain any index2ip stuff. It is the backup config for when
// multus isn't working or a pod is not tagged with any network annotations.
local platformNodeCNIConf = {
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
    'cloud-cni-conf.json': std.toString(cloudCNIConf),
    'platform-node-cni-conf.json': std.toString(platformNodeCNIConf),
  },
}
