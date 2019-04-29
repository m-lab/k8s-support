std.flattenArrays([
	import 'roles/container-linux-update-coordinator.jsonnet',
	import 'roles/flannel.jsonnet',
	import 'roles/kube-rbac-proxy.jsonnet',
	import 'roles/kube-state-metrics.jsonnet',
	import 'roles/rbac-prometheus.jsonnet',
])
