# A run that concluded startup_failure; its jobs aren't read.
# expect: unverified run-startup-failure
include "lib";
.runs.workflow_runs[1].conclusion = "startup_failure" | del(."jobs-102")
| ctx(map(select(.name != "validate")))
