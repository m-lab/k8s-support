local CluoAnnotation(annotation) = {
  name: 'add-cluo-annotation',
  image: 'alpine:latest',
  command: ['/bin/sh', '-c'],
  args: [
    |||
      KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) \
      apk update && apk add curl && \
      curl -k \
      -H "Accept: application/json" \
      -H "Authorization: Bearer $KUBE_TOKEN" \
      -H "Content-Type: application/merge-patch+json" \
      -X PATCH \
      -d '{"metadata":{"annotations":{"%(annotation)s":"true"}}}' \
      https://kubernetes.default.svc.cluster.local:443/api/v1/nodes/$NODE
    ||| % annotation,
  ],
  env: [
    {
      name: 'NODE',
      valueFrom: {
        fieldRef: {
          fieldPath: 'spec.nodeName',
        },
      },
    },
  ],
};

local uuid = {
  initContainer: {
    // Write out the UUID prefix to a well-known location.
    // more on this, see DESIGN.md
    // https://github.com/m-lab/uuid/
    name: 'set-up-uuid-prefix-file',
    image: 'measurementlab/uuid:v0.1',
    args: [
      '-filename=' + uuid.prefixfile,
    ],
    volumeMounts: [
      uuid.volumemount {
        readOnly: false,
      },
    ],
  },
  prefixfile: '/var/local/uuid/prefix',
  volumemount: {
    mountPath: '/var/local/uuid',
    name: 'uuid-prefix',
    readOnly: true,
  },
  volume: {
    emptyDir: {},
    name: 'uuid-prefix',
  },
};

local volume(name) = {
  hostPath: {
    path: '/cache/data/' + name,
    type: 'DirectoryOrCreate',
  },
  name: name + '-data',
};

local VolumeMount(name) = {
  mountPath: '/var/spool/' + name,
  name: name + '-data',
};

local RBACProxy(name, port) = {
  name: 'kube-rbac-proxy-' + name,
  image: 'quay.io/coreos/kube-rbac-proxy:v0.4.1',
  args: [
    '--logtostderr',
    '--secure-listen-address=$(IP):' + port,
    '--upstream=http://127.0.0.1:' + port + '/',
  ],
  env: [
    {
      name: 'IP',
      valueFrom: {
        fieldRef: {
          fieldPath: 'status.podIP',
        },
      },
    },
  ],
  ports: [
    {
      containerPort: port,
    },
  ],
};

local ExperimentNoIndex(name, datatypes, hostNetworking) = {
  apiVersion: 'extensions/v1beta1',
  kind: 'DaemonSet',
  metadata: {
    name: name,
    namespace: 'default',
  },
  spec: {
    selector: {
      matchLabels: {
        workload: name,
      },
    },
    template: {
      metadata: {
        annotations: {
          'prometheus.io/scrape': 'true',
          'prometheus.io/scheme': if hostNetworking then 'https' else 'http',
        },
        labels: {
          workload: name,
        },
      },
      spec: {
        containers: [
          {
            name: 'tcpinfo',
            image: 'measurementlab/tcp-info:v0.0.9',
            args: [
              if hostNetworking then
                '-prometheusx.listen-address=127.0.0.1:9991'
              else
                '-prometheusx.listen-address=$(PRIVATE_IP):9991'
              ,
              '-output=' + VolumeMount(name).mountPath + '/tcpinfo',
              '-uuid-prefix-file=' + uuid.prefixfile,
            ],
            env: if hostNetworking then [] else [
              {
                name: 'PRIVATE_IP',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'status.podIP',
                  },
                },
              },
            ],
            ports: if hostNetworking then [] else [
              {
                containerPort: 9991,
              },
            ],
            volumeMounts: [
              VolumeMount(name),
              uuid.volumemount,
            ],
          },
          {
            name: 'traceroute',
            image: 'measurementlab/traceroute-caller:v0.0.6',
            args: [
              if hostNetworking then
                '-prometheusx.listen-address=127.0.0.1:9992'
              else
                '-prometheusx.listen-address=$(PRIVATE_IP):9992',
              '-outputPath=' + VolumeMount(name).mountPath + '/traceroute',
              '-uuid-prefix-file=' + uuid.prefixfile,
            ],
            env: if hostNetworking then [] else [
              {
                name: 'PRIVATE_IP',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'status.podIP',
                  },
                },
              },
            ],
            ports: if hostNetworking then [] else [
              {
                containerPort: 9992,
              },
            ],
            volumeMounts: [
              VolumeMount(name),
              uuid.volumemount,
            ],
          },
          {
            name: 'pusher',
            image: 'measurementlab/pusher:v1.9',
            args: [
              if hostNetworking then
                '-prometheusx.listen-address=127.0.0.1:9993'
              else
                '-prometheusx.listen-address=$(PRIVATE_IP):9993',
              '-experiment=' + name,
              '-archive_size_threshold=50MB',
              '-directory=/var/spool/' + name,
              '-datatype=tcpinfo',
              '-datatype=traceroute',
            ] + ['-datatype=' + d for d in datatypes],
            env: [
              {
                name: 'GOOGLE_APPLICATION_CREDENTIALS',
                value: '/etc/credentials/pusher.json',
              },
              {
                name: 'BUCKET',
                valueFrom: {
                  configMapKeyRef: {
                    key: 'bucket',
                    name: 'pusher-dropbox',
                  },
                },
              },
              {
                name: 'MLAB_NODE_NAME',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'spec.nodeName',
                  },
                },
              },
            ] + if hostNetworking then [] else [
              {
                name: 'PRIVATE_IP',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'status.podIP',
                  },
                },
              },
            ],
            ports: if hostNetworking then [] else [
              {
                containerPort: 9993,
              },
            ],
            volumeMounts: [
              VolumeMount(name),
              {
                mountPath: '/etc/credentials',
                name: 'pusher-credentials',
                readOnly: true,
              },
            ],
          },
        ] + if hostNetworking then [
          RBACProxy('tcpinfo', 9991),
          RBACProxy('traceroute', 9992),
          RBACProxy('pusher', 9993),
        ] else [],
        [if hostNetworking then 'serviceAccountName']: 'kube-rbac-proxy',
        initContainers: [
          uuid.initContainer,
        ],
        nodeSelector: {
          'mlab/type': 'platform',
        },
        volumes: [
          {
            name: 'pusher-credentials',
            secret: {
              secretName: 'pusher-credentials',
            },
          },
          uuid.volume,
          volume(name),
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
};

local Experiment(name, index, datatypes=[]) = ExperimentNoIndex(name, datatypes, false) + {
  spec+: {
    template+: {
      metadata+: {
        annotations+: {
          'k8s.v1.cni.cncf.io/networks': '[{ "name": "index2ip-index-' + index + '-conf" }]',
          'v1.multus-cni.io/default-network': 'flannel-experiment-conf',
        },
      },
      spec+: {
        initContainers+: [
          // TODO: this is a hack. Remove the hack by fixing
          // contents of resolv.
          {
            name: 'fix-resolv-conf',
            image: 'busybox',
            command: [
              'sh',
              '-c',
              'echo "nameserver 8.8.8.8" > /etc/resolv.conf',
            ],
          },
        ],
      },
    },
  },
};

{
  // Returns a minimal experiment, suitable for adding a unique network config
  // before deployment. It is expected that most users of this library will use
  // Experiment().
  ExperimentNoIndex(name, datatypes, hostNetworking):: ExperimentNoIndex(name, datatypes, hostNetworking),

  // RBACProxy creates a https proxy for an http port. This allows us to serve
  // metrics securely over https, andto https-authenticate to only serve them to
  // ourselves.
  RBACProxy(name, port):: RBACProxy(name, port),

  // Returns all the trappings for a new experiment. New experiments should
  // need to add one new container.
  Experiment(name, index, datatypes):: Experiment(name, index, datatypes),

  // Returns a volumemount for a given datatype. All produced volume mounts
  // in /var/spool/name/
  VolumeMount(name):: VolumeMount(name),

  // Helper object containing uuid-related filenames, volumes, and volumemounts.
  uuid: uuid,

  // Returns an initContainer element allowing the CLUO DaemonSets to set a
  // particular annotation on the node on which each pod gets scheduled.
  CluoAnnotation: CluoAnnotation,
}
