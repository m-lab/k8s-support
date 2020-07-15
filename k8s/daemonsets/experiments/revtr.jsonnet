local exp = import '../templates.jsonnet';

exp.Experiment('revtr', 3, 'pusher-' + std.extVar('PROJECT_ID'), 'none', ['traffic']) + {
    spec+: {
        template+: {
            spec+: {
                containers+: [
                    {
                        name: 'revtrvp',
                        image: 'measurementlab/revtrvp:v0.0.5',
                        args: [
                            '/root.crt',
                            '/plvp.config',
                        ],
			volumeMounts: [
			  exp.VolumeMount('revtr/traffic'),
			],
                    }
                ],
            }
        }
    }
}
