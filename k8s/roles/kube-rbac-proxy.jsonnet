[
  {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: 'kube-rbac-proxy',
    },
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: {
      name: 'kube-rbac-proxy',
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'kube-rbac-proxy',
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: 'kube-rbac-proxy',
        namespace: 'default',
      },
    ],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: {
      name: 'kube-rbac-proxy',
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
          'pods'
        ],
        verbs: [
          'get',
          'watch',
          'list',
        ],
      },
      {
        apiGroups: [
          '',
        ],
        resources: [
          'nodes'
        ],
        verbs: [
          'get',
          'watch',
          'list',
        ],
      },
    ],
  },
]
