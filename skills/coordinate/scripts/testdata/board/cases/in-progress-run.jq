# An in-progress run is pending.
# expect: pending run-pending
include "lib";
.runs.workflow_runs[0] |= (.status = "in_progress" | .conclusion = null) | del(."jobs-101")
