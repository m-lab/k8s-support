local cmutil = import 'configmap.jsonnet';

local data = {
    'metrics.yaml': importstr 'disco/metrics.yaml',
};

{
  kind: 'ConfigMap',
  apiVersion: 'v1',
  metadata: cmutil.metadata('disco-config', data),
  data: data,
}
