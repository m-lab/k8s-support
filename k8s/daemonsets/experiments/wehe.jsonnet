local exp = import '../templates.jsonnet';

exp.Experiment('wehe', 1, 'pusher-' + std.extVar('PROJECT_ID'), ['replay']) + {
    spec+: {
        template+: {
            spec+: {
                containers+: [
                    {
                        name: 'wehe',
                        image: 'measurementlab/wehe:general-start',
                        args: [
                            'wehe.$(MLAB_NODE_NAME)'
                        ],
                        env: [
                            {
                                name: 'MLAB_NODE_NAME',
                                valueFrom: {
                                    fieldRef: {
                                        fieldPath: 'spec.nodeName',
                                    },
                                },
                            },
                            {
                                name: 'CA_KEY',
                                value: '/wehe-ca/ca.key',
                            },
                            {
                                name: 'CA_CERT',
                                value: '/wehe-ca/ca.crt',
                            },
                        ],
                        volumeMounts: [
                            {
                                mountPath: '/wehe-ca',
                                name: 'wehe-ca',
                                readOnly: true,
                            },
                            exp.VolumeMount('wehe'),
                        ],
                    }
                ],
                volumes+: [
                    {
                        name: 'wehe-ca',
                        secret: {
                            secretName: 'wehe-ca',
                        },
                    },
                ],
            }
        }
    }
}
