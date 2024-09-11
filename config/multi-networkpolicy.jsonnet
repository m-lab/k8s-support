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
  data: {
    'custom-v4-rules.txt': '# accept redirect\n-p icmp --icmp-type redirect -j ACCEPT\n# accept fragmentation-needed (for MTU discovery)\n-p icmp --icmp-type fragmentation-needed -j ACCEPT\n',
  },
    'custom-v6-rules.txt': '# accept NDP\n-p icmpv6 --icmpv6-type neighbor-solicitation -j ACCEPT\n-p icmpv6 --icmpv6-type neighbor-advertisement -j ACCEPT\n# accept RA/RS\n-p icmpv6 --icmpv6-type router-solicitation -j ACCEPT\n-p icmpv6 --icmpv6-type router-advertisement -j ACCEPT\n# accept redirect\n-p icmpv6 --icmpv6-type redirect -j ACCEPT\n# accept packet-too-big (for MTU discovery)\n-p icmpv6 --icmpv6-type packet-too-big -j ACCEPT\n',
}

