# A job GitHub refused to start for an account billing block: it completed
# failure with no step and no runner, and its check run says why. It is no
# verdict on the code (shirabe#564): not run, with the annotation as reason.
# expect: not-run job-not-run
# check: [.reasons[] | {code, detail}] == [{code: "job-not-run", detail: "The job was not started because recent account payments have failed or your spending limit needs to be increased."}]
include "lib";
."jobs-101".jobs[0] |= (.conclusion = "failure" | .runner_name = null | .runner_id = null | .steps = [])
| .runs.workflow_runs[0].conclusion = "failure"
| ctx(map(if .name == "Unit Tests" then .conclusion = "FAILURE" else . end))
| ."annotations-1001" = [{annotation_level: "failure", message: "The job was not started because recent account payments have failed or your spending limit needs to be increased."}]
