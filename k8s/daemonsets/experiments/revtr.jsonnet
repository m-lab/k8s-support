local exp = import '../templates.jsonnet';

exp.Experiment('revtr', 3, 'pusher-' + std.extVar('PROJECT_ID'), 'none', []) + {
    spec+: {
        template+: {
            spec+: {
                containers+: [
                    {
                        name: 'revtrvp',
                        image: 'measurementlab/revtrvp:v0.0.2',
                        args: [
                            '/root.crt',
                            '/plvp.config',
                        ],
                    }
                ],
                [if std.extVar('PROJECT_ID') != 'mlab-sandbox' then 'terminationGracePeriodSeconds']: 180,
            }
        }
    }
}
