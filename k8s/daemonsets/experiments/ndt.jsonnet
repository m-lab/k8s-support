local datatypes = ['ndt5', 'ndt7'];
local exp = import '../templates.jsonnet';
local expName = 'ndt';

exp.Experiment(expName, 2, 'pusher-' + std.extVar('PROJECT_ID'), "none", datatypes) + {
  spec+: {
    template+: {
      spec+: {
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
              "n=$(NODE_NAME); m=$(cat /etc/" + std.extVar('MAX_RATES_CONFIGMAP') + "/$n); /ndt-server -max-rate=$m $@",
              "--",
            ],
            args: [
              '-key=/certs/key.pem',
              '-cert=/certs/cert.pem',
              '-uuid-prefix-file=' + exp.uuid.prefixfile,
              '-prometheusx.listen-address=$(PRIVATE_IP):9990',
              '-datadir=/var/spool/' + expName,
              '-txcontroller.device=net1',
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
                name: 'ndt-tls',
                readOnly: true,
              },
              {
                mountPath: '/etc/' + std.extVar('MAX_RATES_CONFIGMAP'),
                name: std.extVar('MAX_RATES_CONFIGMAP'),
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

          },
        ],
        // The default grace period after k8s sends SIGTERM is 30s. We
        // extend the grace period to give time for the following
        // shutdown sequence. After the grace period, kubernetes sends
        // SIGKILL.
        //
        // NDT pod shutdown sequence:
        //
        //  * k8s sends SIGTERM to NDT server
        //  * NDT server enables lame duck status
        //  * monitoring reads lame duck status (60s max)
        //  * mlab-ns updates server status (60s max)
        //  * all currently running tests complete. (30s max)
        //
        // Feel free to change this to a smaller value for speedy
        // sandbox deployments to enable faster compile-run-debug loops,
        // but 60+60+30=150 is what it needs to be for staging and prod.
        //
        // Only enable grace period where production traffic is possible.
        [if std.extVar('PROJECT_ID') != 'mlab-sandbox' then 'terminationGracePeriodSeconds']: 180,
        volumes+: [
          {
            name: 'ndt-tls',
            secret: {
              secretName: 'ndt-tls',
            },
          },
          {
            name: std.extVar('MAX_RATES_CONFIGMAP'),
            configMap: {
              name: std.extVar('MAX_RATES_CONFIGMAP'),
            },
          },
        ],
      },
    },
  },
}
