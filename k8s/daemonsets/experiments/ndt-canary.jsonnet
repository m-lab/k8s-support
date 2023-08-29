local datatypes = ['ndt5', 'ndt7'];
local exp = import '../templates.jsonnet';
local expName = 'ndt';
local services = [
  'ndt/ndt7=ws:///ndt/v7/download,ws:///ndt/v7/upload,wss:///ndt/v7/download,wss:///ndt/v7/upload',
  'ndt/ndt5=ws://:3001/ndt_protocol,wss://:3010/ndt_protocol',
];

exp.ExperimentNoIndex(expName, 'pusher-' + std.extVar('PROJECT_ID'), 'none', datatypes, [], true, 'virtual') + {
  metadata+: {
    name: expName + '-canary',
  },
  spec+: {
    selector+: {
      matchLabels+: {
        workload: expName + '-canary',
      },
    },
    template+: {
      metadata+: {
        annotations+: {
          'secret.reloader.stakater.com/reload': 'measurement-lab-org-tls',
        },
        labels+: {
          workload: expName + '-canary',
          'site-type': 'virtual',
          'vector.dev/exclude': 'true',
        },
      },
      spec+: {
        hostNetwork: true,
        nodeSelector: {
          'mlab/type': 'virtual',
          'mlab/ndt-version': 'canary',
        },
        serviceAccountName: 'heartbeat-experiment',
        containers+: [
          {
            name: 'ndt-server',
            image: 'measurementlab/ndt-server:' + exp.ndtCanaryVersion,
            args: [
              '-ndt5_addr=127.0.0.1:3002', // any non-public port.
              '-ndt5_ws_addr=:3001', // default, public ndt5 port.
              '-ndt5.token.required=true',
              '-ndt7.token.required=true',
              '-token.machine=$(NODE_NAME)',
              '-htmldir=html/mlab',
              '-uuid-prefix-file=' + exp.uuid.prefixfile,
              '-prometheusx.listen-address=127.0.0.1:9990',
              '-datadir=/var/spool/' + expName,
              '-key=/certs/tls.key',
              '-cert=/certs/tls.crt',
              '-token.verify-key=/verify/jwk_sig_EdDSA_locate_20200409.pub',
              '-txcontroller.device=bond0',
              // Equinix machines of type m3-small-x86 have a 50Gbps
              // unthrottled link. Set max-rate to 40Gbps.
              '-txcontroller.max-rate=40000000000',
              '-label=type=virtual',
              '-label=deployment=canary',
              '-label=external-ip=@' + exp.Metadata.path + '/external-ip',
              '-label=external-ipv6=@' + exp.Metadata.path + '/external-ipv6',
              '-label=machine-type=@' + exp.Metadata.path + '/machine-type',
              '-label=network-tier=@' + exp.Metadata.path + '/network-tier',
              '-label=zone=@' + exp.Metadata.path + '/zone',
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
              exp.uuid.volumemount,
              exp.Metadata.volumemount,
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
          exp.Metadata.volume,
        ],
      },
    },
  },
}
