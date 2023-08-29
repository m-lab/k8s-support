We have two kinds of daemonset we want to run on our nodes: Those that make the platform work ([core]) and those which cause an actual researcher's experiment to run ([experiments]).

[templates.json] contains helpful templates for the creation of new daemonsets of both kinds.

## Access Metrics and PProf Instrumentation

Our core services (tcp-info, traceroute-caller, packet-headers, uuid-annotator,
pusher) are built with native prometheus metrics and pprof instrumentation.
Access to the `/metrics` and `/debug/pprof` targets are only accessible to the
private k8s network.

Operators can access these targets by following these steps. The steps differ depending on whether the services are listening on the cluster's private network, or as part of the host network using localhost.

Each sidecar service (and measurement service) listens on a particular port. At the time
of this writing the ports are as follows:

* 9990: measurement service (e.g. ndt-server, msak, etc)
* 9991: tcp-info
* 9992: traceroute-caller
* 9993: packet-headers
* 9994: uuid-annotator
* 9995: pusher
* 9996: heartbeat
* 9997: jostler

### Private Network

Identify a pod of interest. For example:

```sh
$ kubectl get pods -l workload=ndt -o wide | grep mlab1-lga0t
ndt-w6tr6   13/13       Running   0          29m     192.168.3.24 mlab1-lga0t[...]
```

In one terminal, use kubectl to start a proxy to the control plane (API
cluster). By default `kubectl proxy` will create a local listener on port
8001. You can use the default or change the port to whatever you prefer.

```sh
$ kubectl proxy
Starting to serve on 127.0.0.1:8001
```

Using the local listener created by `kubectl proxy`, make an API call to the
"proxy" operation for the pod we discovered earlier. The general URL pattern is
like:

```sh
/api/v1/namespaces/<namespace>/pods/<podname>:<port>/proxy/
```

For example:

```sh
curl http://localhost:8001/api/v1/namespaces/default/pods/ndt-w6tr6:9990/proxy/debug/pprof/
curl http://localhost:8001/api/v1/namespaces/default/pods/ndt-w6tr6:9995/proxy/metrics
go tool pprof -top http://localhost:8001/api/v1/namespaces/default/pods/ndt-w6tr6:9991/proxy/debug/pprof/heap
google-chrome http://localhost:8001/api/v1/namespaces/default/pods/ndt-w6tr6:9992/proxy/debug/pprof/
```

To access metrics or pprof data for a given service, simply modify the URL
to specify `<podname>:<port>`.

### Host Network Localhost

Identify a pod of interest. For example:

```sh
$ kubectl get pods -l workload=ndt-virtual -o wide | grep mlab1-lax0t
ndt-virtual-46gnr 14/14 Running 0 2d2h 10.0.0.27 mlab1-lax0t...
```

In one terminal, use kubectl to port forward from your local system to the
remote system on localhost.

```sh
$ kubectl port-forward pod/ndt-virtual-5mlnd 9991:9991
Forwarding from 127.0.0.1:9991 -> 9991
Forwarding from [::1]:9991 -> 9991
```

Using localhost:9991 you can now access the remote services.

```sh
curl http://localhost:9991/debug/pprof/
curl http://localhost:9991/metrics/
go tool pprof -top http://localhost:9991/debug/pprof/heap
google-chrome http://localhost:9991/debug/pprof/
```

To access metrics or pprof data for another service, simply use an alternate
port for `kubectl port-forward`.

## Container Logs

By default we do not push any container logs to Google Cloud Logging with
Vector. Every experiment pod has the `vector.dev/exclude: true` label, which
causes Vector to ignore logs from any container in the pod. In almost every
case, container logs that exist in the cluster are good enough. The only case
where we might want to push container logs to GCP is one in which we need more
than a couple days worth of logs and need to use Cloud Logging expressions to
search the logs in some way. Other than that, the main difference is that logs
in the cluster will only live as long as the log size stays under some
threshold, whereas GCP will store them unconditionally for 30 days. To enable
pushing container logs for a pod to GCP, remove the aforementioned label from
the pod of interest.
