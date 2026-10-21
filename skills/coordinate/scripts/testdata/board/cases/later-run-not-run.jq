# Run 101 failed, and the later run's job of the same name never started (no
# step at all): a job that never ran is no verdict on the code, so it doesn't
# supersede the failure.
# expect: unverified run-conclusion job-conclusion job-not-run
# check: .superseded == []
include "lib";
."jobs-101".jobs[0].conclusion = "failure" | .runs.workflow_runs[0].conclusion = "failure"
| .runs = runs(.runs.workflow_runs + [later(101; 103; "completed"; "failure"; "2026-10-21T07:02:00Z")])
| ."jobs-103" = jobs([job(1003; "Unit Tests"; "failure"; null; [])])
| ctx(map(if .name == "Unit Tests" then .conclusion = "FAILURE" else . end))
