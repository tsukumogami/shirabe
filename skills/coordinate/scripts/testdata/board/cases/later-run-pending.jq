# Run 101 failed and a later run of its workflow is still going: the failure is
# superseded, but the board reads pending until the later run finishes, never
# verified.
# expect: pending run-pending
# check: .superseded == [{run: 101, name: "wf-101", by: 103}] and all(.reasons[]; .code != "run-conclusion" and .code != "job-conclusion")
include "lib";
."jobs-101".jobs[0].conclusion = "failure" | .runs.workflow_runs[0].conclusion = "failure"
| .runs = runs(.runs.workflow_runs + [later(101; 103; "in_progress"; null; "2026-10-21T07:02:00Z")])
| ctx(map(if .name == "Unit Tests" then .conclusion = "FAILURE" | .databaseId = 1001 else . end)
      + [check_of(1003; "Unit Tests"; "IN_PROGRESS"; null; false)])
