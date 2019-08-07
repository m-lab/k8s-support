{
  // These k8s objects will only be created in sandbox. To migrate them to
  // staging and production, remove them from this file and add them to
  // system.jsonnet.

  kind: 'List',
  apiVersion: 'v1',
  items: [
    // Configmaps

    // Custom resource definitions

    // Daemonsets
    import 'k8s/daemonsets/experiments/bismark.jsonnet',

    // Deployments

    // Namespaces

    // Networks (which are in array form already).

    // Roles (which are in array form already).
  ],
}
