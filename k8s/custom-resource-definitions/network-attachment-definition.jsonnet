// The new CRD type used by Multus.
//
// This file must be applied first. Kubernetes does not support defining new
// data types and new resources of that type at the same time.
{
  apiVersion: 'apiextensions.k8s.io/v1',
  kind: 'CustomResourceDefinition',
  metadata: {
    name: 'network-attachment-definitions.k8s.cni.cncf.io',
  },
  spec: {
    group: 'k8s.cni.cncf.io',
    names: {
      kind: 'NetworkAttachmentDefinition',
      listKind: 'NetworkAttachmentDefinitionList',
      plural: 'network-attachment-definitions',
      shortNames: [
        'network',
        'net-attach-def',
        'net',
      ],
      singular: 'network-attachment-definition',
    },
    scope: 'Namespaced',
    versions: [
      {
        name: 'v1',
        served: true,
        storage: true,
        schema: {
          openAPIV3Schema: {
            type: 'object',
            properties: {
              spec: {
                type: 'object',
                properties: {
                  config: {
                    type: 'string',
                  },
                },
              },
            },
          },
        },
      },
    ],
  },
}
