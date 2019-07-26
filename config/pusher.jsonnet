local cmutil = import 'cloudmap-utils.jsonnet';

local data = {
  bucket: 'pusher-' + std.extVar('PROJECT_ID'),
};

{
  kind: 'ConfigMap',
  apiVersion: 'v1',
  metadata: cmutil.metadata('pusher-dropbox', data),
  data: data,
}
