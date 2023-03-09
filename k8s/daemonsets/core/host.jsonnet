local nodeinfoConfig = import '../../../config/nodeinfo.jsonnet';

local exp = import '../templates.jsonnet';
local expName = 'host';

local nodeinfoconfig = import '../../../config/nodeinfo/config.jsonnet';

exp.ExperimentNoIndex(expName, 'pusher-' + std.extVar('PROJECT_ID'), "none", [], ['nodeinfo1'], true) + {
  spec+: {
    template+: {
      spec+: {
        containers+: [
          {
            name: 'nodeinfo',
            image: 'measurementlab/nodeinfo:v1.3.1', // pre-release
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
              {
                mountPath: '/var/spool/datatypes',
                name: 'var-spool-datatypes',
                readOnly: false,
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
