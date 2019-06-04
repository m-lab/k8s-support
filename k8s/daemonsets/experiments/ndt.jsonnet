local exp = import 'library.jsonnet';

exp.Experiment('ndt', 2, ['legacy', 'ndt7']) + {
  spec+: {
    template+: {
      spec+: {
        containers+: [
          {
            name: 'ndt-server',
            image: 'measurementlab/ndt-server:v0.9.0',
            args: [
              '-key=/certs/key.pem',
              '-cert=/certs/cert.pem',
              '-uuid-prefix-file=' + exp.uuid.prefixfile,
              '-prometheusx.listen-address=:9090',
              '-datadir=/var/spool/ndt',
            ],
            ports: [
              {
                containerPort: 9090,
              },
            ],
            volumeMounts: [
              {
                mountPath: '/certs',
                name: 'ndt-tls',
                readOnly: true,
              },
              exp.uuid.volumemount,
              exp.VolumeMount('ndt', 'legacy'),
              exp.VolumeMount('ndt', 'ndt7'),
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
        terminationGracePeriodSeconds: 150,
        volumes+: [
          {		
            name: 'ndt-tls',		
            secret: {		
              secretName: 'ndt-tls',		
            },
          },
        ],
      },
    },
  },
}
