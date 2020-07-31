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
        annotations: {
          'prometheus.io/scrape': 'true',
          'prometheus.io/scheme': 'http'
        },
        labels: {
          name: 'kured',
        },
      },
      spec: {
        containers: [
          {
            args: [
              '--reboot-sentinel=/var/run/mlab-reboot',
              '--period=1h',
              '--annotation-ttl=4h',
              // We may or may not want to enable something like the following
              // schedule for reboots. For now it is commented out until we can
              // gather more experience with Kured.
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
            ports: [
              {
                containerPort: 8080,
              },
            ],
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
