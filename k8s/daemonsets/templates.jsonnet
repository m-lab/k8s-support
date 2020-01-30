local ndtVersion = 'v0.13.3';

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
  name: std.strReplace(name, '/', '-') + '-data',
};

local VolumeMount(name) = {
  mountPath: '/var/spool/' + name,
  name: std.strReplace(name, '/', '-') + '-data',
};

// SOCATProxy creates a tunnel between localhost:<port> and the private pod
// IP:<port>. This allows operators and developers to use `kubectl port-forward`
// (which only binds to localhost) to connect to :<port>/debug/pprof for profile
// information.
local SOCATProxy(name, port) = {
  name: 'socat-proxy-' + name,
  image: 'alpine/socat',
  args: [
    // socat does not support long options.
    '-dd', // debug.
    'tcp-listen:' + port + ',bind=127.0.0.1,fork,reuseaddr',
    'tcp-connect:$(IP):' +  port,
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

local Tcpinfo(expName, tcpPort, hostNetwork, anonMode) = [
  {
    name: 'tcp-info',
    image: 'measurementlab/tcp-info:v1.4.0',
    args: [
      if hostNetwork then
        '-prometheusx.listen-address=127.0.0.1:' + tcpPort
      else
        '-prometheusx.listen-address=$(PRIVATE_IP):' + tcpPort
      ,
      '-output=' + VolumeMount(expName).mountPath + '/tcpinfo',
      '-uuid-prefix-file=' + uuid.prefixfile,
      '-tcpinfo.eventsocket=' + tcpinfoServiceVolume.eventsocketFilename,
      '-anonymize.ip=' + anonMode,
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
    [SOCATProxy('tcpinfo', tcpPort)]
;

local Traceroute(expName, tcpPort, hostNetwork) = [
  {
    name: 'traceroute-caller',
    image: 'measurementlab/traceroute-caller:v0.6.0',
    args: [
      if hostNetwork then
        '-prometheusx.listen-address=127.0.0.1:' + tcpPort
      else
        '-prometheusx.listen-address=$(PRIVATE_IP):' + tcpPort,
      '-outputPath=' + VolumeMount(expName).mountPath + '/traceroute',
      '-uuid-prefix-file=' + uuid.prefixfile,
      '-poll=false',
      '-tcpinfo.eventsocket=' + tcpinfoServiceVolume.eventsocketFilename,
      '-tracetool=scamper-daemon-with-scamper-backup',
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
    [SOCATProxy('traceroute', tcpPort)]
;

local Pcap(expName, tcpPort, hostNetwork) = [
  {
    name: 'packet-headers',
    image: 'measurementlab/packet-headers:v0.5.4',
    args: [
      if hostNetwork then
        '-prometheusx.listen-address=127.0.0.1:' + tcpPort
      else
        '-prometheusx.listen-address=$(PRIVATE_IP):' + tcpPort,
      '-datadir=' + VolumeMount(expName).mountPath + '/pcap',
      '-tcpinfo.eventsocket=' + tcpinfoServiceVolume.eventsocketFilename,
    ] + if hostNetwork then [
      '-interface=eth0',
    ] else [],
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
    [RBACProxy('pcap', tcpPort)]
  else
    [SOCATProxy('pcap', tcpPort)]
;


local Pusher(expName, tcpPort, datatypes, hostNetwork, bucket) = [
  {
    local version='v1.15',
    name: 'pusher',
    image: 'measurementlab/pusher:'+version,
    args: [
      if hostNetwork then
        '-prometheusx.listen-address=127.0.0.1:' + tcpPort
      else
        '-prometheusx.listen-address=$(PRIVATE_IP):' + tcpPort,
      '-bucket=' + bucket,
      '-experiment=' + expName,
      '-archive_size_threshold=50MB',
      '-sigterm_wait_time=120s',
      '-directory=/var/spool/' + expName,
      '-metadata=MLAB.server.name=$(MLAB_NODE_NAME)',
      '-metadata=MLAB.experiment.name=' + expName,
      '-metadata=MLAB.pusher.image=measurementlab/pusher:' + version,
      '-metadata=MLAB.pusher.src.url=https://github.com/m-lab/pusher/tree/' + version,
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
    [SOCATProxy('pusher', tcpPort)]
;

local ExperimentNoIndex(name, bucket, anonMode, datatypes, hostNetwork) = {
  // TODO(m-lab/k8s-support/issues/358): make this unconditional once traceroute
  // supports anonymization.
  local allDatatypes =  ['tcpinfo', 'pcap'] + datatypes +
      if anonMode == "none" then ['traceroute'] else [],
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
            Tcpinfo(name, 9991, hostNetwork, anonMode),
            if anonMode == "none" then
              Traceroute(name, 9992, hostNetwork) else [],
            Pcap(name, 9993, hostNetwork),
            Pusher(name, 9994, allDatatypes, hostNetwork, bucket),
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
        ] + [
          volume(name + '/' + d) for d in datatypes
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

local Experiment(name, index, bucket, anonMode, datatypes=[]) = ExperimentNoIndex(name, bucket, anonMode, datatypes, false) + {
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
  ExperimentNoIndex(name, bucket, anonMode, datatypes, hostNetwork):: ExperimentNoIndex(name, bucket, anonMode, datatypes, hostNetwork),

  // RBACProxy creates a https proxy for an http port. This allows us to serve
  // metrics securely over https, andto https-authenticate to only serve them to
  // ourselves.
  RBACProxy(name, port):: RBACProxy(name, port),

  // RBACProxy creates a localhost proxy for containers that listen on the
  // pod private IP. This allows operators to use kubectl port-forward to access
  // metrics and debug/pprof profiling safely through kubectl.
  SOCATProxy(name, port):: SOCATProxy(name, port),

  // Returns all the trappings for a new experiment. New experiments should
  // need to add one new container.
  Experiment(name, index, bucket, anonMode, datatypes):: Experiment(name, index, bucket, anonMode, datatypes),

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
