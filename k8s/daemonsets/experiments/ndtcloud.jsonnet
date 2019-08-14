local exp = import '../templates.jsonnet';
local expName = 'ndtcloud';

exp.ExperimentNoIndex(expName, ['ndt5', 'ndt7'], true, 'pusher-ndtcloud-' + std.extVar('PROJECT_ID')) + {
  spec+: {
    template+: {
      spec+: {
        containers+: [
          {
            name: 'ndt-server',
            image: 'measurementlab/ndt-server:' + exp.ndtVersion,
            args: [
              '-key=/certs/key.pem',
              '-cert=/certs/cert.pem',
              '-uuid-prefix-file=' + exp.uuid.prefixfile,
              '-prometheusx.listen-address=127.0.0.1:9990',
              '-datadir=/var/spool/' + expName,
            ],
            volumeMounts: [
              {
                mountPath: '/certs',
                name: 'ndt-tls',
                readOnly: true,
              },
              exp.uuid.volumemount,
              exp.VolumeMount(expName),
            ],
            ports: [],
          },

          exp.RBACProxy(expName, 9990),

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
        terminationGracePeriodSeconds: 150,
        volumes+: [
          {
            name: 'ndt-tls',
            secret: {
              secretName: 'ndt-tls',
            },
          },
        ],
        nodeSelector: {
          'mlab/type': 'cloud',
          'mlab/run': expName,
        },
        hostNetwork: true,
      },
    },
  },
}
