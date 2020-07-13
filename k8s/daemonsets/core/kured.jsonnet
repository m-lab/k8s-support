{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: 'kured',
    namespace: 'kube-system',
  },
  spec: {
    selector: {
      matchLabels: {
        name: 'kured',
      },
    },
    template: {
      metadata: {
        labels: {
          name: 'kured',
        },
      },
      spec: {
        containers: [
          {
            args: [
              '--reboot-sentinel=/var/run/mlab-reboot',
              '--period=10m',
              //'--reboot-days=mon,tue,wed,thu,fri',
              //'--time-zone=America/New_York',
              //'--start-time=09:00',
              //'--end-time=16:00',
            ],
            command: [
              '/usr/bin/kured',
            ],
            env: [
              {
                // Pass in the name of the node on which this pod is scheduled
                // for use with drain/uncordon operations and lock acquisition
                name: 'KURED_NODE_ID',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'spec.nodeName',
                  },
                },
              },
            ],
            image: 'weaveworks/kured:1.4.4',
            imagePullPolicy: 'IfNotPresent',
            name: 'kured',
            securityContext: {
              // Give permission to nsenter /proc/1/ns/mnt
              privileged: true
            },
          },
        ],
        hostPID: true,
        restartPolicy: 'Always',
        serviceAccountName: 'kured',
      },
    },
    updateStrategy: {
      type: 'RollingUpdate',
    },
  },
}
