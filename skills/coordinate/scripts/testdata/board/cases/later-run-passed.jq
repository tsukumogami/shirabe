# Run 101 failed; a later run of the same workflow at the same head and on the
# same event (a body edit re-ran it, shirabe#784) passed: the later run judges,
# so the board verifies, with the failed run listed as superseded.
# expect: verified
# check: .superseded == [{run: 101, name: "wf-101", by: 103}] and .counts.runs == 2
include "lib";
."jobs-101".jobs[0].conclusion = "failure" | .runs.workflow_runs[0].conclusion = "failure"
| .runs = runs(.runs.workflow_runs + [later(101; 103; "completed"; "success"; "2026-10-21T07:02:00Z")])
| ."jobs-103" = jobs([job(1003; "Unit Tests"; "success"; "GitHub Actions 3"; [step("success")])])
| ctx(map(if .name == "Unit Tests" then .conclusion = "FAILURE" | .databaseId = 1001 else . end)
      + [check_of(1003; "Unit Tests"; "COMPLETED"; "SUCCESS"; false)])
