# A run that concluded skipped is listed, and its jobs aren't read.
# expect: verified
# check: .skipped == [{run: 102, name: "wf-102"}]
include "lib";
.runs.workflow_runs[1].conclusion = "skipped" | del(."jobs-102") | .branch = {protected: false}
| ctx(map(select(.name != "validate")))
