local datatypes = ['ndt5', 'ndt7'];
local exp = import '../templates.jsonnet';
local expName = 'ndt';
local services = [
  'ndt/ndt7=ws:///ndt/v7/download,ws:///ndt/v7/upload,wss:///ndt/v7/download,wss:///ndt/v7/upload',
  'ndt/ndt5=ws://:3001/ndt_protocol,wss://:3010/ndt_protocol',
];

exp.ExperimentNoIndex(expName, 'pusher-' + std.extVar('PROJECT_ID'), 'none', datatypes, [], true, 'virtual', true) + {
  metadata+: {
    name: expName + '-virtual-autojoin',
  },
  spec+: {
    selector+: {
      matchLabels+: {
        workload: expName + '-virtual-autojoin',
      },
    },
    template+: {
      metadata+: {
        annotations+: {
          'secret.reloader.stakater.com/reload': 'measurement-lab-org-tls',
        },
        labels+: {
          workload: expName + '-virtual-autojoin',
          'site-type': 'virtual',
          'mlab/project': std.extVar('PROJECT_ID'),
        },
      },
      spec+: {
        hostNetwork: true,
        nodeSelector: {
          'mlab/type': 'virtual',
          'mlab/run': expName + '-autojoin',
        },
        serviceAccountName: 'heartbeat-experiment',
        containers+: [
          {
            name: 'register-node',
            image: 'measurementlab/autojoin-register:v0.2.11',
            imagePullPolicy: 'Always',
            args: [
              '-endpoint=https://autojoin-dot-$(PROJECT).appspot.com/autojoin/v0/node/register',
              '-key=$(AUTOJOIN_API_KEY)',
              '-ipv4=@/metadata/external-ip',
              '-ipv6=@/metadata/external-ipv6',
              '-iata=@/metadata/iata-code',
              '-service=ndt',
              '-organization=mlab',
              '-output=/autonode',
              '-probability=@/metadata/probability',
              '-type=virtual',
              '-uplink=7g',
            ],
            env: [
              {
                name: 'PROJECT',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'metadata.labels[\'mlab/project\']',
                  },
                },
              },
              {
                name: 'AUTOJOIN_API_KEY',
                valueFrom: {
                  secretKeyRef: {
                    key: 'autojoin-api-key',
                    name: 'autojoin-api-key',
                  },
                },
              },
            ],
            volumeMounts: [
              {
                mountPath: '/autonode',
                name: 'autonode',
              },
              exp.Metadata.volumemount,
            ],
          },
          {
            name: 'ndt-server',
            image: 'measurementlab/ndt-server:' + exp.ndtVersion,
            args: [
              '-ndt5_addr=127.0.0.1:3002', // any non-public port.
              '-ndt5_ws_addr=:3001', // default, public ndt5 port.
              '-ndt5.token.required=true',
              '-ndt7.token.required=true',
              '-htmldir=html/mlab',
              '-uuid-prefix-file=' + exp.uuid.prefixfile,
              '-prometheusx.listen-address=127.0.0.1:9990',
              '-datadir=/var/spool/' + expName,
              '-key=/certs/tls.key',
              '-cert=/certs/tls.crt',
              '-token.verify-key=/verify/jwk_sig_EdDSA_locate_20200409.pub',
              '-token.machine=@/autonode/hostname',
              '-txcontroller.device=ens4',
              // GCE VMs have an egress rate limit of 7Gbps to Internet
              // addresses. Setting max-rate to 4Gbps should leave headroom for
              // very fast clients.
              '-txcontroller.max-rate=4000000000',
              '-label=type=virtual',
              '-label=deployment=stable',
              '-label=external-ip=@' + exp.Metadata.path + '/external-ip',
              '-label=external-ipv6=@' + exp.Metadata.path + '/external-ipv6',
              '-label=machine-type=@' + exp.Metadata.path + '/machine-type',
              '-label=network-tier=@' + exp.Metadata.path + '/network-tier',
              '-label=zone=@' + exp.Metadata.path + '/zone',
              '-label=managed=@' + exp.Metadata.path + '/managed',
              '-label=loadbalanced=@' + exp.Metadata.path + '/loadbalanced',
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
              {
                mountPath: '/autonode',
                name: 'autonode',
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
          exp.Heartbeat(expName, true, services, true),
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
