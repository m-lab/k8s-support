{
  kind: 'List',
  apiVersion: 'v1',
  items: std.flattenArrays([
    import 'config/configmaps.jsonnet',
    import 'k8s/custom-resource-definitions.jsonnet',
    import 'k8s/daemonsets.jsonnet',
    import 'k8s/deployments.jsonnet',
    import 'k8s/namespaces.jsonnet',
    import 'k8s/networks.jsonnet',
    import 'k8s/roles.jsonnet',
  ]),
}
