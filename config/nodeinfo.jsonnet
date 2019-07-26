local cmutil = import 'cloudmap-utils.jsonnet';
local config = import 'nodeinfo/config.jsonnet';

local data = {
  'config.json': std.toString(config),
};

{
  apiVersion: 'v1',
  data: data,
  kind: 'ConfigMap',
  metadata: cmutil.metadata('nodeinfo-config', data),
}
