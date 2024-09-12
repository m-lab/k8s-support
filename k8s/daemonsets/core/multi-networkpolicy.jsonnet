{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: 'multi-networkpolicy',
    namespace: 'kube-system',
    labels: {
      tier: 'node',
      app: 'multi-networkpolicy',
      name: 'multi-networkpolicy',
    },
  },
  spec: {
    selector: {
      matchLabels: {
        name: 'multi-networkpolicy',
      },
    },
    updateStrategy: {
      type: 'RollingUpdate',
    },
    template: {
      metadata: {
        labels: {
          tier: 'node',
          app: 'multi-networkpolicy',
          name: 'multi-networkpolicy',
        },
      },
      spec: {
        hostNetwork: true,
        nodeSelector: {
          'kubernetes.io/arch': 'amd64',
        },
        tolerations: [
          {
            operator: 'Exists',
            effect: 'NoSchedule',
          },
        ],
        serviceAccountName: 'multi-networkpolicy',
        containers: [
          {
            name: 'multi-networkpolicy',
            image: 'ghcr.io/k8snetworkplumbingwg/multi-networkpolicy-iptables:snapshot',
            imagePullPolicy: 'Always',
            command: [
              '/usr/bin/multi-networkpolicy-iptables',
            ],
            args: [
              '--host-prefix=/host',
              '--container-runtime-endpoint=/run/containerd/containerd.sock',
              '--network-plugins=ipvlan',
              '--pod-iptables=/var/lib/multi-networkpolicy/iptables',
            ],
            resources: {
              requests: {
                cpu: '100m',
                memory: '80Mi',
              },
              limits: {
                cpu: '100m',
                memory: '150Mi',
              },
            },
            securityContext: {
              privileged: true,
              capabilities: {
                add: [
                  'SYS_ADMIN',
                  'NET_ADMIN',
                ],
              },
            },
            volumeMounts: [
              {
                name: 'host',
                mountPath: '/host',
              },
              {
                name: 'var-lib-multinetworkpolicy',
                mountPath: '/var/lib/multi-networkpolicy',
              },
              {
                name: 'multi-networkpolicy-custom-rules',
                mountPath: '/etc/multi-networkpolicy/rules',
                readOnly: true,
              },
            ],
          },
        ],
        volumes: [
          {
            name: 'host',
            hostPath: {
              path: '/',
            },
          },
          {
            name: 'var-lib-multinetworkpolicy',
            hostPath: {
              path: '/var/lib/multi-networkpolicy',
            },
          },
          {
            name: 'multi-networkpolicy-custom-rules',
            configMap: {
              name: 'multi-networkpolicy-custom-rules',
            },
          },
        ],
      },
    },
  },
}

