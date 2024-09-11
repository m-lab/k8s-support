[
  {
    kind: 'ClusterRole',
    apiVersion: 'rbac.authorization.k8s.io/v1',
    metadata: {
      name: 'multi-networkpolicy',
    },
    rules: [
      {
        apiGroups: [
          'k8s.cni.cncf.io',
        ],
        resources: [
          '*',
        ],
        verbs: [
          '*',
        ],
      },
      {
        apiGroups: [
          '',
        ],
        resources: [
          'pods',
          'namespaces',
        ],
        verbs: [
          'list',
          'watch',
          'get',
        ],
      },
      {
        apiGroups: [
          'networking.k8s.io',
        ],
        resources: [
          'networkpolicies',
        ],
        verbs: [
          'watch',
          'list',
        ],
      },
      {
        apiGroups: [
          '',
          'events.k8s.io',
        ],
        resources: [
          'events',
        ],
        verbs: [
          'create',
          'patch',
          'update',
        ],
      },
    ],
  },
  {
    kind: 'ClusterRoleBinding',
    apiVersion: 'rbac.authorization.k8s.io/v1',
    metadata: {
      name: 'multi-networkpolicy',
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'multi-networkpolicy',
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: 'multi-networkpolicy',
        namespace: 'kube-system',
      },
    ],
  },
  {
    kind: 'ServiceAccount',
    apiVersion: 'v1',
    metadata: {
      name: 'multi-networkpolicy',
      namespace: 'kube-system',
    },
  },
]

