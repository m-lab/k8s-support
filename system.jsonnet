{
  kind: 'List',
  apiVersion: 'v1',
  items: [
    // Configmaps
    import 'config/flannel.jsonnet',
    import 'config/fluentd.jsonnet',
    import 'config/nodeinfo.jsonnet',
    import 'config/prometheus.jsonnet',
    import 'config/prometheus-synthetic-textfile-metrics.jsonnet',
    import 'config/pusher.jsonnet',
    // Custom resource definitions
    import 'k8s/custom-resource-definitions/network-attachment-definition.jsonnet',
    // Daemonsets
    import 'k8s/daemonsets/core/cadvisor.jsonnet',
    import 'k8s/daemonsets/core/flannel-cloud.jsonnet',
    import 'k8s/daemonsets/core/flannel-platform.jsonnet',
    import 'k8s/daemonsets/core/fluentd.jsonnet',
    import 'k8s/daemonsets/core/host.jsonnet',
    import 'k8s/daemonsets/core/node-exporter.jsonnet',
    import 'k8s/daemonsets/core/update-agent.jsonnet',
    import 'k8s/daemonsets/experiments/bismark.jsonnet',
    import 'k8s/daemonsets/experiments/ndt.jsonnet',
    // Deployments
    import 'k8s/deployments/kube-state-metrics.jsonnet',
    import 'k8s/deployments/prometheus.jsonnet',
    import 'k8s/deployments/update-operator.jsonnet',
    // Namespaces
    import 'k8s/namespaces/reboot-operator.jsonnet',
  ] + std.flattenArrays([
    // Networks (which are in array form already).
    import 'k8s/networks/networks.jsonnet',
    // Roles (which are in array form already).
    import 'k8s/roles/container-linux-update-coordinator.jsonnet',
    import 'k8s/roles/flannel.jsonnet',
    import 'k8s/roles/kube-rbac-proxy.jsonnet',
    import 'k8s/roles/kube-state-metrics.jsonnet',
    import 'k8s/roles/rbac-prometheus.jsonnet',
  ]),
}
