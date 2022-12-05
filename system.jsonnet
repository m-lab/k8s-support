{
  kind: 'List',
  apiVersion: 'v1',
  items: [
    // Configmaps
    import 'config/disco.jsonnet',
    import 'config/flannel.jsonnet',
    import 'config/nodeinfo.jsonnet',
    import 'config/prometheus.jsonnet',
    // Custom resource definitions
    import 'k8s/custom-resource-definitions/network-attachment-definition.jsonnet',
    // Daemonsets
    import 'k8s/daemonsets/core/cadvisor.jsonnet',
    import 'k8s/daemonsets/core/disco.jsonnet',
    import 'k8s/daemonsets/core/flannel-virtual.jsonnet',
    import 'k8s/daemonsets/core/flannel-physical.jsonnet',
    import 'k8s/daemonsets/core/host.jsonnet',
    import 'k8s/daemonsets/core/kured.jsonnet',
    import 'k8s/daemonsets/core/node-exporter.jsonnet',
    import 'k8s/daemonsets/experiments/ndt.jsonnet',
    import 'k8s/daemonsets/experiments/ndt-virtual.jsonnet',
    import 'k8s/daemonsets/experiments/ndt-canary.jsonnet',
    import 'k8s/daemonsets/experiments/neubot.jsonnet',
    import 'k8s/daemonsets/experiments/revtr.jsonnet',
  ] + (
    if std.extVar('PROJECT_ID') == 'mlab-sandbox' then [
      import 'k8s/daemonsets/experiments/responsiveness.jsonnet',
      import 'k8s/daemonsets/experiments/msak.jsonnet',
    ] else []
  ) + [
    import 'k8s/daemonsets/experiments/wehe.jsonnet',
    // Deployments
    import 'k8s/deployments/kube-state-metrics.jsonnet',
    import 'k8s/deployments/prometheus.jsonnet',
    import 'k8s/deployments/reloader.jsonnet',
    // ClusterIssuers
    // letsencrypt-staging is provided to test new TLS services
    import 'k8s/clusterissuers/letsencrypt-staging.jsonnet',
    import 'k8s/clusterissuers/letsencrypt.jsonnet',
    //Certificates
    import 'k8s/certificates/measurement-lab.org.jsonnet',
    // Services
    import 'k8s/services/prometheus-tls.jsonnet',
    import 'k8s/services/prometheus-tls-ingress.jsonnet',
    import 'k8s/services/prometheus-tls-basic-ingress.jsonnet',
  ] + std.flattenArrays([
    // Networks (which are in array form already).
    import 'k8s/networks/networks.jsonnet',
    // Roles (which are in array form already).
    import 'k8s/roles/flannel.jsonnet',
    import 'k8s/roles/heartbeat-experiment.jsonnet',
    import 'k8s/roles/kube-rbac-proxy.jsonnet',
    import 'k8s/roles/kube-state-metrics.jsonnet',
    import 'k8s/roles/kured.jsonnet',
    import 'k8s/roles/rbac-prometheus.jsonnet',
    import 'k8s/roles/reloader.jsonnet',
  ]),
}
