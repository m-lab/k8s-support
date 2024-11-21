{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: 'multi-networkpolicy',
    namespace: 'kube-system',
    labels: {
      tier: 'node',
      name: 'multi-networkpolicy',
    },
  },
  spec: {
    selector: {
      matchLabels: {
        workload: 'multi-networkpolicy',
      },
    },
    updateStrategy: {
      type: 'RollingUpdate',
    },
    template: {
      metadata: {
        labels: {
          tier: 'node',
          workload: 'multi-networkpolicy'
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
            image: 'measurementlab/multi-networkpolicy-iptables:v1.0.0',
            imagePullPolicy: 'Always',
            command: [
              '/usr/bin/multi-networkpolicy-iptables',
            ],
            args: [
              '--accept-icmp',
              '--accept-icmpv6',
              '--container-runtime-endpoint=/run/containerd/containerd.sock',
              '--host-prefix=/host',
              '--network-plugins=netctl,ipvlan',
              '--pod-iptables=/var/lib/multi-networkpolicy/iptables',
              // If any custom iptables rules are needed that cannot be
              // provisioned by MultiNetworkPolicy definitions, then you can
              // add them to the file configs/multi-networkpolicy.jsonnet in
              // this repo, and uncomment the following flags as necessary:
              // '--custom-v4-ingress-rule-file=/etc/multi-networkpolicy/rules/custom-v4-ingress-rules.txt',
              // '--custom-v6-ingress-rule-file=/etc/multi-networkpolicy/rules/custom-v6-ingress-rules.txt',
              // '--custom-v4-egress-rule-file=/etc/multi-networkpolicy/rules/custom-v4-egress-rules.txt',
              // '--custom-v6-egress-rule-file=/etc/multi-networkpolicy/rules/custom-v6-egress-rules.txt',
            ],
            resources: {
              requests: {
                cpu: '100m',
                memory: '150Mi',
              },
              limits: {
                cpu: '100m',
                memory: '500Mi',
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

