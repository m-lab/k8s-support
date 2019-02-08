# Deployment

See the kube-state-metrics README for the most current deployment notes.
https://github.com/kubernetes/kube-state-metrics/blob/master/README.md

kube-state-metrics must run from a cloud node.

If initial deployment fails for permissions, it may be necessary to create a
role binding for your user. This also works for the GCE service account.

```
kubectl create clusterrolebinding cluster-admin-binding \
   --clusterrole=cluster-admin \
   --user=$(gcloud info --format='value(config.account)')
```
