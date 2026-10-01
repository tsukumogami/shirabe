# A job that never ran beside a run still going: pending, so a person is asked
# only once nothing else is running.
# expect: pending run-pending job-not-run
include "lib";
."jobs-101".jobs[0] |= (.conclusion = "failure" | .runner_name = null | .runner_id = null | .steps = [])
| .runs.workflow_runs[0].conclusion = "failure"
| .runs.workflow_runs[1] |= (.status = "in_progress" | .conclusion = null)
| ."annotations-1001" = []
