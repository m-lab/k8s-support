{
  kind: 'List',
  apiVersion: 'v1',
  items: [
    // Daemonsets
    import 'k8s/daemonsets/core/host.jsonnet',
    import 'k8s/daemonsets/experiments/bismark.jsonnet',
    import 'k8s/daemonsets/experiments/ndt.jsonnet',
  ],
}
