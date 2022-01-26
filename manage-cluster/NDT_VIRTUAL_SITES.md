# NDT Virtual Sites

NDT virtual sites are sites that run only NDT in cloud environments (e.g., GCP, AWS,
etc.). Differing from their physical counterparts, virtual sites contain only
a single node (mlab1) with a single IPv4 address (assigned by the cloud provider).

**NOTE**: currently, the only supported cloud platform is Google Cloud
Platform (GCE).

**NOTE**: if you are creating a virtual site in mlab-staging or mlab-oti, and
want to be sure that the Locate Service does not send traffic to the site until
you are ready, then you should create a new issue in the
[ops-tracker](https://github.com/m-lab/ops-tracker/issues) Github repository to
track the site creation, and somewhere in the issue body, or in a subsequent
comment, add the following text anywhere, which will put the site into
maintenance mode until either the issue is closed or the site is explicity
removed from maintenance mode (e.g., "/site pdx0t del"). For example:

```sh
/site pdx0t
```

## Creating an NDT virtual node

Unlike physical sites, the machine (VM) for a virtual site must be created in
the cloud _before_ an entry in [siteinfo](https://github.com/m-lab/siteinfo/) is
created. This is because we don't know the IP address of the VM prior to its
creation, and this information is necessary to create the site in siteinfo.

In the same directory as this file there is a script named
`add_ndt_virtual_site.sh`. The script takes 3 arguments, in this order:
<project>, <site>, <zone>. Sites in the mlab-sandbox project must have a "t"
suffix as part of the name (e.g., abc0t, xyz2t), while sites in all other
projects should end in a "c" (e.g., abc0c, xyz2c). As with standard physical
sites, virtual sites should be named after the IATA code of the nearest
international airport. For example, for a virtual site in GCP zone us-west1-c
(Dalles, Oregon), the site code would "pdx" (Portland Internal Airport).
Following the example, to create a new NDT virtual site in GCP zone us-west1-c,
you would run:

```sh
./add_ndt_virtual_site.sh mlab-sandbox pdx0t us-west1-c
```

This will create the VM and join it to the mlab-sandbox platform cluster.

The name of the VM in GCP, for this example, will be:

`mlab1-pdx0t-mlab-sandbox-measurement-lab-org`

Determine the IPv4 address assigned to the VM:

```sh
gcloud compute addresses describe mlab1-pdx0t-mlab-sandbox-measurement-lab-org \
  --project mlab-sandbox --format 'value(address)'
```

## Adding the virtual site siteinfo

Once the virtual site is created and you know the IP address of the single VM,
you can proceed with adding the new virtual site to siteinfo. Adding a virtual
site to siteinfo is by and large the same as adding a typical physical site,
with the exception of the "annotations", "machines" and "network" fields. For a
virtual site the "type" annotation will be "virtual" (instead of "physical"),
the "machines" field will _not_ be additive to the default Jsonnet site config
(e.g., "machines:+"), but will instead overwrite the default config for machines
entirely (e.g, "machines:"). The IPv4 value will have a /32 on the end (not the
usual /26), since we are using a single IPv4 address, not an entire subnet.
Below is an example configuration, again following the pdx0t example:

```jsonnet
local sitesDefault = import 'sites/_default.jsonnet';

sitesDefault {
  name: 'pdx0t',
  annotations+: {
    type: 'virtual',
  },
  machines: {
    mlab1: {
      disk: 'sda',
      iface: 'ens4',
      model: 'gce',
      project: 'mlab-sandbox',
    },
  },
  network+: {
    ipv4+: {
      prefix: '35.247.89.22/32',
    },
    ipv6+: {
      prefix: null,
    },
  },
  transit+: {
    provider: 'Google LLC',
    uplink: '10g',
    asn: 'AS15169',
  },
  location+: {
    continent_code: 'NA',
    country_code: 'US',
    metro: 'pdx',
    city: 'Portland',
    state: 'OR',
    latitude: 45.5886,
    longitude: -122.5975,
  },
  lifecycle+: {
    created: '2022-01-14',
  },
}
```
