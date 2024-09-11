// NOTE: CNI configs located on each node in /etc/cni/net.d are baked into
// machines images through epoxy-images. If one of those needs to change, then
// do it there:
//
// https://github.com/m-lab/epoxy-images/tree/main/configs/stage3_ubuntu/etc/cni/net.d/00-multus.conf
// https://github.com/m-lab/epoxy-images/tree/main/configs/virtual_ubuntu/etc/cni/net.d/00-multus.conf

// This file/config is for Flannel
local netConf = {
  Network: std.extVar('K8S_CLUSTER_CIDR'),
  SubnetLen: 26,
  Backend: {
    Type: 'vxlan',
  },
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
  },
}

