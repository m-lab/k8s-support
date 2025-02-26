local data = {
  'ndt.conf': importstr 'nftables/ndt.conf',
  'neubot.conf': importstr 'nftables/neubot.conf',
  'msak.conf': importstr 'nftables/msak.conf',
  'pt.conf': importstr 'nftables/pt.conf',
  'revtr.conf': importstr 'nftables/revtr.conf',
  'wehe.conf': importstr 'nftables/wehe.conf',
};

{
  apiVersion: 'v1',
  data: data,
  kind: 'ConfigMap',
  metadata: {
    name: 'nftables-rules',
  },
}

