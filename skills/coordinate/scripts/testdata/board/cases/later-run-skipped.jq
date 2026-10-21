# Run 101 failed, and the later run of its workflow was skipped: a skipped run
# tested nothing, so the failure stands.
# expect: unverified run-conclusion job-conclusion
# check: .superseded == [] and any(.reasons[]; .run == 101)
include "lib";
."jobs-101".jobs[0].conclusion = "failure" | .runs.workflow_runs[0].conclusion = "failure"
| .runs = runs(.runs.workflow_runs + [later(101; 103; "completed"; "skipped"; "2026-10-21T07:02:00Z")])
| ctx(map(if .name == "Unit Tests" then .conclusion = "FAILURE" else . end))
