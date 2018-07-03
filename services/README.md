These are all the things we run that aren't experiments that nonetheless should
be running on the platform.  Primarily, these should be our internal support
scripts and monitoring systems, as well as some tools which are run for all
experiments:

* [node-exporter](https://github.com/prometheus/node_exporter) to monitor node health
* `disco` to monitor (and archive) switch health
* [tcp-info](https://github.com/m-lab/tcp-info) to collect statistics (and packet headers) on all connections
* `paris-traceroute` to run reverse-traceroute after every connection
