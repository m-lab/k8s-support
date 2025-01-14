local data = {
  name: 'generic-veth',
  cniVersion: '0.3.1',
  plugins: [
    {
      type: 'cilium-cni',
    },
    {
      "cniVersion": "0.3.1",
      "kubeconfig": "/etc/kubernetes/kubelet.conf",
      "multusNamespace": "default",
      "name": "multus-network",
      "type": "multus"
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

