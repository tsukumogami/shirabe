# The check rollup is refused, a run is still going, and a required check has
# no job yet: pending while it runs, not unreadable yet.
# expect: pending required-missing
# check: .source == "actions" and any(.required[]; .name == "codecov" and .result == "MISSING")
include "lib";
.branch = protection(["validate", "codecov"])
| .runs.workflow_runs += [run(103; "in_progress"; null; 1)] | .runs.total_count = 3
| refuse_rollup
