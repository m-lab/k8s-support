# General
A configuration file for every experiment deployed on our fleet.

Most experiments will be configured as DaemonSets that only run on nodes where
`mlab/type=physical`.

# Strict separation between experiment data and sidecar data
In order to maintain a strict separation between experiment data and sidecar
data, the experiment container should never mount the base experiment directory
/cache/data/<experiment>. An experiment should only mount its datatype
subdirectories of the base directory e.g., /cache/data/<experiment>/ndt5. In
this way, an experiment does not have visibility of any directory outside of
it's datatype directories and therefore cannot accidentally (or intentionally)
modify sidecar data.
