# A queued run is pending; its jobs aren't read.
# expect: pending run-pending
include "lib";
.runs.workflow_runs[1] |= (.status = "queued" | .conclusion = null) | del(."jobs-102")
| ctx(map(if .name == "validate" then .status = "QUEUED" | .conclusion = null else . end))
