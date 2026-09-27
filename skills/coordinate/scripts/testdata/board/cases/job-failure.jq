# A job concluded failure.
# expect: unverified job-conclusion run-conclusion
include "lib";
."jobs-101".jobs[0].conclusion = "failure" | .runs.workflow_runs[0].conclusion = "failure"
| ctx(map(if .name == "Unit Tests" then .conclusion = "FAILURE" else . end))
