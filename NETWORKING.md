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

For an example of how to configure a pod to receive multiple IP addresses,
checkout the `k8s.v1.cni.cncf.io/networks` annotation in
[./k8s/daemonsets/experiments/ndt.yml](./k8s/daemonsets/experiments/ndt.yml) in
concert with it's `name:` containing the string `index2` (or really anything
that matches `index[0-9]+`).

Pods with no network config receive a default Flannel config that allows them to
communicate between cluster pods, but not to provide services to the outside
world.

## Kubernetes configs

All the kubernetes configs for cluster networking. They specify that all nodes
with the label `mlab/type=virtual` run flannel in the standard way, and all
nodes with the label `mlab/type=physical` run multus+flannel+ipvlan+index2ip in
our custom way. If a node has no value for the `mlab/type` label, the network
will likely not work at all.

## Debugging CNI plugins

To debug CNI plugins, modify the variable `KUBELET_KUBECONFIG_ARGS` in the file
`/etc/systemd/system/kubelet.service.d/10-kubeadm.conf` and add
`--cni-bin-dir=/usr/shimcni/bin/shim.sh`. Then `systemctl daemon-reload`, then
`systemctl restart kubelet`.

The directory `/usr/shimcni/bin` contains a set of symlinks named after all the
actual CNI plugins located in `/opt/bin/cni`, and they all point to `shim.sh`.
`shim.sh` is a fairly simple bash script that notes what name it was called as
(via the symlink), calls the real CNI plugin, and logs a bunch input and output
to a directory in `/tmp`. This allows you to see the data that was received by
any given CNI plugin, and also the data returned by that same CNI plugin.
