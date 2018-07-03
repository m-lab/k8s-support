All setup scripts that run on a node.  These scripts are referenced as ePoxy
actions in an epoxy setup script in http://github.com/m-lab/epoxy-images ,
specifically [`stage3post.json`](https://github.com/m-lab/epoxy-images/blob/dev/actions/stage3_coreos/stage3post.json).

The `shim.sh` file exists to aid in the debugging of CNI plugins.  It will
likely be turned on in production for a while, but eventually the kubelet on the
node should be set up to use the files in `/usr/cni/bin` instead of
`/opt/shimcni/bin`.

It is my hope that we can figure out a way to make `setup_k8s.sh` eventually be
only the last three lines, and that a better `/etc` can become easily shipped as
part of the epoxy-served image.
