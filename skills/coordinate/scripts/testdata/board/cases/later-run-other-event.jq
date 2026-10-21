# Run 101 (pull_request) failed, and a later run of the same workflow on
# another event (push) passed: a different event is a different payload, so
# it doesn't supersede.
# expect: unverified run-conclusion job-conclusion
# check: .superseded == [] and any(.reasons[]; .run == 101)
include "lib";
."jobs-101".jobs[0].conclusion = "failure" | .runs.workflow_runs[0].conclusion = "failure"
| .runs = runs(.runs.workflow_runs + [later(101; 103; "completed"; "success"; "2026-10-21T07:02:00Z") | .event = "push"])
| ."jobs-103" = jobs([job(1003; "Unit Tests"; "success"; "GitHub Actions 3"; [step("success")])])
| ctx(map(if .name == "Unit Tests" then .conclusion = "FAILURE" else . end))
