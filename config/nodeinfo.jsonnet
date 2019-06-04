local config = import 'nodeinfo/config.jsonnet';

{
  apiVersion: 'v1',
  data: {
    'config.json': std.toString(config),
  },
  kind: 'ConfigMap',
  metadata: {
    name: 'nodeinfo-config',
  },
}
