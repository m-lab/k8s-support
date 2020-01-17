{
  kind: 'List',
  apiVersion: 'v1',
  items: [
    // Configmaps
    import 'config/flannel.jsonnet',
    import 'config/fluentd.jsonnet',
    import 'config/nodeinfo.jsonnet',
    import 'config/prometheus.jsonnet',
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
    import 'k8s/daemonsets/core/utilization.jsonnet',
    import 'k8s/daemonsets/experiments/ndt.jsonnet',
    import 'k8s/daemonsets/experiments/ndtcloud.jsonnet',
    import 'k8s/daemonsets/experiments/neubot.jsonnet',
    import 'k8s/daemonsets/experiments/wehe.jsonnet',
    // Deployments
    import 'k8s/deployments/kube-state-metrics.jsonnet',
    import 'k8s/deployments/prometheus.jsonnet',
    import 'k8s/deployments/update-operator.jsonnet',
    // Namespaces
    import 'k8s/namespaces/reboot-operator.jsonnet',
    // ClusterIssuers
    // The letsencrypt-staging is provided to test new TLS
    // services but commented out here by default.
    // import 'k8s/clusterissuers/letsencrypt-staging.jsonnet',
    import 'k8s/clusterissuers/letsencrypt.jsonnet',
    // Services
    import 'k8s/services/prometheus-tls.jsonnet',
    import 'k8s/services/prometheus-tls-ingress.jsonnet',
  ] + std.flattenArrays([
    // Networks (which are in array form already).
    import 'k8s/networks/networks.jsonnet',
    // Roles (which are in array form already).
    import 'k8s/roles/update-operator.jsonnet',
    import 'k8s/roles/flannel.jsonnet',
    import 'k8s/roles/fluentd.jsonnet',
    import 'k8s/roles/kube-rbac-proxy.jsonnet',
    import 'k8s/roles/kube-state-metrics.jsonnet',
    import 'k8s/roles/rbac-prometheus.jsonnet',
  ]),
}
