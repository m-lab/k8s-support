local cmutil = import 'configmap.jsonnet';

local data = {
  'alerts.yml': importstr 'prometheus/alerts.yml',
  'rules.yml': importstr 'prometheus/rules.yml',
  'prometheus.yml': std.strReplace(importstr 'prometheus/prometheus.yml', '{{PROJECT}}', std.extVar('PROJECT_ID')),
};

{
  kind: 'ConfigMap',
  apiVersion: 'v1',
  metadata: cmutil.metadata('prometheus-config', data),
  data: data,
}
