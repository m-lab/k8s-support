# Prometheus

## Resizing the Prometheus VM's disk

Prometheus uses a lot of disk space. As new metrics, recording rules, alerts,
etc. are added, the disk space requirements may go up, requiring someone to
resize the disk, adding more space. Prometheus is part of the platform
cluster, and is always scheduled to run on a dedicated GCE VM named
[prometheus-platform-cluster](https://console.cloud.google.com/compute/instancesDetail/zones/us-east1-b/instances/prometheus-platform-cluster?project=mlab-oti).
The VM has a dedicated persistent disk (PD) which is only used for Prometheus
data. The PD is _not_ a boot disk. The disk should be exposed to the OS as
`/dev/sdb` and is mounted at `/mnt/local`. Resizing a PD attached to VM in
GCP is very easy, and the [Google
documentation](https://cloud.google.com/compute/docs/disks/regional-persistent-disk#resize_repd)
for how to do this is very straightforward. Once the PD has been resized in
the GCP console for the VM, you will need to SSH to the VM and resize the
filesystem in the VM itself. Again, [Google's
documentation](https://cloud.google.com/compute/docs/disks/add-persistent-disk#resize_partitions)
for how to do this is quite detailed and clear (i.e., resize2fs). All of this
can be done without interrupting the VM or any running processes.
