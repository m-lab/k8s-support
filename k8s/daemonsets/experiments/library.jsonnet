local uuid = {
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

local Volume(name, datatype) = {
  hostPath: {
    path: '/cache/data/' + name + '/' + datatype,
    type: 'DirectoryOrCreate',
  },
  name: datatype + '-data',
};

local VolumeMount(name, datatype) = {
  mountPath: '/var/spool/' + name + '/' + datatype,
  name: datatype + '-data',
};

local Experiment(name, index, datatypes=[]) = {
  apiVersion: 'extensions/v1beta1',
  kind: 'DaemonSet',
  metadata: {
    name: name,
    namespace: 'default',
  },
  spec+: {
    selector: {
      matchLabels: {
        workload: name,
      },
    },
    template+: {
      metadata+: {
        annotations+: {
          'k8s.v1.cni.cncf.io/networks': '[{ "name": "index2ip-index-' + index + '-conf" }]',
          'prometheus.io/scrape': 'true',
          'v1.multus-cni.io/default-network': 'flannel-experiment-conf',
        },
        labels+: {
          workload: name,
        },
      },
      spec+: {
        containers+: [
          {
            name: 'tcpinfo',
            image: 'measurementlab/tcp-info:v0.0.8',
            args: [
              '-prometheusx.listen-address=:9091',
              '-output=' + VolumeMount(name, 'tcpinfo').mountPath,
              '-uuid-prefix-file=' + uuid.prefixfile,
            ],
            ports: [
              {
                containerPort: 9091,
              },
            ],
            volumeMounts: [
              VolumeMount(name, 'tcpinfo'),
              uuid.volumemount,
            ],
          },
          {
            name: 'traceroute',
            image: 'measurementlab/traceroute-caller:v0.0.5',
            args: [
              '-prometheusx.listen-address=:9092',
              '-outputPath=' + VolumeMount(name, 'traceroute').mountPath,
              '-uuid-prefix-file=' + uuid.prefixfile,
            ],
            ports: [
              {
                containerPort: 9092,
              },
            ],
            volumeMounts: [
              VolumeMount(name, 'traceroute'),
              uuid.volumemount,
            ],
          },
          {
            name: 'pusher',
            image: 'measurementlab/pusher:v1.8',
            args: [
              '-prometheusx.listen-address=:9093',
              '-experiment=ndt',
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
            ],
            ports: [
              {
                containerPort: 9093,
              },
            ],
            volumeMounts: [
              VolumeMount(name, 'tcpinfo'),
              VolumeMount(name, 'traceroute'),
              {
                mountPath: '/etc/credentials',
                name: 'pusher-credentials',
                readOnly: true,
              },
            ] + [VolumeMount(name, d) for d in datatypes],
          },
        ],
        initContainers+: [
          // TODO: this is a hack. Remove the hack by fixing the
          // contents of resolv.conf
          {
            name: 'fix-resolv-conf',
            image: 'busybox',
            command: [
              'sh',
              '-c',
              'echo "nameserver 8.8.8.8" > /etc/resolv.conf',
            ],
          },
          // Write out the UUID prefix to a well-known location. For
          // more on this, see DESIGN.md in
          // https://github.com/m-lab/uuid/
          {

            name: 'set-up-uuid-prefix-file',
            image: 'measurementlab/uuid:v0.1',
            args: [
              '-filename=' + uuid.prefixfile,
            ],
            volumeMounts: [
              uuid.volumemount + {
                readOnly: false,
              },
            ],
          },
        ],
        nodeSelector: {
          'mlab/type': 'platform',
        },
        volumes+: [
          {
            name: 'pusher-credentials',
            secret: {
              secretName: 'pusher-credentials',
            },
          },
          uuid.volume,
          Volume(name, 'traceroute'),
          Volume(name, 'tcpinfo'),
        ] + [Volume(name, d) for d in datatypes],
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

{
  // Returns all the trappings for a new experiment. New experiments should only
  // need to add one new container.
  Experiment(name, index, datatypes):: Experiment(name, index, datatypes),

  // Returns a volumemount for a given datatype. All produced volume mounts are
  // in /var/spool/name/datatype
  VolumeMount(name, datatype):: VolumeMount(name, datatype),

  // Helper object containing uuid-related filenames, volumes, and volumemounts.
  uuid: uuid,
}
