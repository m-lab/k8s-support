[
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: {
      name: 'reloader',
      namespace: 'default',
    },
    rules: [
      {
        apiGroups: [
          '',
        ],
        resources: [
          'configmaps',
          'secrets',
        ],
        verbs: [
          'get',
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
          'statefulsets',
        ],
        verbs: [
          'get',
          'list',
          'patch',
          'update',
        ],
      },
      {
        apiGroups: [
          'extensions',
        ],
        resources: [
          'deployments',
          'daemonsets',
        ],
        verbs: [
          'get',
          'list',
          'patch',
          'update',
        ],
      },
    ],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: {
      name: 'reloader',
      namespace: 'default',
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'reloader',
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: 'reloader',
        namespace: 'default',
      },
    ],
  },
  {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: 'reloader',
    },
  },
]
