// The daemonset for networking on virtual nodes.
//
// As can be seen in the nodeSelector, a virtual node is any node with the
// label mlab/type=virtual. If a node tries to join without an mlab/type, its
// network will likely not work. Pods running on virtual nodes only get an
// internal IP address.
//
// The toleration "key: node-role.kubernetes.io/master" was removed because of
// this issue: https://github.com/coreos/flannel/issues/1044. This was needed
// because flannel pods were not getting scheduled on the master nodes due to a
// new taint being added to the master because of this issue:
// https://github.com/kubernetes/kubernetes/issues/44254

{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: 'flannel-virtual',
    namespace: 'kube-system',
  },
  spec: {
    selector: {
      matchLabels: {
        app: 'flannel',
        tier: 'node',
        workload: 'flannel-virtual',
      },
    },
    template: {
      metadata: {
        labels: {
          app: 'flannel',
          tier: 'node',
          workload: 'flannel-virtual',
        },
      },
      spec: {
        containers: [
          {
            args: [
              '--ip-masq',
              '--kube-subnet-mgr',
            ],
            command: [
              '/opt/bin/flanneld',
            ],
            env: [
              {
                name: 'POD_NAME',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'metadata.name',
                  },
                },
              },
              {
                name: 'POD_NAMESPACE',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'metadata.namespace',
                  },
                },
              },
            ],
            image: 'quay.io/coreos/flannel:' + std.extVar('K8S_FLANNEL_VERSION') + '-amd64',
            name: 'flannel',
            resources: {
              limits: {
                cpu: '100m',
                memory: '128Mi',
              },
              requests: {
                cpu: '100m',
                memory: '128Mi',
              },
            },
            securityContext: {
              privileged: true,
            },
            volumeMounts: [
              {
                mountPath: '/run',
                name: 'run',
              },
              {
                mountPath: '/etc/kube-flannel/',
                name: 'flannel-cfg',
              },
            ],
          },
        ],
        hostNetwork: true,
        initContainers: [
          {
            args: [
              '-f',
              '/etc/kube-flannel/virtual-cni-conf.json',
              '/etc/cni/net.d/10-flannel.conflist',
            ],
            command: [
              'cp',
            ],
            image: 'quay.io/coreos/flannel:' + std.extVar('K8S_FLANNEL_VERSION') + '-amd64',
            name: 'install-cni',
            volumeMounts: [
              {
                mountPath: '/etc/cni/net.d',
                name: 'cni',
              },
              {
                mountPath: '/etc/kube-flannel/',
                name: 'flannel-cfg',
              },
            ],
          },
        ],
        nodeSelector: {
          'beta.kubernetes.io/arch': 'amd64',
          'mlab/type': 'virtual',
        },
        serviceAccountName: 'flannel',
        tolerations: [
          {
            effect: 'NoSchedule',
            operator: 'Exists',
          },
        ],
        volumes: [
          {
            hostPath: {
              path: '/run',
            },
            name: 'run',
          },
          {
            hostPath: {
              path: '/etc/cni/net.d',
            },
            name: 'cni',
          },
          {
            configMap: {
              name: 'kube-flannel-cfg',
            },
            name: 'flannel-cfg',
          },
        ],
      },
    },
    updateStrategy: {
      type: 'RollingUpdate',
    },
  },
}
