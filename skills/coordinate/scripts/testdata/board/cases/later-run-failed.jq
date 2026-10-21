# Run 101 passed, and a later run of the same workflow at the same head failed:
# an earlier green never hides a later red.
# expect: unverified run-conclusion job-conclusion
# check: .superseded == [{run: 101, name: "wf-101", by: 103}] and all(.reasons[]; .run == 103)
include "lib";
.runs = runs(.runs.workflow_runs + [later(101; 103; "completed"; "failure"; "2026-10-21T07:02:00Z")])
| ."jobs-103" = jobs([job(1003; "Unit Tests"; "failure"; "GitHub Actions 3"; [step("failure")])])
| ctx(map(if .name == "Unit Tests" then .databaseId = 1001 else . end)
      + [check_of(1003; "Unit Tests"; "COMPLETED"; "FAILURE"; false)])
