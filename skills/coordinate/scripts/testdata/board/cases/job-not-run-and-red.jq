# One job never ran and another failed in its steps: the failure is the
# worker's, so the board is unverified.
# expect: unverified job-conclusion job-not-run
include "lib";
."jobs-101".jobs[0] |= (.conclusion = "failure" | .runner_name = null | .runner_id = null | .steps = [])
| .runs.workflow_runs[0].conclusion = "failure"
| ."jobs-102".jobs[0] |= (.conclusion = "failure" | .steps = [step("failure")])
| .runs.workflow_runs[1].conclusion = "failure"
| ctx(map(.conclusion = "FAILURE"))
| ."annotations-1001" = []
