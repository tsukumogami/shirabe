# Attempt 1 of run 101 failed and attempt 2 passed: the latest attempt's jobs verify, and the run is listed as superseded.
# expect: verified
# check: .superseded == [{run: 101, name: "wf-101", latest_attempt: 2, earlier: [1]}]
include "lib";
.runs.workflow_runs[0].run_attempt = 2
