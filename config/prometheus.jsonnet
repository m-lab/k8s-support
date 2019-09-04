local cmutil = import 'configmap.jsonnet';

local data = {
    'rules.yml': importstr 'prometheus/rules.yml',
    'prometheus.yml': importstr 'prometheus/prometheus.yml',
};

{
  kind: 'ConfigMap',
  apiVersion: 'v1',
  metadata: cmutil.metadata('prometheus-config', data),
  data: data,
}
