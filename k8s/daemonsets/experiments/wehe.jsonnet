local exp = import '../templates.jsonnet';

exp.Experiment('wehe', 1, 'pusher-' + std.extVar('PROJECT_ID'), ['replay']) + {
    spec+: {
        template+: {
            spec+: {
                containers+: [
                    {
                        name: 'wehe',
                        image: 'measurementlab/wehe:v0.1',
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
                        ],
                        volumeMounts: [
                            {
                                mountPath: '/wehe/ssl',
                                name: 'wehe-certs',
                                readOnly: true,
                            },
                            exp.VolumeMount('wehe'),
                        ],
                    }
                ],
                volumes+: [
                    {
                        name: 'wehe-certs',
                        secret: {
                            secretName: 'wehe-certs',
                        },
                    },
                ],
            }
        }
    }
}
