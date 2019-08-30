local cmutil = import 'configmap.jsonnet';
local outputConfMissingProjectAndZone = importstr 'fluentd/output.conf.template';
local outputConfMissingZone = std.strReplace(outputConfMissingProjectAndZone, '{{PROJECT_ID}}', std.extVar('PROJECT_ID'));
local outputConf = std.strReplace(outputConfMissingZone, '{{GCE_ZONE}}', std.extVar('GCE_ZONE'));

local data = {
  'containers.input.conf': importstr 'fluentd/containers.input.conf',
  'monitoring.conf': importstr 'fluentd/monitoring.conf',
  'output.conf': outputConf,
};

{
  kind: 'ConfigMap',
  apiVersion: 'v1',
  metadata: cmutil.metadata('fluentd-config', data),
  data: data,
}
