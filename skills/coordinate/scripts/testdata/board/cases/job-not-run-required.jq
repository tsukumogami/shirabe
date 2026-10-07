# The required check is a job that never ran: required-not-run, not a
# required-conclusion, and the board is not run.
# expect: not-run job-not-run required-not-run
# check: .required == [{name: "validate", source: ["classic", "rollup"], result: "NOT_RUN"}] and ([.reasons[].code] | index("required-conclusion")) == null
include "lib";
."jobs-102".jobs[0] |= (.conclusion = "failure" | .runner_name = null | .runner_id = null | .steps = [])
| .runs.workflow_runs[1].conclusion = "failure"
| ctx(map(if .name == "validate" then .conclusion = "FAILURE" else . end))
| ."annotations-1002" = [{annotation_level: "failure", message: "The job was not started because recent account payments have failed or your spending limit needs to be increased."}]
