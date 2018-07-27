# The M-Lab platform cluster network 

Our network is non-standard, because kubernetes does not expect to expose
services running on pods directly to the outside world.  So, for the pods that
run services we want to expose (the ones running on platform nodes), we actually
give them two IP addresses using [multus](https://github.com/intel/multus-cni)
to specify two interfaces instead of just one.

For pods that are configured appropriately, we give out two IP addresses:
1. One internal one, handed out
with [flannel](https://github.com/coreos/flannel) in the standard way flannel
does things, and
2. another handed out by a combination of the [ipvlan CNI
plugin](https://github.com/containernetworking/plugins/tree/master/plugins/main/ipvlan)
and our own [index2ip CNI IPAM plugin](https://github.com/m-lab/index2ip).

For an example of how to configure a pod to receive multiple IP addresses, checkout the `networks:`
annotation in [../experiments/ndt.yml](../experiments/ndt.yml) in concert with
it's `name:` containing the string `index2` (or really anything that matches
`index[0-9]+`).

Pods with no network config receive a default Flannel config that allows them to
communicate between cluster pods, but not to provide services to the outside
world.

## Kubernetes configs

All the kubernetes configs for cluster networking. They specify that all nodes
with the label `mlab/type=cloud` run flannel in the standard way, and all nodes
with the label `mlab/type=platform` run multus+flannel+ipvlan+index2ip in our
custom way. If a node has no value for the `mlab/type` label, the network will
likely not work at all.
