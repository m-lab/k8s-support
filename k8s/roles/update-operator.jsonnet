// From: https://github.com/coreos/container-linux-update-operator/tree/master/examples/deploy
[
  {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: 'reboot-coordinator',
      namespace: 'reboot-coordinator',
    },
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1beta1',
    kind: 'ClusterRole',
    metadata: {
      name: 'reboot-coordinator',
    },
    rules: [
      {
        apiGroups: [
          '',
        ],
        resources: [
          'nodes',
        ],
        verbs: [
          'get',
          'list',
          'patch',
          'watch',
          'update',
        ],
      },
      {
        apiGroups: [
          '',
        ],
        resources: [
          'configmaps',
        ],
        verbs: [
          'create',
          'get',
          'update',
          'list',
          'watch',
        ],
      },
      {
        apiGroups: [
          '',
        ],
        resources: [
          'events',
        ],
        verbs: [
          'create',
          'watch',
        ],
      },
      {
        apiGroups: [
          '',
        ],
        resources: [
          'pods',
        ],
        verbs: [
          'get',
          'list',
          'delete',
        ],
      },
      {
        apiGroups: [
          'extensions',
        ],
        resources: [
          'daemonsets',
        ],
        verbs: [
          'get',
        ],
      },
    ],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1beta1',
    kind: 'ClusterRoleBinding',
    metadata: {
      name: 'reboot-coordinator',
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'reboot-coordinator',
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: 'default',
        namespace: 'reboot-coordinator',
      },
    ],
  },
]
