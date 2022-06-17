local datatypes = ['ndt5', 'ndt7'];
local exp = import '../templates.jsonnet';
local expName = 'ndt';
local services = [
  'ndt/ndt7=ws:///ndt/v7/download,ws:///ndt/v7/upload,wss:///ndt/v7/download,wss:///ndt/v7/upload',
  'ndt/ndt5=ws://:3001/ndt_protocol,wss://:3010/ndt_protocol',
];

local metadata = {
  path: '/metadata',
  volumemount: {
    mountPath: metadata.path,
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

exp.ExperimentNoIndex(expName, 'pusher-' + std.extVar('PROJECT_ID'), 'none', datatypes, true) + {
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
          'secret.reloader.stakater.com/reload': 'measurement-lab-org-tls',
        },
        labels+: {
          workload: expName + '-virtual',
          'site-type': 'virtual',
        },
      },
      spec+: {
        hostNetwork: true,
        nodeSelector: {
          'mlab/type': 'virtual',
          'mlab/run': expName,
        },
        containers+: [
          {
            name: 'ndt-server',
            image: 'measurementlab/ndt-server:' + exp.ndtVersion,
            args: [
              // port 3002 is arbitrary.
              '-ndt5_addr=127.0.0.1:3002',
              '-ndt5_ws_addr=:3001',
              '-ndt5.token.required=true',
              '-ndt7.token.required=true',
              '-uuid-prefix-file=' + exp.uuid.prefixfile,
              '-prometheusx.listen-address=127.0.0.1:9990',
              '-datadir=/var/spool/' + expName,
              '-key=/certs/tls.key',
              '-cert=/certs/tls.crt',
              '-token.machine=$(NODE_NAME)',
              '-token.verify-key=/verify/jwk_sig_EdDSA_locate_20200409.pub',
              '-txcontroller.device=ens4',
              '-txcontroller.max-rate=150000000',
              '-label=type=virtual',
              '-label=deployment=canary',
              '-label=external-ip=@' + metadata.path + '/external-ip',
              '-label=external-ipv6=@' + metadata.path + '/external-ipv6',
              '-label=machine-type=@' + metadata.path + '/machine-type',
              '-label=network-tier=@' + metadata.path + '/network-tier',
              '-label=zone=@' + metadata.path + '/zone',
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
            ],
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
              exp.uuid.volumemount,
              metadata.volumemount,
            ] + [
              exp.VolumeMount(expName + '/' + d)
              for d in datatypes
            ],
            ports: [],
          },
          exp.RBACProxy(expName, 9990),
        ] + std.flattenArrays([
          exp.Heartbeat(expName, true, services),
        ]),
        [if std.extVar('PROJECT_ID') != 'mlab-sandbox' then 'terminationGracePeriodSeconds']: exp.terminationGracePeriodSeconds,
        volumes+: [
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
          metadata.volume,
        ],
      },
    },
  },
}
