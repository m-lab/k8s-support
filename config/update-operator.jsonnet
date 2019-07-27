{
  kind: 'ConfigMap',
  apiVersion: 'v1',
  metadata: {
    name: 'update-operator-config',
    namespace: 'reboot-coordinator',
  },
  data: {
    'annotate-node.sh': importstr 'update-operator/annotate-node.sh',
  },
}
