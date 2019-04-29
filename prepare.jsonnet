{
   kind: 'List',
   apiVersion: 'v1',
   items: std.flattenArrays([
      import 'k8s/custom-resource-definitions.jsonnet',
      import 'k8s/namespaces.jsonnet',
      import 'k8s/roles.jsonnet',
   ]),
}
