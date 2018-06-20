All setup and startup scripts for cloud and cloud networking.

The scripts need to be run from this directory.

To set up a cloud master in sandbox, run ```bash
./setup_cloud_k8s_master.sh
```

To set up a cloud master in staging, run ```bash
GOOGLE_CLOUD_PROJECT=mlab-staging ./setup_cloud_k8s_master.sh
```

To set up a cloud master in staging, run ```bash
GOOGLE_CLOUD_PROJECT=mlab-oti ./setup_cloud_k8s_master.sh
```

# Master node setup

We use `kubeadm` to set everything up.  It's alpha, but it works pretty well.
The `setup_cloud_k8s_master.sh` script, when run with no arguments, sets up
`k8s-platform-master` in the `mlab-sandbox` project.

# Network

Our network is non-standard, because kubernetes does not expect to expose
services running on pods directly to the outside world.  So, for the pods that
run services we want to expose (running on platform nodes), we actually give
them two IP addresses using [multus](https://github.com/intel/multus-cni) to
speciy two interfaces instead of just one.  One internal one, handed out with
[flannel](https://github.com/coreos/flannel) in the standard way flannel does
things, and the other handed out by a combination of the [ipvlan CNI
plugin](https://github.com/containernetworking/plugins/tree/master/plugins/main/ipvlan)
and our own [index2ip CNI IPAM plugin](https://github.com/m-lab/index2ip).

# Kubernetes configs

All the kubernetes configs for the master are stored under [k8s/]. They specify
that all nodes with the label `mlab/type=cloud` run flannel in the standard way,
and all nodes with the label `mlab/type=platform` run
multus+flannel+ipvlan+index2ip in our custom way.
