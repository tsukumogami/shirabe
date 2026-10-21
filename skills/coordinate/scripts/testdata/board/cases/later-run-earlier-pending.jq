# Run 101 is still going, and a later run of its workflow already passed: an
# earlier run that hasn't finished may run a job the later one doesn't, so it
# is never superseded and the board waits for it.
# expect: pending run-pending
# check: .superseded == [] and any(.reasons[]; .code == "run-pending" and .run == 101)
include "lib";
.runs.workflow_runs[0] |= (.status = "in_progress" | .conclusion = null) | del(."jobs-101")
| .runs = runs(.runs.workflow_runs + [later(101; 103; "completed"; "success"; "2026-10-21T07:02:00Z")])
| ."jobs-103" = jobs([job(1003; "Unit Tests"; "success"; "GitHub Actions 3"; [step("success")])])
| ctx(map(if .name == "Unit Tests" then .status = "IN_PROGRESS" | .conclusion = null else . end)
      + [check_of(1003; "Unit Tests"; "COMPLETED"; "SUCCESS"; false)])
