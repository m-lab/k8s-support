{
  kind: 'List',
  apiVersion: 'v1',
  items: [
    // Configmaps
    import 'config/disco.jsonnet',
    import 'config/flannel.jsonnet',
    import 'config/fluentd.jsonnet',
    import 'config/nodeinfo.jsonnet',
    import 'config/prometheus.jsonnet',
    import 'config/nodes-max-rate.json',
    // Custom resource definitions
    import 'k8s/custom-resource-definitions/network-attachment-definition.jsonnet',
    // Daemonsets
    import 'k8s/daemonsets/core/cadvisor.jsonnet',
  ] + (
    // Don't deploy disco to prod or staging yet.
    if std.extVar('PROJECT_ID') == 'mlab-sandbox'
    then [import 'k8s/daemonsets/core/disco.jsonnet']
    else [import 'k8s/daemonsets/core/utilization.jsonnet']
  ) + [
    import 'k8s/daemonsets/core/dmesg-exporter.jsonnet',
    import 'k8s/daemonsets/core/flannel-virtual.jsonnet',
    import 'k8s/daemonsets/core/flannel-physical.jsonnet',
    import 'k8s/daemonsets/core/fluentd.jsonnet',
    import 'k8s/daemonsets/core/host.jsonnet',
    import 'k8s/daemonsets/core/kured.jsonnet',
    import 'k8s/daemonsets/core/node-exporter.jsonnet',
    import 'k8s/daemonsets/experiments/ndt.jsonnet',
    import 'k8s/daemonsets/experiments/ndtcloud.jsonnet',
    import 'k8s/daemonsets/experiments/neubot.jsonnet',
  ] + (
    // Don't deploy revtr to prod until all privacy i's and t's are dotted and crossed.
    // Don't deploy outside of sandbox until we are done debugging with Ege
    if std.extVar('PROJECT_ID') == 'mlab-sandbox'
    then [import 'k8s/daemonsets/experiments/revtr.jsonnet']
    else []
  ) + (
    // Don't deploy wehe to prod until we understand what it does and why it's RAM usage is so high.
    if std.extVar('PROJECT_ID') != 'mlab-oti'
    then [import 'k8s/daemonsets/experiments/wehe.jsonnet']
    else []
  ) + [
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
  ] + std.flattenArrays([
    // Networks (which are in array form already).
    import 'k8s/networks/networks.jsonnet',
    // Roles (which are in array form already).
    import 'k8s/roles/flannel.jsonnet',
    import 'k8s/roles/fluentd.jsonnet',
    import 'k8s/roles/kube-rbac-proxy.jsonnet',
    import 'k8s/roles/kube-state-metrics.jsonnet',
    import 'k8s/roles/kured.jsonnet',
    import 'k8s/roles/rbac-prometheus.jsonnet',
    import 'k8s/roles/reloader.jsonnet',
  ]),
}
