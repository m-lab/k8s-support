[
  {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: 'heartbeat-experiment',
    },
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: {
      name: 'heartbeat-experiment',
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'heartbeat-experiment',
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: 'heartbeat-experiment',
        namespace: 'default',
      },
    ],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: {
      name: 'heartbeat-experiment',
    },
    rules: [
      {
        apiGroups: [
          'authentication.k8s.io',
        ],
        resources: [
          'tokenreviews',
        ],
        verbs: [
          'create',
        ],
      },
      {
        apiGroups: [
          'authorization.k8s.io',
        ],
        resources: [
          'subjectaccessreviews',
        ],
        verbs: [
          'create',
        ],
      },
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
