local ndtVersion = 'v0.13.2';

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

local tcpinfoServiceVolume = {
  volumemount: {
    mountPath: '/var/local/tcpinfoeventsocket',
    name: 'tcpinfo-eventsocket',
    readOnly: false,
  },
  volume: {
    emptyDir: {},
    name: 'tcpinfo-eventsocket',
  },
  eventsocketFilename: '/var/local/tcpinfoeventsocket/tcpevents.sock',
};

local Tcpinfo(expName, tcpPort, hostNetwork) = [
  {
    name: 'tcpinfo',
    image: 'measurementlab/tcp-info:v1.2.0',
    args: [
      if hostNetwork then
        '-prometheusx.listen-address=127.0.0.1:' + tcpPort
      else
        '-prometheusx.listen-address=$(PRIVATE_IP):' + tcpPort
      ,
      '-output=' + VolumeMount(expName).mountPath + '/tcpinfo',
      '-uuid-prefix-file=' + uuid.prefixfile,
      '-eventsocket=' + tcpinfoServiceVolume.eventsocketFilename,
    ],
    env: if hostNetwork then [] else [
      {
        name: 'PRIVATE_IP',
        valueFrom: {
          fieldRef: {
            fieldPath: 'status.podIP',
          },
        },
      },
    ],
    ports: if hostNetwork then [] else [
      {
        containerPort: tcpPort,
      },
    ],
    volumeMounts: [
      VolumeMount(expName),
      tcpinfoServiceVolume.volumemount,
      uuid.volumemount,
    ],
  }] +
  if hostNetwork then
    [RBACProxy('tcpinfo', tcpPort)]
  else
    []
;

local Traceroute(expName, tcpPort, hostNetwork) = [
  {
    name: 'traceroute',
    image: 'measurementlab/traceroute-caller:v0.2.2',
    args: [
      if hostNetwork then
        '-prometheusx.listen-address=127.0.0.1:' + tcpPort
      else
        '-prometheusx.listen-address=$(PRIVATE_IP):' + tcpPort,
      '-outputPath=' + VolumeMount(expName).mountPath + '/traceroute',
      '-uuid-prefix-file=' + uuid.prefixfile,
      '-tcpinfo.socket=' + tcpinfoServiceVolume.eventsocketFilename,
    ],
    env: if hostNetwork then [] else [
      {
        name: 'PRIVATE_IP',
        valueFrom: {
          fieldRef: {
            fieldPath: 'status.podIP',
          },
        },
      },
    ],
    ports: if hostNetwork then [] else [
      {
        containerPort: tcpPort,
      },
    ],
    volumeMounts: [
      VolumeMount(expName),
      tcpinfoServiceVolume.volumemount,
      uuid.volumemount,
    ],
  }] +
  if hostNetwork then
    [RBACProxy('traceroute', tcpPort)]
  else
    []
;

local Pcap(expName, tcpPort, hostNetwork) = [
  {
    name: 'pcap',
    image: 'measurementlab/packet-headers:v0.2',
    args: [
      if hostNetwork then
        '-prometheusx.listen-address=127.0.0.1:' + tcpPort
      else
        '-prometheusx.listen-address=$(PRIVATE_IP):' + tcpPort,
      '-datadir=' + VolumeMount(expName).mountPath + '/pcap',
      '-eventsocket=' + tcpinfoServiceVolume.eventsocketFilename,
    ],
    env: if hostNetwork then [] else [
      {
        name: 'PRIVATE_IP',
        valueFrom: {
          fieldRef: {
            fieldPath: 'status.podIP',
          },
        },
      },
    ],
    ports: if hostNetwork then [] else [
      {
        containerPort: tcpPort,
      },
    ],
    volumeMounts: [
      VolumeMount(expName),
      tcpinfoServiceVolume.volumemount,
      uuid.volumemount,
    ],
  }] +
  if hostNetwork then
    [RBACProxy('traceroute', tcpPort)]
  else
    []
;


local Pusher(expName, tcpPort, datatypes, hostNetwork, bucket) = [
  {
    name: 'pusher',
    image: 'measurementlab/pusher:v1.9',
    args: [
      if hostNetwork then
        '-prometheusx.listen-address=127.0.0.1:' + tcpPort
      else
        '-prometheusx.listen-address=$(PRIVATE_IP):' + tcpPort,
      '-bucket=' + bucket,
      '-experiment=' + expName,
      '-archive_size_threshold=50MB',
      '-directory=/var/spool/' + expName,
    ] + ['-datatype=' + d for d in datatypes],
    env: [
      {
        name: 'GOOGLE_APPLICATION_CREDENTIALS',
        value: '/etc/credentials/pusher.json',
      },
      {
        name: 'MLAB_NODE_NAME',
        valueFrom: {
          fieldRef: {
            fieldPath: 'spec.nodeName',
          },
        },
      },
    ] + if hostNetwork then [] else [
      {
        name: 'PRIVATE_IP',
        valueFrom: {
          fieldRef: {
            fieldPath: 'status.podIP',
          },
        },
      },
    ],
    ports: if hostNetwork then [] else [
      {
        containerPort: tcpPort,
      },
    ],
    volumeMounts: [
      VolumeMount(expName),
      {
        mountPath: '/etc/credentials',
        name: 'pusher-credentials',
        readOnly: true,
      },
    ],
  }] +
  if hostNetwork then
    [RBACProxy('pusher', tcpPort)]
  else
    []
;

local ExperimentNoIndex(name, datatypes, hostNetwork, bucket) = {
  apiVersion: 'apps/v1',
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
          'prometheus.io/scheme': if hostNetwork then 'https' else 'http',
        },
        labels: {
          workload: name,
        },
      },
      spec: {
        containers:
          std.flattenArrays([
            Tcpinfo(name, 9991, hostNetwork),
            Traceroute(name, 9992, hostNetwork),
            Pcap(name, 9993, hostNetwork),
            Pusher(name, 9994, ['tcpinfo', 'traceroute', 'pcap'] + datatypes, hostNetwork, bucket),
          ]),
        [if hostNetwork then 'serviceAccountName']: 'kube-rbac-proxy',
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
          tcpinfoServiceVolume.volume,
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

local Experiment(name, index, bucket, datatypes=[]) = ExperimentNoIndex(name, datatypes, false, bucket) + {
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
  ExperimentNoIndex(name, datatypes, hostNetwork, bucket):: ExperimentNoIndex(name, datatypes, hostNetwork, bucket),

  // RBACProxy creates a https proxy for an http port. This allows us to serve
  // metrics securely over https, andto https-authenticate to only serve them to
  // ourselves.
  RBACProxy(name, port):: RBACProxy(name, port),

  // Returns all the trappings for a new experiment. New experiments should
  // need to add one new container.
  Experiment(name, index, datatypes, bucket):: Experiment(name, index, datatypes, bucket),

  // Returns a volumemount for a given datatype. All produced volume mounts
  // in /var/spool/name/
  VolumeMount(name):: VolumeMount(name),

  // Returns a "container" configuration for pusher that will upload the named experiment datatypes.
  // Users MUST declare a "pusher-credentials" volume as part of the deployment.
  Pusher(expName, tcpPort, datatypes, hostNetwork, bucket):: Pusher(expName, tcpPort, datatypes, hostNetwork, bucket),

  // Helper object containing uuid-related filenames, volumes, and volumemounts.
  uuid: uuid,

  // The NDT tag to use for containers.
  ndtVersion: ndtVersion,
}
