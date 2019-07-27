{
  kind: 'ConfigMap',
  apiVersion: 'v1',
  metadata: {
    name: 'update-operator-config',
  },
  data: {
    'annotate-node.sh': importstr 'update-operator/annotate-node.sh',
  },
}
