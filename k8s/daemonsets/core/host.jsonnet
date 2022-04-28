local nodeinfoConfig = import '../../../config/nodeinfo.jsonnet';

local exp = import '../templates.jsonnet';
local expName = 'host';

local nodeinfoconfig = import '../../../config/nodeinfo/config.jsonnet';
local nodeinfo_datatypes = [d.Datatype for d in nodeinfoconfig];

exp.ExperimentNoIndex(expName, 'pusher-' + std.extVar('PROJECT_ID'), "none", nodeinfo_datatypes, true) + {
  spec+: {
    template+: {
      metadata+: {
        annotations+: {
          'secret.reloader.stakater.com/reload': 'measurement-lab-org-tls',
        },
      },
      spec+: {
        containers+: [
          {
            args: [
              '-base-port=443',
              '-public-name=$(MLAB_NODE_NAME)',
              '-domain=$(MLAB_NODE_NAME)',
              '-cert-file=/certs/tls.crt',
              '-key-file=/certs/tls.key',
              '-listen-addr=0.0.0.0',
            ],
            env: [
              {
                name: 'MLAB_NODE_NAME',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'spec.nodeName',
                  },
                },
              },
            ],
            image: 'soltesz/aimscore-server:v0.0',
            name: 'aimscore-server',
            volumeMounts: [
              {
                mountPath: '/certs',
                name: 'measurement-lab-org-tls',
                readOnly: true,
              },
            ],
          },
          {
            name: 'nodeinfo',
            image: 'measurementlab/nodeinfo:v1.2.1',
            args: [
              '-datadir=/var/spool/' + expName,
              '-wait=6h',
              '-prometheusx.listen-address=127.0.0.1:9990',
              '-config=/etc/nodeinfo/config.json',
            ],
            volumeMounts: [
              {
                mountPath: '/etc/nodeinfo',
                name: 'nodeinfo-config',
                readOnly: true,
              },
              {
                mountPath: '/etc/os-release',
                name: 'etc-os-release',
                readOnly: true,
              },
              exp.VolumeMount(expName),
            ],
          },
          exp.RBACProxy('nodeinfo', 9990),
        ],
        hostNetwork: true,
        hostPID: true,
        [if std.extVar('PROJECT_ID') != 'mlab-sandbox' then 'terminationGracePeriodSeconds']: 180,
        volumes+: [
          {
            name: 'measurement-lab-org-tls',
            secret: {
              secretName: 'measurement-lab-org-tls',
            },
          },
          {
            configMap: {
              name: nodeinfoConfig.metadata.name,
            },
            name: 'nodeinfo-config',
          },
          {
            hostPath: {
              path: '/etc/os-release',
              type: 'File',
            },
            name: 'etc-os-release',
          },
        ],
      },
    },
  },
}
