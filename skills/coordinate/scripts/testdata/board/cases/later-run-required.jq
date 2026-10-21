# The required check's run failed and a later run of its workflow passed, and
# the rollup still carries both check runs: the superseded one's check run
# (its id is its job's) doesn't answer for the required check.
# expect: verified
# check: .superseded == [{run: 102, name: "wf-102", by: 104}] and .required == [{name: "validate", source: ["classic", "rollup"], result: "SUCCESS"}]
include "lib";
."jobs-102".jobs[0].conclusion = "failure" | .runs.workflow_runs[1].conclusion = "failure"
| .runs = runs(.runs.workflow_runs + [later(102; 104; "completed"; "success"; "2026-10-21T07:02:00Z")])
| ."jobs-104" = jobs([job(1004; "validate"; "success"; "GitHub Actions 4"; [step("success")])])
| ctx(map(if .name == "validate" then .conclusion = "FAILURE" | .databaseId = 1002 else . end)
      + [check_of(1004; "validate"; "COMPLETED"; "SUCCESS"; true)])
