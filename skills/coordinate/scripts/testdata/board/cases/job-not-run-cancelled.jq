# A job cancelled before any step ran, with no annotation: not run, and the
# reason says no step ran.
# expect: not-run job-not-run
# check: [.reasons[] | {code, detail}] == [{code: "job-not-run", detail: "no step ran (cancelled)"}]
include "lib";
."jobs-101".jobs[0] |= (.conclusion = "cancelled" | .runner_name = null | .runner_id = null | .steps = [])
| .runs.workflow_runs[0].conclusion = "cancelled"
| ."annotations-1001" = []
