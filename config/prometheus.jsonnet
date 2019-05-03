{
  kind: 'ConfigMap',
  apiVersion: 'v1',
  metadata: {
    name: 'prometheus-config',
  },
  data: {
    'rules.yml': importstr 'prometheus/rules.yml',
    'prometheus.yml': importstr 'prometheus/prometheus.yml',
  },
}
