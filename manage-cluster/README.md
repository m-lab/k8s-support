All setup and startup scripts for cloud and cloud networking.

The scripts need to be run from this directory.

To set up a high availability k8s cloud master and etcd, run the following
command, replacing <gcp-project-name> with the name of your GCP project (e.g.,
mlab-sandbox). NOTE: be sure look at and modify the global variables in the
script appropriately, else the results will not be what you want or expect.
```bash
./bootstrap_k8s_master_cluster.sh <gcp-project-name>
```

# Master node setup
We use `kubeadm` to set everything up.  It's alpha, but it works pretty well.

All the kubernetes configs for the master are stored under [./network/](./network/).

# The ./bootstrap\_k8s\_master\_cluster.sh script
This is a ridiculously long bash script, but it is not complicated; there are
just a lot of steps to take and commands to be run. Additionally, line wrapping
for readability makes is a good deal longer than it might otherwise be.  The
basic flow of the script boils down to this:

## Delete any old GCP objects
1. Delete any existing GCP objects so that we can start fresh.

## Configure external load balancing
1. Determine/create a public IP for the external load balancer, and update
   Google Cloud DNS accordingly.
2. Create an http-health-check for the GCE instances, which will be used by the
   external load balancer.
3. Create a target-pool for the external load balancer. Our GCE instances will
   be added to this target-pool.
4. Create a forwarding-rule that uses our external load balancer IP and our
   target-pool. In essence, this forwarding-rule is the load balancer.
5. Create a firewall rule allowing access to sshd and the k8s-api-server from
   anywhere.
 
## Configure internal load balancing
1. Determine/create an internal IP for the internal load balancer, and update
   Google Cloud DNS accordingly.
2. Create a basic TCP health-check for the token-servers, which run on each GCE
   instance.
3. Create a backend-service for the internal load balancer.
4. Create a forwarding-rule that uses our internal load balancer IP and our
   backend-service.
5. Create a firewall rule allowing unrestricted access between instances in our
   VPC subnet.

## Create one GCE instance for each zone in $GCE\_ZONES
1. Determine/create a public IP for the GCE instance, and update Google Cloud
   DNS accordingly.
2. Add the GCE instance to the target-pool created earlier.
3. Create an instance-group for the zone, and add the GCE instance to it.
4. Add the instance-group to the backend-service we created earlier.
5. Login to the GCE instance and install any necessary packages and
   configurations.
6. Configure k8s and etcd using `kubeadm`.

# gcp-loadbalancer-proxy
Our k8s api servers only run over HTTPS, but currently the TCP network load
balancer in GCP only supports HTTP health checks. Therefore we must run a
container that will expose an HTTP port and will run an HTTPS request on the
api-server on the localhost. From
https://cloud.google.com/load-balancing/docs/network/:

> Network Load Balancing relies on legacy HTTP Health checks for determining
> instance health. Even if your service does not use HTTP, you'll need to at least
> run a basic web server on each instance that the health check system can
> query.

https://github.com/kubernetes/kubernetes/issues/43784#issuecomment-415090237

For this purpose a special purpose
[gcp-loadbalancer-proxy](https://github.com/m-lab/gcp-loadbalancer-proxy) was
created. It gets installed automatically in bootstrap\_k8s\_master\_cluster.sh.
