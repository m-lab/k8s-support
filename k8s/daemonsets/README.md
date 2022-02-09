We have two kinds of daemonset we want to run on our nodes: Those that make the platform work ([core]) and those which cause an actual researcher's experiment to run ([experiments]).

[templates.json] contains helpful templates for the creation of new daemonsets of both kinds.

## Access Metrics and PProf Instrumentation

Our core services (tcpinfo, traceroute, pcap, pusher) are built with native
prometheus metrics and pprof instrumentation. Access to the `/metrics` and
`/debug/pprof` targets are only accessible to the private k8s network.

Operators can access these targets by following these steps.

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
```

Using the local listener created by `kubectl proxy`, make an API call to the
"proxy" operation for the pod we discovered earlier. The general URL pattern is
like:

```sh
/api/v1/namespaces/<namespace>/pods/<podname>:<port>/proxy/
```

For example:

```sh
$ curl http://localhost:8001/api/v1/namespaces/default/pods/ndt-w6tr6:9990/proxy/debug/pprof/
$ curl http://localhost:8001/api/v1/namespaces/default/pods/ndt-w6tr6:9995/proxy/metrics
$ go tool pprof -top http://localhost:8001/api/v1/namespaces/default/pods/ndt-w6tr6:9991/proxy/debug/pprof/heap
$ google-chrome http://localhost:8001/api/v1/namespaces/default/pods/ndt-w6tr6:9992/proxy/debug/pprof/
```

Each sidecar service (and ndt-server) listens on a particular port. At the time
of this writing the ports are as follows:

* 9990: ndt-server
* 9991: tcp-info
* 9992: traceroute-caller
* 9993: packet-headers
* 9994: uuid-annotator
* 9995: pusher

To access metrics or pprof data for a given service, simply modify the the URL
to specify `<podname>:<port>`. 

