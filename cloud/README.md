All setup and startup scripts for cloud and cloud networking.

# Master node setup

We use `kubeadm` to set everything up.  It's alpha, but it works pretty well.
The `setup_cloud_k8s_master.sh` script, when run with no arguments, sets up
`k8s-platform-master` in the `mlab-sandbox` project.

# Network

Every Node in a k8s system is allocated its own /24. We have 500+ nodes already,
and through platform expansion that number could at least quadruple. So we need
a subnet that supports more than 2000 /24 address blocks. Doing the math (`32 -
log_2(256 ips per node * 2000 nodes on the platform) = 12`) it looks like we
need a `/12` block.  The `10.0.0.0/8` block is used by Google cloud, so we either need to fight their configs or use one of the others.  `192.168.0.0/16` is too small, so that leaves the little-known `172.16.0.0/12` block for the M-Lab platform.

We will use Calico to set things up. It uses standard pieces, and has a flexible
config language that allows us to provide rich options and/or specified external
IPs to some pods.
