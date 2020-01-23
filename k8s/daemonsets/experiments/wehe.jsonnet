local exp = import '../templates.jsonnet';

// Should this be 1?
exp.Experiment('wehe', 5, 'pusher-' + std.extVar('PROJECT_ID'), 'netblock', ['replay']) + {
    spec+: {
        template+: {
            spec+: {
                initContainers+: [
                    {
                        // Wehe expects the ca.key and ca.crt to be in a
                        // directory to which it can write the resulting keys
                        // produced. Secrets can't be mounted read/write, so
                        // before we start we copy those files from the mounted
                        // secret (read-only) to a cache directory (read-write).
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
                            'wehe.$(MLAB_NODE_NAME)',
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
                            // This volume exists in the volumes entry because
                            // 'replay' was one of the passed-in datatypes.
                            exp.VolumeMount('wehe/replay') + {
                                // Mount it where wehe expects to write it
                                mountPath: '/data/RecordReplay/ReplayDumps',
                            },
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
