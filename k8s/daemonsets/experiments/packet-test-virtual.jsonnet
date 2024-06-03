local datatypes = ['pair1','train1','ndt7'];
local exp = import '../templates.jsonnet';
local expName = 'pt';
local services = [];

{
  apiVersion: 'apps/v1',
  kind: 'DaemonSet',
  metadata: {
    name: expName + '-virtual',
  },
  spec: {
    selector: {
      matchLabels: {
        workload: expName + '-virtual',
      },
    },
    template: {
      metadata: {
        annotations: {
          'secret.reloader.stakater.com/reload': 'measurement-lab-org-tls',
        },
        labels: {
          workload: expName + '-virtual',
          'site-type': 'virtual',
        },
      },
      spec: {
        hostNetwork: true,
        nodeSelector: {
          'mlab/type': 'virtual',
          // This is added so k8s doesn't try to schedule the pods to prometheus or
          // API nodes.
          'mlab/run': 'ndt',
        },
        serviceAccountName: 'heartbeat-experiment',
        initContainers: [
          {
            // Copy the JSON schema where jostler expects it to be.
            name: 'copy-schema',
            image: 'measurementlab/packet-test:latest',
            command: [
              '/bin/sh',
              '-c',
              'cp /packet-test/pair1.json /var/spool/datatypes/pair1.json && ' +
              'cp /packet-test/train1.json /var/spool/datatypes/train1.json && ' +
              'cp /packet-test/ndt7.json /var/spool/datatypes/ndt7.json',
            ],
            volumeMounts: [
              exp.VolumeMountDatatypes(expName),
            ],
          },
        ],
        containers: [
          {
            args: [
              '-datadir=/var/spool/' + expName,
              '-hostname=$(NODE_NAME)',
            ],
            env: [
              {
                name: 'NODE_NAME',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'spec.nodeName',
                  },
                },
              },
              {
                name: 'PRIVATE_IP',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'status.podIP',
                  },
                },
              },
            ],
            image: 'measurementlab/packet-test:latest',
            name: 'packet-test',
            command: [
              '/packet-test/server',
            ],
            securityContext: {
              capabilities: {
                add: [
                  'NET_BIND_SERVICE',
                ],
                drop: [
                  'all',
                ],
              },
              runAsUser: 0,
            },
            volumeMounts: [
              {
                mountPath: '/certs',
                name: 'measurement-lab-org-tls',
                readOnly: true,
              },
              {
                mountPath: '/verify',
                name: 'locate-verify-keys',
                readOnly: true,
              },
              exp.Metadata.volumemount,
            ] + [
              exp.VolumeMount(expName + '/' + d)
              for d in datatypes
            ],
            ports: [],
          },
        ],
        volumes: [
          {
            name: 'measurement-lab-org-tls',
            secret: {
              secretName: 'measurement-lab-org-tls',
            },
          },
          {
            name: 'locate-verify-keys',
            secret: {
              secretName: 'locate-verify-keys',
            },
          },
          {
            name: expName + '-datatypes',
            hostPath: {
              path: '/cache/datatypes/' + expName,
              type: 'DirectoryOrCreate',
            },
          },
          {
            name: expName + '-pair1-data',
            hostPath: {
              path: '/cache/data/' + expName + '/pair1',
              type: 'DirectoryOrCreate',
            },
          },
          {
            name: expName + '-train1-data',
            hostPath: {
              path: '/cache/data/' + expName + '/train1',
              type: 'DirectoryOrCreate',
            },
          },
          {
            name: expName + '-ndt7-data',
            hostPath: {
              path: '/cache/data/' + expName + '/ndt7',
              type: 'DirectoryOrCreate',
            },
          },
          exp.Metadata.volume,
        ],
      },
    },
    updateStrategy: {
      rollingUpdate: {
        maxUnavailable: 2,
      },
      type: 'RollingUpdate',
    },
  },
}
