{
  kind: 'ConfigMap',
  apiVersion: 'v1',
  metadata: {
    name: 'multi-networkpolicy-custom-rules',
    namespace: 'kube-system',
    labels: {
      tier: 'node',
      app: 'multi-networkpolicy',
    },
  },
  // Add custom iptables rules below. The rules will not be applied unless you
  // pass at least one of the following flags to multi-networkpolicy-iptables
  // in the multi-networkpolicy DaemonSet in
  // k8s/daemonsets/core/multi-networkpolicy.jsonnet:
  //
  //   --custom-v4-igress-rule-file
  //   --custom-v4-egress-rule-file
  //   --custom-v6-igress-rule-file
  //   --custom-v4-egress-rule-file
  //
  // Add iptables rules one per line in the appropriate sections below, minus
  // "iptables -A <chain>" as that is added for you by
  // multi-networkpolicy-iptables.
  data: {
    'custom-v4-ingress-rules.txt': |||
      # No custom rules, yet.
    |||,
    'custom-v4-egress-rules.txt': |||
      # No custom rules, yet.
    |||,
    'custom-v6-ingress-rules.txt': |||
      # No custom rules, yet.
    |||,
    'custom-v6-egress-rules.txt': |||
      # No custom rules, yet.
    |||,
  },
}

