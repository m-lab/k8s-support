// Service Account for experiments that use the Heartbeat Service.
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
      // The following rules are needed for experiments to run the kube-rbac-proxy
      // sidecar container.
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
      // The following rule is needed for the Heartbeat Service to send pod/node GET
      // requests to the Kubernetes API server.
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
