{
  kind: 'List',
  apiVersion: 'v1',
  items: [
    // Configmaps
    import 'config/disco.jsonnet',
    import 'config/flannel.jsonnet',
    import 'config/multi-networkpolicy.jsonnet',
    import 'config/nodeinfo.jsonnet',
    import 'config/prometheus.jsonnet',
    // Custom resource definitions
    import 'k8s/custom-resource-definitions/multi-networkpolicy.jsonnet',
    import 'k8s/custom-resource-definitions/network-attachment-definition.jsonnet',
    // Daemonsets
    import 'k8s/daemonsets/core/cadvisor.jsonnet',
    import 'k8s/daemonsets/core/disco.jsonnet',
    import 'k8s/daemonsets/core/flannel.jsonnet',
    import 'k8s/daemonsets/core/host.jsonnet',
    import 'k8s/daemonsets/core/node-exporter.jsonnet',
    import 'k8s/daemonsets/core/multi-networkpolicy.jsonnet',
  ] + std.flattenArrays([
    import 'k8s/daemonsets/experiments/msak.jsonnet',
    import 'k8s/daemonsets/experiments/ndt.jsonnet',
    import 'k8s/daemonsets/experiments/revtr.jsonnet',
    import 'k8s/daemonsets/experiments/wehe.jsonnet',
    import 'k8s/daemonsets/experiments/neubot.jsonnet',
  ]) + [
    import 'k8s/daemonsets/experiments/ndt-virtual.jsonnet',
    import 'k8s/daemonsets/experiments/ndt-canary.jsonnet',
    import 'k8s/daemonsets/experiments/packet-test.jsonnet',
  ] + (
    if std.extVar('PROJECT_ID') == 'mlab-sandbox' then [
      // responsiveness commented out by Kinkade. It's stuck in sandbox and not
      // really being used, and must be run as root because is has
      // hostNetwork=true. If we want to resume the experiment we can just
      // uncomment the following line.
      //import 'k8s/daemonsets/experiments/responsiveness.jsonnet',
    ] else []
  ) + (
    if std.extVar('PROJECT_ID') != 'mlab-oti' then [
      // A internal Google service we are experimenting with only in sandbox
      // and staging.
      import 'k8s/daemonsets/core/flooefi.jsonnet',
    ] else []
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
    import 'k8s/services/prometheus-tls-basic-ingress.jsonnet',
  ] + std.flattenArrays([
    // Networks (which are in array form already).
    import 'k8s/networks/networks.jsonnet',
    // Roles (which are in array form already).
    import 'k8s/roles/flannel.jsonnet',
    import 'k8s/roles/heartbeat-experiment.jsonnet',
    import 'k8s/roles/kube-rbac-proxy.jsonnet',
    import 'k8s/roles/kube-state-metrics.jsonnet',
    import 'k8s/roles/multi-networkpolicy.jsonnet',
    import 'k8s/roles/rbac-prometheus.jsonnet',
    import 'k8s/roles/reloader.jsonnet',
  ]),
}
