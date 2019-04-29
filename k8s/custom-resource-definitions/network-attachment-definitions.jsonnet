// The new CRD type used by Multus.
//
// This file must be applied first. Kubernetes does not support defining new
// data types and new resources of that type at the same time.
{
  apiVersion: 'apiextensions.k8s.io/v1beta1',
  kind: 'CustomResourceDefinition',
  metadata: {
    name: 'network-attachment-definitions.k8s.cni.cncf.io',
  },
  spec: {
    group: 'k8s.cni.cncf.io',
    names: {
      kind: 'NetworkAttachmentDefinition',
      plural: 'network-attachment-definitions',
      shortNames: [
        'net-attach-def',
        'net',
      ],
      singular: 'network-attachment-definition',
    },
    scope: 'Namespaced',
    validation: {
      openAPIV3Schema: {
        properties: {
          spec: {
            properties: {
              config: {
                type: 'string',
              },
            },
          },
        },
      },
    },
    version: 'v1',
  },
}
