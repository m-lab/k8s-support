local ndtVersion = 'v0.20.17';
// The canary version is expected to be greater than or equal to
// the current stable version.
local ndtCanaryVersion = 'v0.20.17';
local PROJECT_ID = std.extVar('PROJECT_ID');

// The default grace period after k8s sends SIGTERM is 30s. We
// extend the grace period to give time for the following
// shutdown sequence. After the grace period, kubernetes sends
// SIGKILL.
//
// Expected container shutdown sequence:
//
//  * k8s sends SIGTERM to container
//  * container enables lame duck status
//  * monitoring reads lame duck status (60s max)
//  * mlab-ns updates server status (60s max)
//  * all currently running tests complete. (30s max)
//  * give everything an additional 30s to be safe
//  * 60s + 60s + 30s + 30s = 180s grace period
local terminationGracePeriodSeconds = 180;

local uuid = {
  initContainer: {
    // Write out the UUID prefix to a well-known location.
    // more on this, see DESIGN.md
    // https://github.com/m-lab/uuid/
    name: 'set-up-uuid-prefix-file',
    image: 'measurementlab/uuid:v1.0.0',
    args: [
      '-filename=' + uuid.prefixfile,
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
    ],
    securityContext: {
      runAsUser: 0,
    },
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

local VolumeMountDatatypeSchema() = {
  mountPath: '/var/spool/datatypes',
  name: 'var-spool-datatypes',
};

local RBACProxy(name, port) = {
  name: 'kube-rbac-proxy-' + name,
  image: 'quay.io/brancz/kube-rbac-proxy:v0.11.0',
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
  securityContext: {
    capabilities: {
      drop: [
        'all',
      ],
    },
  },
};

// Set the owner:group of the experiment data directory to 65534:65534, and set
// the directory with setguid. hostPath volumes will be owned by the kubelet
// user (i.e., root). We are unable to use the fsGroup securityContext feature
// on hostPath volumes:
// https://kubernetes.io/docs/concepts/storage/volumes/#hostpath
// https://github.com/kubernetes/minikube/issues/1990
local setDataDirOwnership(name) = {
  local dataDir = VolumeMount(name).mountPath,
  initContainer: {
    name: 'set-data-dir-perms',
    image: 'alpine:3.17',
    command: [
      '/bin/sh',
      '-c',
      'cd ' + dataDir + ' && chown -R 65534:65534 . && chmod -R 2775 .',
    ],
    securityContext: {
      runAsUser: 0,
    },
    volumeMounts: [
      VolumeMount(name),
    ],
  },
};

// The datatypes directory is where autoloading experiments drop their schema.
// This directory is different from where experiments store their data.
local setDatatypesDirOwnership() = {
  local dataDir = VolumeMountDatatypeSchema().mountPath,
  initContainer: {
    name: 'set-datatypes-dir-perms',
    image: 'alpine:3.17',
    command: [
      '/bin/sh',
      '-c',
      'chown -R 65534:65534 ' + dataDir,
    ],
    securityContext: {
      runAsUser: 0,
    },
    volumeMounts: [
      VolumeMountDatatypeSchema(),
    ],
  },
};

local tcpinfoServiceVolume = {
  volumemount: {
    mountPath: '/var/local/tcpinfoeventsocket',
    name: 'tcpinfoeventsocket',
    readOnly: false,
  },
  volume: {
    emptyDir: {},
    name: 'tcpinfoeventsocket',
  },
  socketFilename: '/var/local/tcpinfoeventsocket/tcpevents.sock',
};

local uuidannotatorServiceVolume = {
  volumemount: {
    mountPath: '/var/local/uuidannotatorsocket',
    name: 'uuidannotatorsocket',
    readOnly: false,
  },
  volume: {
    emptyDir: {},
    name: 'uuidannotatorsocket',
  },
  socketFilename: '/var/local/uuidannotatorsocket/annotator.sock',
};

local Tcpinfo(expName, tcpPort, hostNetwork, anonMode) = [
  {
    name: 'tcp-info',
    image: 'measurementlab/tcp-info:v1.6.0',
    args: [
      if hostNetwork then
        '-prometheusx.listen-address=127.0.0.1:' + tcpPort
      else
        '-prometheusx.listen-address=$(PRIVATE_IP):' + tcpPort
      ,
      '-output=' + VolumeMount(expName).mountPath + '/tcpinfo',
      '-uuid-prefix-file=' + uuid.prefixfile,
      '-tcpinfo.eventsocket=' + tcpinfoServiceVolume.socketFilename,
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
    securityContext: {
      capabilities: {
        drop: [
          'all',
        ],
      },
    },
    volumeMounts: [
      VolumeMount(expName),
      tcpinfoServiceVolume.volumemount,
      uuid.volumemount,
    ],
  }] +
  if hostNetwork then
    [RBACProxy('tcpinfo', tcpPort)]
  else []
;

local Traceroute(expName, tcpPort, hostNetwork, anonMode) = [
  {
    name: 'traceroute-caller',
    image: 'measurementlab/traceroute-caller:v0.11.2',
    args: [
      if hostNetwork then
        '-prometheusx.listen-address=127.0.0.1:' + tcpPort
      else
        '-prometheusx.listen-address=$(PRIVATE_IP):' + tcpPort,
      '-traceroute-output=' + VolumeMount(expName).mountPath + '/scamper1',
      '-tcpinfo.eventsocket=' + tcpinfoServiceVolume.socketFilename,
      '-IPCacheTimeout=10m',
      '-IPCacheUpdatePeriod=1m',
      '-scamper.timeout=30m',
      '-scamper.tracelb-W=15',
      '-hopannotation-output=' + VolumeMount(expName).mountPath + '/hopannotation2',
      '-ipservice.sock=' + uuidannotatorServiceVolume.socketFilename,
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
    // scamper requires a lot of highly privileged capabilities :(
    securityContext: {
      capabilities: {
        add: [
          'DAC_OVERRIDE',
          'NET_RAW',
          'SETGID',
          'SETUID',
          'SYS_CHROOT',
        ],
        drop: [
          'all',
        ],
      },
    },
    volumeMounts: [
      VolumeMount(expName),
      tcpinfoServiceVolume.volumemount,
      uuidannotatorServiceVolume.volumemount,
      uuid.volumemount,
    ],
  }] +
  if hostNetwork then
    [RBACProxy('traceroute', tcpPort)]
  else []
;

local Pcap(expName, tcpPort, hostNetwork, siteType, anonMode) = [
  {
    name: 'packet-headers',
    image: 'measurementlab/packet-headers:v0.7.2',
    args: [
      if hostNetwork then
        '-prometheusx.listen-address=127.0.0.1:' + tcpPort
      else
        '-prometheusx.listen-address=$(PRIVATE_IP):' + tcpPort,
      '-datadir=' + VolumeMount(expName).mountPath + '/pcap',
      '-tcpinfo.eventsocket=' + tcpinfoServiceVolume.socketFilename,
      '-stream=false',
      '-anonymize.ip=' + anonMode,
    ] + if siteType == 'virtual' then [
      // Only virtual nodes need to limit RAM beyond default values.
      '-maxidleram=1500MB',
      '-maxheap=2GB',
    ] else [
    ] + if expName == 'host' then [
      // The "host" experiment is currently the only experiment where
      // packet-headers needs to listen explictly on interface eth0.
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
    resources: if siteType == 'virtual' then {
      limits: {
        memory: '3G',
      },
    } else {},
    securityContext: {
      capabilities: {
        add: [
          'NET_RAW',
        ],
        drop: [
          'all',
        ],
      },
    },
    volumeMounts: [
      VolumeMount(expName),
      tcpinfoServiceVolume.volumemount,
      uuid.volumemount,
    ],
  }] +
  if hostNetwork then
    [RBACProxy('pcap', tcpPort)]
  else []
;


local Pusher(expName, tcpPort, datatypes, hostNetwork, bucket) = [
  {
    local version='v1.20.3',
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
      '-sigterm_wait_time=' + std.toString(terminationGracePeriodSeconds - 60) + 's',
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
    // ndt-virtual and responsiveness still run as root, so Pusher, for now,
    // needs to run as root to be able to manage data files owned by both root
    // and nobody. But only give it the DAC_OVERRIDE capability.
    securityContext: {
      capabilities: {
        add: [
          'DAC_OVERRIDE',
        ],
        drop: [
          'all',
        ],
      },
      runAsUser: 0,
    },
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
  else []
;

local Jostler(expName, tcpPort, datatypesAutoloaded, hostNetwork, bucket) = [
  {
    name: 'jostler',
    image: 'measurementlab/jostler:v1.0.9',
    args: [
      if hostNetwork then
        '-prometheusx.listen-address=127.0.0.1:' + tcpPort
      else
        '-prometheusx.listen-address=$(PRIVATE_IP):' + tcpPort,
      '-gcs-bucket=' + bucket,
      '-gcs-data-dir=autoload/v1',
      '-experiment=' + expName,
      '-bundle-size-max=52428800', // 50*1024*1024
      '-bundle-age-max=1h',
      '-local-data-dir=/var/spool',  // experiment will be appended by jostler
      '-extensions=.json',
      '-missed-age=2h',
      '-missed-interval=5m',
    ] + ['-datatype=' + d for d in datatypesAutoloaded] +
        ['-datatype-schema-file=' + d + ':/var/spool/datatypes/' + d + '.json' for d in datatypesAutoloaded],
    env: [
      {
        name: 'GOOGLE_APPLICATION_CREDENTIALS',
        value: '/etc/credentials/pusher.json', // jostler uses pusher's credentials
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
    securityContext: {
      capabilities: {
        drop: [
          'all',
        ],
      },
    },
    volumeMounts: [
      VolumeMount(expName),
      VolumeMountDatatypeSchema(),
      {
        mountPath: '/etc/credentials',
        name: 'pusher-credentials', // jostler uses pusher's credentials
        readOnly: true,
      },
    ],
  }] +
  if hostNetwork then
    [RBACProxy('jostler', tcpPort)]
  else []
;

local UUIDAnnotator(expName, tcpPort, hostNetwork) = [
  {
    name: 'uuid-annotator',
    image: 'measurementlab/uuid-annotator:v0.5.1',
    args: [
      if hostNetwork then
        '-prometheusx.listen-address=127.0.0.1:' + tcpPort
      else
        '-prometheusx.listen-address=$(PRIVATE_IP):' + tcpPort,
      '-datadir=' + VolumeMount(expName).mountPath + '/annotation2',
      '-tcpinfo.eventsocket=' + tcpinfoServiceVolume.socketFilename,
      '-ipservice.sock=' + uuidannotatorServiceVolume.socketFilename,
      '-maxmind.url=gs://downloader-' + PROJECT_ID + '/Maxmind/current/GeoLite2-City.tar.gz',
      '-routeview-v4.url=gs://downloader-' + PROJECT_ID + '/RouteViewIPv4/current/routeview.pfx2as.gz',
      '-routeview-v6.url=gs://downloader-' + PROJECT_ID + '/RouteViewIPv6/current/routeview.pfx2as.gz',
      '-siteinfo.url=https://siteinfo.' + PROJECT_ID + '.measurementlab.net/v2/sites/annotations.json',
      '-hostname=$(MLAB_NODE_NAME)',
    ],
    env: [
      {
        name: 'GOOGLE_APPLICATION_CREDENTIALS',
        value: '/etc/credentials/uuid-annotator.json',
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
    securityContext: {
      capabilities: {
        drop: [
          'all',
        ],
      },
    },
    volumeMounts: [
      VolumeMount(expName),
      tcpinfoServiceVolume.volumemount,
      uuidannotatorServiceVolume.volumemount,
      {
        mountPath: '/etc/credentials',
        name: 'uuid-annotator-credentials',
        readOnly: true,
      },
    ],
  }] +
  if hostNetwork then
    [RBACProxy('uuid-annotator', tcpPort)]
  else []
;

local Heartbeat(expName, tcpPort, hostNetwork, services) = [
  {
    name: 'heartbeat',
    image: 'measurementlab/heartbeat:v0.14.11',
    args: [
      if hostNetwork then
        '-prometheusx.listen-address=127.0.0.1:' + tcpPort
      else
        '-prometheusx.listen-address=$(PRIVATE_IP):' + tcpPort,
      if PROJECT_ID == 'mlab-oti' then
        '-heartbeat-url=wss://locate.measurementlab.net/v2/platform/heartbeat?key=$(API_KEY)'
      else
        '-heartbeat-url=wss://locate.' + PROJECT_ID + '.measurementlab.net/v2/platform/heartbeat?key=$(API_KEY)',
      '-registration-url=https://siteinfo.' + PROJECT_ID + '.measurementlab.net/v2/sites/registration.json',
      '-experiment=' + expName,
      '-hostname=' + expName + '-$(MLAB_NODE_NAME)',
      '-node=$(MLAB_NODE_NAME)',
      '-pod=$(MLAB_POD_NAME)',
      '-namespace=$(MLAB_NAMESPACE)',
      '-kubernetes-url=https://api-platform-cluster.' + PROJECT_ID + '.measurementlab.net:6443',
    ] + ['-services=' + s for s in services],
    env: [
      {
        name: 'API_KEY',
        valueFrom: {
          secretKeyRef: {
            name: 'locate-heartbeat-key',
            key: 'locate-heartbeat-key',
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
      {
        name: 'MLAB_POD_NAME',
        valueFrom: {
          fieldRef: {
            fieldPath: 'metadata.name',
          },
        },
      },
      {
        name: 'MLAB_NAMESPACE',
        valueFrom: {
          fieldRef: {
            fieldPath: 'metadata.namespace',
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
    securityContext: {
      capabilities: {
        drop: [
          'all',
        ],
      },
    },
    volumeMounts: [
      {
        mountPath: '/etc/credentials',
        name: 'locate-heartbeat-key',
        readOnly: true,
      },
    ],
  }] +
  if hostNetwork then
    [RBACProxy('heartbeat', tcpPort)]
  else []
;

local Metadata = {
  path: '/metadata',
  volumemount: {
    mountPath: Metadata.path,
    name: 'metadata',
    readOnly: true,
  },
  volume: {
    hostPath: {
      path: '/var/local/metadata',
      type: 'Directory',
    },
    name: 'metadata',
  },
};

local ExperimentNoIndex(name, bucket, anonMode, datatypes, datatypesAutoloaded, hostNetwork, siteType='physical') = {
  local allDatatypes =  ['tcpinfo', 'pcap', 'annotation2', 'scamper1', 'hopannotation2'] + datatypes,
  local allVolumes = datatypes + datatypesAutoloaded,
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
          'site-type': 'physical',
        },
      },
      spec: {
        containers:
          std.flattenArrays([
            Tcpinfo(name, 9991, hostNetwork, anonMode),
            Traceroute(name, 9992, hostNetwork, anonMode),
            Pcap(name, 9993, hostNetwork, siteType, anonMode),
            UUIDAnnotator(name, 9994, hostNetwork),
            Pusher(name, 9995, allDatatypes, hostNetwork, bucket),
          ] + if datatypesAutoloaded != [] then [Jostler(name, 9997, datatypesAutoloaded, hostNetwork, bucket)] else []),
        [if hostNetwork then 'serviceAccountName']: 'kube-rbac-proxy',
        initContainers: [
          uuid.initContainer,
          setDataDirOwnership(name).initContainer,
          setDatatypesDirOwnership().initContainer,
        ],
        nodeSelector: {
          'mlab/type': 'physical',
        },
        securityContext: {
          runAsGroup: 65534,
          runAsUser: 65534,
          // Pods with hostNetwork=true cannot set this sysctl.  Those
          // containers will run as root with cap_net_bind_service enabled.
          sysctls: if hostNetwork then [] else [
            {
              // Set this so that experiments can listen on port 80 as a
              // non-root user.
              name: 'net.ipv4.ip_unprivileged_port_start',
              value: '80',
            },
          ],
        },
        volumes: [
          {
            name: 'pusher-credentials',
            secret: {
              secretName: 'pusher-credentials',
            },
          },
          {
            name: 'uuid-annotator-credentials',
            secret: {
              secretName: 'uuid-annotator-credentials',
            },
          },
          {
            name: 'locate-heartbeat-key',
            secret: {
              secretName: 'locate-heartbeat-key',
            },
          },
          {
            name: 'var-spool-datatypes',
            hostPath: {
              path: '/var/spool/datatypes',
              type: 'DirectoryOrCreate',
            },
          },
          uuid.volume,
          volume(name),
          tcpinfoServiceVolume.volume,
          uuidannotatorServiceVolume.volume,
        ] + [
          volume(name + '/' + v) for v in allVolumes
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

local Experiment(name, index, bucket, anonMode, datatypes=[], datatypesAutoloaded=[]) = ExperimentNoIndex(name, bucket, anonMode, datatypes, datatypesAutoloaded, false) + {
  spec+: {
    template+: {
      metadata+: {
        annotations+: {
          'k8s.v1.cni.cncf.io/networks': '[{ "name": "index2ip-index-' + index + '-conf" }]',
          'v1.multus-cni.io/default-network': 'flannel-experiment-conf',
        },
      },
      spec+: {
        // NOTE(github.com/m-lab/k8s-support/issues/542): this overrides the
        // default kube-dns configuration because M-Lab pod networks bypass
        // kubernetes Services iptables rules.
        dnsPolicy: 'None',
        dnsConfig: {
          nameservers: ['8.8.8.8', '8.8.4.4'],
        },
        // Only enable extended grace period where production traffic is possible.
        [if std.extVar('PROJECT_ID') != 'mlab-sandbox' then 'terminationGracePeriodSeconds']: terminationGracePeriodSeconds,
      },
    },
  },
};

{
  // Returns a minimal experiment, suitable for adding a unique network config
  // before deployment. It is expected that most users of this library will use
  // Experiment().
  ExperimentNoIndex(name, bucket, anonMode, datatypes, datatypesAutoloaded, hostNetwork, siteType='physical'):: ExperimentNoIndex(name, bucket, anonMode, datatypes, datatypesAutoloaded, hostNetwork, siteType),

  // RBACProxy creates a https proxy for an http port. This allows us to serve
  // metrics securely over https, andto https-authenticate to only serve them to
  // ourselves.
  RBACProxy(name, port):: RBACProxy(name, port),

  // Returns all the trappings for a new experiment. New experiments should
  // need to add one new container.
  Experiment(name, index, bucket, anonMode, datatypes, datatypesAutoloaded):: Experiment(name, index, bucket, anonMode, datatypes, datatypesAutoloaded),

  // Returns a volumemount for a given datatype. All produced volume mounts
  // in /var/spool/name/
  VolumeMount(name):: VolumeMount(name),

  // Returns a "container" configuration for pusher that will upload the named experiment datatypes.
  // Users MUST declare a "pusher-credentials" volume as part of the deployment.
  Pusher(expName, tcpPort, datatypes, hostNetwork, bucket):: Pusher(expName, tcpPort, datatypes, hostNetwork, bucket),

  // Returns a "container" configuration for jostler that will upload the named experiment datatypes.
  // Because jostler uploads files to pusher's buckets, users MUST
  // declare a "pusher-credentials" volume as part of the deployment.
  Jostler(expName, tcpPort, datatypesAutoloaded, hostNetwork, bucket):: Jostler(expName, tcpPort, datatypesAutoloaded, hostNetwork, bucket),

  // Returns a "container" configuration for the heartbeat service.
  Heartbeat(expName, hostNetwork, services):: Heartbeat(expName, 9996, hostNetwork, services),

  // Volumes, volumemounts and other data and configs for experiment metadata.
  Metadata:: Metadata,

  // Helper object containing uuid-related filenames, volumes, and volumemounts.
  uuid: uuid,

  // The NDT tag to use for containers.
  ndtVersion: ndtVersion,

  // The NDT tag to use for canary nodes.
  ndtCanaryVersion: ndtCanaryVersion,

  // Changes the owner:group of the base data directory to nobody:nogroup, and
  // sets the permissions to 2775.
  setDataDirOwnership(name):: setDataDirOwnership(name),

  // How long k8s should give a pod to shut itself down cleanly.
  terminationGracePeriodSeconds: terminationGracePeriodSeconds,
}
