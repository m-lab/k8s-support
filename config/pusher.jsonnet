{
  kind: 'ConfigMap',
  apiVersion: 'v1',
  metadata: {
    name: 'pusher-dropbox',
  },
  data: {
    bucket: 'pusher-' + std.extVar('PROJECT_ID'),
  },
}
