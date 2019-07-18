local exp = import '../templates.jsonnet';

local nodeinfoconfig = import '../../../config/nodeinfo/config.jsonnet';
local nodeinfo_datatypes = [d.Datatype for d in nodeinfoconfig];

exp.ExperimentNoIndex('host', nodeinfo_datatypes, true) + {
  spec+: {
    template+: {
      spec+: {
        containers+: [
          {
            name: 'nodeinfo',
            image: 'measurementlab/nodeinfo:v1.2',
            args: [
              '-datadir=/var/spool/host',
              '-wait=1h',
              '-prometheusx.listen-address=127.0.0.1:9990',
              '-config=/etc/nodeinfo/config.json',
            ],
            volumeMounts: [
              {
                mountPath: '/etc/nodeinfo',
                name: 'nodeinfo-config',
                readOnly: true,
              },
              exp.VolumeMount('host'),
            ],
          },
          exp.RBACProxy('nodeinfo', 9990),
        ],
        hostNetwork: true,
        hostPID: true,
        volumes+: [
          {
            configMap: {
              name: 'nodeinfo-config',
            },
            name: 'nodeinfo-config',
          },
        ],
      },
    },
  },
}
