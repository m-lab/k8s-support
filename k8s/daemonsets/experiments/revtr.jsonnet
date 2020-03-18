local exp = import '../templates.jsonnet';

exp.Experiment('revtr', 3, 'pusher-' + std.extVar('PROJECT_ID'), 'none', []) + {
    spec+: {
        template+: {
            spec+: {
                containers+: [
                    {
                        name: 'revtr',
                        image: 'measurementlab/revtrvp:v0.0.1',
                        args: [
                            '/root.crt',
                            '/plvp.config',
                            '-loglevel debug',
                        ],
                    }
                ],
                [if std.extVar('PROJECT_ID') != 'mlab-sandbox' then 'terminationGracePeriodSeconds']: 180,
            }
        }
    }
}
