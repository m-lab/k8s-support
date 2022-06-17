local datatypes = ['ndt5', 'ndt7'];
local exp = import '../templates.jsonnet';
local expName = 'ndt';
local services = [
  'ndt/ndt7=ws:///ndt/v7/download,ws:///ndt/v7/upload,wss:///ndt/v7/download,wss:///ndt/v7/upload',
  'ndt/ndt5=ws://:3001/ndt_protocol,wss://:3010/ndt_protocol',
];

exp.Experiment(expName, 2, 'pusher-' + std.extVar('PROJECT_ID'), "none", datatypes) + {
  spec+: {
    template+: {
      metadata+: {
        annotations+: {
          "secret.reloader.stakater.com/reload": "measurement-lab-org-tls",
        },
      },
      spec+: {
        nodeSelector+: {
          'mlab/ndt-version': 'production',
        },
        containers+: [
          {
            name: 'ndt-server',
            image: 'measurementlab/ndt-server:' + exp.ndtVersion,
            // This command section is somewhat of a workaround to get a value
            // to pass to the -max-rate flag of ndt-server. The default
            // ENTRYPOINT for the ndt-server image is /ndt-server, but this
            // overrides it to allow us to inject -max-rate using a value from
            // a ConfigMap that is generated by the k8s-support build process.
            command: [
              "/bin/sh", "-c",
              "n=$(NODE_NAME); m=$(cat /etc/" + std.extVar('MAX_RATES_CONFIGMAP') + "/$n); /ndt-server -txcontroller.max-rate=$m $@",
              "--",
            ],
            args: [
              '-uuid-prefix-file=' + exp.uuid.prefixfile,
              '-prometheusx.listen-address=$(PRIVATE_IP):9990',
              '-datadir=/var/spool/' + expName,
              '-txcontroller.device=net1',
              '-htmldir=html/mlab',
              '-key=/certs/tls.key',
              '-cert=/certs/tls.crt',
              '-token.machine=$(NODE_NAME)',
              '-token.verify-key=/verify/jwk_sig_EdDSA_locate_20200409.pub',
              '-ndt7.token.required=true',
              '-label=type=physical',
              '-label=deployment=stable',
            ],
            env: [
              {
                name: 'PRIVATE_IP',
                valueFrom: {
                  fieldRef: {
                    fieldPath: 'status.podIP',
                  },
                },
              },
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
                mountPath: '/etc/' + std.extVar('MAX_RATES_CONFIGMAP'),
                name: std.extVar('MAX_RATES_CONFIGMAP'),
                readOnly: true,
              },
              {
                mountPath: '/verify',
                name: 'locate-verify-keys',
                readOnly: true,
              },
              exp.uuid.volumemount,
            ] + [
              exp.VolumeMount(expName + '/' + d) for d in datatypes
            ],
            ports: [
              {
                containerPort: 9990,
              },
            ],

          }]  + std.flattenArrays([
            exp.Heartbeat(expName, 9996, true, services),
          ]),
        volumes+: [
          {
            name: 'measurement-lab-org-tls',
            secret: {
              secretName: 'measurement-lab-org-tls',
            },
          },
          {
            name: std.extVar('MAX_RATES_CONFIGMAP'),
            configMap: {
              name: std.extVar('MAX_RATES_CONFIGMAP'),
            },
          },
          {
            name: 'locate-verify-keys',
            secret: {
              secretName: 'locate-verify-keys',
            },
          },
        ],
      },
    },
  },
}
