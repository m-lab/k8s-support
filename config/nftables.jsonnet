local data = {
  'ndt.conf': importstr 'nftables/ndt.conf',
  'msak.conf': importstr 'nftables/msak.conf',
  'revtr.conf': importstr 'nftables/revtr.conf',
  'wehe.conf': importstr 'nftables/wehe.conf',
  'neubot.conf': importstr 'nftables/neubot.conf',
};

{
  apiVersion: 'v1',
  data: data,
  kind: 'ConfigMap',
  metadata: {
    name: 'nftables-rules',
  },
}

