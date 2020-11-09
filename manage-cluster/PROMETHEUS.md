# Prometheus

## Resizing the Prometheus VM's disk

Prometheus uses a lot of disk space. As new metrics, recording rules, alerts,
etc. are added, the disk space requirements may go up, requiring someone to
resize the disk, adding more space. Prometheus is part of the platform
cluster, and is always scheduled to run on a dedicated GCE VM named
[prometheus-platform-cluster](https://console.cloud.google.com/compute/instancesDetail/zones/us-east1-b/instances/prometheus-platform-cluster?project=mlab-oti).
Resizing a VM's persistent disk in GCP is very easy, and the [Google
documentation](https://cloud.google.com/compute/docs/disks/regional-persistent-disk#resize_repd)
for how to do this is very straightforward. Once the disk has been resized in
the GCP console for the VM, you will need to resize the partition in the VM
itself. Again, [Google's
documentation](https://cloud.google.com/compute/docs/disks/add-persistent-disk#resize_partitions)
for how to do this is quite detailed and clear.
