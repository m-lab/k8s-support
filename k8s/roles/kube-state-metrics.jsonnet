[
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'Role',
    metadata: {
      name: 'kube-state-metrics-resizer',
      namespace: 'kube-system',
    },
    rules: [
      {
        apiGroups: [
          '',
        ],
        resources: [
          'pods',
        ],
        verbs: [
          'get',
        ],
      },
      {
        apiGroups: [
          'apps',
        ],
        resourceNames: [
          'kube-state-metrics',
        ],
        resources: [
          'deployments',
        ],
        verbs: [
          'get',
          'update',
        ],
      },
      {
        apiGroups: [
          'extensions',
        ],
        resourceNames: [
          'kube-state-metrics',
        ],
        resources: [
          'deployments',
        ],
        verbs: [
          'get',
          'update',
        ],
      },
    ],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'RoleBinding',
    metadata: {
      name: 'kube-state-metrics',
      namespace: 'kube-system',
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'Role',
      name: 'kube-state-metrics-resizer',
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: 'kube-state-metrics',
        namespace: 'kube-system',
      },
    ],
  },
  {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: 'kube-state-metrics',
      namespace: 'kube-system',
    },
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: {
      name: 'kube-state-metrics',
    },
    rules: [
      {
        apiGroups: [
          '',
        ],
        resources: [
          'configmaps',
          'secrets',
          'nodes',
          'pods',
          'services',
          'resourcequotas',
          'replicationcontrollers',
          'limitranges',
          'persistentvolumeclaims',
          'persistentvolumes',
          'namespaces',
          'endpoints',
        ],
        verbs: [
          'list',
          'watch',
        ],
      },
      {
        apiGroups: [
          'extensions',
        ],
        resources: [
          'daemonsets',
          'deployments',
          'replicasets',
          'ingresses',
        ],
        verbs: [
          'list',
          'watch',
        ],
      },
      {
        apiGroups: [
          'apps',
        ],
        resources: [
          'daemonsets',
          'deployments',
          'replicasets',
          'statefulsets',
        ],
        verbs: [
          'list',
          'watch',
        ],
      },
      {
        apiGroups: [
          'batch',
        ],
        resources: [
          'cronjobs',
          'jobs',
        ],
        verbs: [
          'list',
          'watch',
        ],
      },
      {
        apiGroups: [
          'autoscaling',
        ],
        resources: [
          'horizontalpodautoscalers',
        ],
        verbs: [
          'list',
          'watch',
        ],
      },
      {
        apiGroups: [
          'policy',
        ],
        resources: [
          'poddisruptionbudgets',
        ],
        verbs: [
          'list',
          'watch',
        ],
      },
    ],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: {
      name: 'kube-state-metrics',
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'kube-state-metrics',
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: 'kube-state-metrics',
        namespace: 'kube-system',
      },
    ],
  },
]
