local datatypes = ['ndt5', 'ndt7'];
local exp = import '../templates.jsonnet';
local expName = 'ndt';

exp.ExperimentNoIndex(expName, 'pusher-' + std.extVar('PROJECT_ID'), "none", datatypes, true) + {
  metadata+: {
    name: expName + '-virtual',
  },
  spec+: {
    selector+: {
      matchLabels+: {
        workload: expName + '-virtual',
      },
    },
    template+: {
      metadata+: {
        annotations+: {
          "secret.reloader.stakater.com/reload": "measurement-lab-org-tls",
        },
        labels+: {
          workload: expName + '-virtual',
        },
      },
      spec+: {
        hostNetwork: true,
        nodeSelector: {
          'mlab/type': 'virtual',
          'mlab/run': expName,
        },
        initContainers+:[
          {
            name: 'curl',
            image: 'curlimages/curl:7.81.0',
            args: [
              '--header=Metadata-Flavor: Google',
              '--output=/var/local/metadata/external-ip',
              'http://metadata/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip'
            ],
            volumeMounts: [
              {
                mountPath: '/var/local/metadata',
                name: 'metadta',
                readOnly: false,
              },
            ],
          },
        ],
        containers+: [
          {
            name: 'ndt-server',
            image: 'measurementlab/ndt-server:' + exp.ndtVersion,
            command: [
              "/bin/sh", "-c",
              "external_ip=$(cat /usr/local/metadata/external-ip); /ndt-server -label=external-ip=$external_ip $@",
              "--",
            ],
            args: [
              '-uuid-prefix-file=' + exp.uuid.prefixfile,
              '-prometheusx.listen-address=127.0.0.1:9990',
              '-datadir=/var/spool/' + expName,
              '-key=/certs/tls.key',
              '-cert=/certs/tls.crt',
              '-label=type=virtual',
              '-label=deployment=stable',
              '-txcontroller.max-rate=150000000',
            ],
            volumeMounts: [
              {
                mountPath: '/certs',
                name: 'measurement-lab-org-tls',
                readOnly: true,
              },
              exp.uuid.volumemount,
              {
                mountPath: '/var/local/metadata',
                name: 'metadta',
                readOnly: true,
              },
            ] + [
              exp.VolumeMount(expName + '/' + d) for d in datatypes
            ],
            ports: [],
          },
          exp.RBACProxy(expName, 9990),
        ],
        [if std.extVar('PROJECT_ID') != 'mlab-sandbox' then 'terminationGracePeriodSeconds']: exp.terminationGracePeriodSeconds,
        volumes+: [
          {
            name: 'measurement-lab-org-tls',
            secret: {
              secretName: 'measurement-lab-org-tls',
            },
          },
          {
            emptyDir: {},
            name: 'metadata',
          },
        ],
      },
    },
  },
}
