local exp = import '../templates.jsonnet';

// Should this be 1?
exp.Experiment('wehe', 5, 'pusher-' + std.extVar('PROJECT_ID'), 'netblock', ['replay']) + {
    spec+: {
        template+: {
            spec+: {
                initContainers+: [
                    {
                        name: 'ca-copy',
                        image: 'busybox',
                        args: [
                            'cp', '/wehe-ca/ca.key', '/wehe-ca/ca.crt', '/wehe/ssl/',
                        ],
                        volumeMounts: [
                            {
                                mountPath: '/wehe/ssl/',
                                name: 'wehe-ca-cache',
                            },
                            {
                                mountPath: '/wehe-ca/',
                                name: 'wehe-ca',
                            },
                        ]
                    },
                ],
                containers+: [
                    {
                        name: 'wehe',
                        image: 'measurementlab/wehe:v0.1',
                        args: [
                            // should be wehe.$(MLAB_NODE_NAME)
                            'diff.mlab.$(MLAB_NODE_NAME)',
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
                                mountPath: '/wehe/ssl/',
                                name: 'wehe-ca-cache',
                            },
                            exp.VolumeMount('wehe'),
                        ],
                    }
                ],
                [if std.extVar('PROJECT_ID') != 'mlab-sandbox' then 'terminationGracePeriodSeconds']: 180,
                volumes+: [
                    {
                        name: 'wehe-ca-cache',
                        emptyDir: {},
                    },
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
