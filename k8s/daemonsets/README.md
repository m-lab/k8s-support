We have two kinds of daemonset we want to run on our nodes: Those that make the platform work ([core]) and those which cause an actual researcher's experiment to run ([experiments]).

[templates.json] contains helpful templates for the creation of new daemonsets of both kinds.

## Access Metrics and PProf Instrumentation

Our core services (tcpinfo, traceroute, pcap, pusher) are built with native
prometheus metrics and pprof instrumentation. Ordinarily, access to the
`/metrics` and `/debug/pprof` targets are only accessible to the private k8s
network.

Operators can access these targets by following these steps.

1. Identify a pod of interest. For example:

```sh
$ kubectl get pods -o wide | grep mlab1.lga0t | grep ndt
ndt-w6tr6   9/9       Running   0          29m     192.168.3.24    mlab1.lga0t
```

2. Forward a local port to the remote pod port for the container of interest.
   Check the latest port-to-container mapping in k8s/daemonsets/templates.jsonnet

```sh
$ kubectl port-forward pod/ndt-w6tr6 9993:9993
```

3. Access localhost:9993 using a browser, `go tool pprof <url>`, or other tool.

```sh
$ google-chrome http://localhost:9993/metrics
$ go tool pprof -top http://localhost:9993/debug/pprof/heap
$ lynx http://localhost:9993/debug/pprof/
```
