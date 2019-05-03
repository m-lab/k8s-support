{
  kind: 'ConfigMap',
  apiVersion: 'v1',
  metadata: {
    name: 'prometheus-synthetic-textfile-metrics',
  },
  data: {
    'collectd.prom': importstr 'prometheus-synthetic-textfile-metrics/collectd.prom',
    'lame_duck.prom': importstr 'prometheus-synthetic-textfile-metrics/lame_duck.prom',
    'vdlimit.prom': importstr 'prometheus-synthetic-textfile-metrics/vdlimit.prom',
  },
}
