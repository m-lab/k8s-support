local exp = import '../templates.jsonnet';
local plvp_config = if std.extVar('PROJECT_ID') == 'mlab-oti' then
    '/plvp_mlab.config.production'
  else
    '/plvp_mlab.config.sandbox';

[
  exp.Experiment('revtr', 3, 'pusher-' + std.extVar('PROJECT_ID'), 'none', [], []) + {
    spec+: {
      template+: {
        spec+: {
          containers+: [
            {
              name: 'revtrvp',
              image: 'measurementlab/revtrvp:v0.4.0',
              args: [
                '/server.crt',
                plvp_config
              ],
              securityContext: {
                capabilities: {
                  // The container processes run as nobody:nogroup, but the
                  // scamper binary has/needs these capabilities.
                  // scamper in traceroute-caller also has most of these
                  // capabilities, except CHOWN. scamper in this container is
                  // version 20211212a, while traceroute-caller uses scamper
                  // version 20230302.  Perhaps the need for CHOWN was removed in
                  // the newer version?
                  // TODO(kinkade): if revtr updates scamper, check to see
                  // whether we can remove the CHOWN capability.
                  add: [
                    'CHOWN',
                    'DAC_OVERRIDE',
                    'NET_RAW',
                    'SETGID',
                    'SETUID',
                    'SYS_CHROOT',
                  ],
                  drop: [
                    'all',
                  ],
                },
              },
            }
          ],
          volumes+: [
            exp.Metadata.volume,
          ],
        }
      }
    }
  },
]
