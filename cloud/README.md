All setup and startup scripts for cloud and cloud networking.

The scripts need to be run from this directory.

To set up a cloud master in sandbox, run
```bash
./setup_cloud_k8s_master.sh mlab-sandbox
```

To set up a cloud master in staging, run
```bash
./setup_cloud_k8s_master.sh mlab-staging
```

To set up a cloud master in production, run
```bash
./setup_cloud_k8s_master.sh mlab-oti
```

# Master node setup

We use `kubeadm` to set everything up.  It's alpha, but it works pretty well.

All the kubernetes configs for the master are stored under [../network/](../network/).
