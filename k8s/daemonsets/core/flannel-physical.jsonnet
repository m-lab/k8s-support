// The daemonset for networking on physical platform nodes.
//
// As can be seen in the nodeSelector, a physical platform node is any node
// with the label mlab/type=physical. If a node tries to join without an
// mlab/type, its network will likely not work.
//
// Physical platform nodes have their cluster-internal networking done by
// Flannel and their external networking run done by ipvlan with a custom IPAM
// plugin. The ability to have multus network interfaces in a pod is provided
// by multus.
{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: 'kube-flannel-ds-physical',
    namespace: 'kube-system',
  },
  spec: {
    selector: {
      matchLabels: {
        app: 'flannel',
        tier: 'node',
        workload: 'flannel-physical',
      },
    },
    template: {
      metadata: {
        labels: {
          app: 'flannel',
          tier: 'node',
          workload: 'flannel-physical',
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
            name: 'kube-flannel',
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
              '/etc/kube-flannel/physical-cni-conf.json',
              '/etc/cni/net.d/multus-cni.conf',
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
          'mlab/type': 'physical',
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
