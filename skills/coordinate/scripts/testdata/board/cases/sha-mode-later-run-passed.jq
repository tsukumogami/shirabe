# --sha: the required check's run failed and a later run of its workflow
# passed; the commit's check runs carry both, and the superseded one (its id is
# its job's) doesn't answer for the required check.
# expect: verified
# args: --sha 0123456789abcdef0123456789abcdef01234567 --base main
# check: .superseded == [{run: 102, name: "wf-102", by: 104}] and .required == [{name: "validate", source: ["classic"], result: "SUCCESS"}]
include "lib";
del(.snapshot, .files, .ref)
| ."jobs-102".jobs[0].conclusion = "failure" | .runs.workflow_runs[1].conclusion = "failure"
| .runs = runs(.runs.workflow_runs + [later(102; 104; "completed"; "success"; "2026-10-21T07:02:00Z")])
| ."jobs-104" = jobs([job(1004; "validate"; "success"; "GitHub Actions 4"; [step("success")])])
| .checkruns = {total_count: 3, check_runs: [
    {id: 1001, name: "Unit Tests", status: "completed", conclusion: "success", app: {id: 15368}},
    {id: 1002, name: "validate", status: "completed", conclusion: "failure", app: {id: 15368}},
    {id: 1004, name: "validate", status: "completed", conclusion: "success", app: {id: 15368}}]}
| .statuses = {total_count: 0, statuses: []}
