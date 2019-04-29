[
  // TODO: Remove the - networks and - kubernetes.com lines
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: {
      labels: {
        'rbac.authorization.k8s.io/aggregate-to-view': 'true',
      },
      name: 'network-reader',
    },
    rules: [
      {
        apiGroups: [
          'kubernetes.com',
          'k8s.cni.cncf.io',
        ],
        resources: [
          'networks',
          'network-attachment-definitions',
        ],
        verbs: [
          'get',
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
      name: 'allow-nodes-to-read-networks',
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'network-reader',
    },
    subjects: [
      {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Group',
        name: 'system:nodes',
      },
    ],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1beta1',
    kind: 'ClusterRole',
    metadata: {
      name: 'flannel',
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
          '',
        ],
        resources: [
          'nodes',
        ],
        verbs: [
          'list',
          'watch',
        ],
      },
      {
        apiGroups: [
          '',
        ],
        resources: [
          'nodes/status',
        ],
        verbs: [
          'patch',
        ],
      },
    ],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1beta1',
    kind: 'ClusterRoleBinding',
    metadata: {
      name: 'flannel',
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'flannel',
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: 'flannel',
        namespace: 'kube-system',
      },
    ],
  },
  {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: 'flannel',
      namespace: 'kube-system',
    },
  },
]
