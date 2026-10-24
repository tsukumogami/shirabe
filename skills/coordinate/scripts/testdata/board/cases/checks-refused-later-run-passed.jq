# The check rollup is refused, so the checks are the Actions jobs: the required
# check's run failed and a later run of its workflow passed, and the superseded
# job is no check.
# expect: verified
# check: .source == "actions" and .superseded == [{run: 102, name: "wf-102", by: 104}] and .required == [{name: "validate", source: ["classic"], result: "SUCCESS"}]
include "lib";
refuse_rollup
| ."jobs-102".jobs[0].conclusion = "failure" | .runs.workflow_runs[1].conclusion = "failure"
| .runs = runs(.runs.workflow_runs + [later(102; 104; "completed"; "success"; "2026-10-21T07:02:00Z")])
| ."jobs-104" = jobs([job(1004; "validate"; "success"; "GitHub Actions 4"; [step("success")])])
