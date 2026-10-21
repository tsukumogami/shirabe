# Run 102 failed at startup (no job read), and a later run of its workflow
# passed: the startup failure is superseded whole.
# expect: verified
# check: .superseded == [{run: 102, name: "wf-102", by: 104}]
include "lib";
.runs.workflow_runs[1].conclusion = "startup_failure" | del(."jobs-102")
| .runs = runs(.runs.workflow_runs + [later(102; 104; "completed"; "success"; "2026-10-21T07:02:00Z")])
| ."jobs-104" = jobs([job(1004; "validate"; "success"; "GitHub Actions 4"; [step("success")])])
