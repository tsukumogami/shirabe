# Run 101 failed, and a later run of another workflow at the same head ran a job
# of the same name and passed: runs of different workflows never supersede
# each other.
# expect: unverified run-conclusion job-conclusion
# check: .superseded == [] and any(.reasons[]; .run == 101)
include "lib";
."jobs-101".jobs[0].conclusion = "failure" | .runs.workflow_runs[0].conclusion = "failure"
| .runs = runs(.runs.workflow_runs + [later(999; 103; "completed"; "success"; "2026-10-21T07:02:00Z")])
| ."jobs-103" = jobs([job(1003; "Unit Tests"; "success"; "GitHub Actions 3"; [step("success")])])
| ctx(map(if .name == "Unit Tests" then .conclusion = "FAILURE" else . end))
