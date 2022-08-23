[
  {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: 'platform-experiment',
    },
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: {
      name: 'platform-experiment',
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'status-reader',
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: 'platform-experiment',
        namespace: 'default',
      },
    ],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: {
      name: 'status-reader',
    },
    rules: [
      {
        apiGroups: [
          '',
        ],
        resources: [
          'pods',
          'nodes',
        ],
        verbs: [
          'get',
        ],
      },
    ],
  },
]
