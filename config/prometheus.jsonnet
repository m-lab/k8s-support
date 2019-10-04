local cmutil = import 'configmap.jsonnet';
local promconfig = std.strReplace(
    importstr 'prometheus/prometheus.yml.template',
    '{{PROJECT}}',
    std.extVar('PROJECT_ID')
);

local data = {
    'rules.yml': importstr 'prometheus/rules.yml',
    'prometheus.yml': promconfig,
};

{
  kind: 'ConfigMap',
  apiVersion: 'v1',
  metadata: cmutil.metadata('prometheus-config', data),
  data: data,
}
