# The check rollup is refused and the required job never ran: the Actions
# jobs show it as not run, not as a failure.
# expect: not-run job-not-run required-not-run
# check: .source == "actions" and .required == [{name: "validate", source: ["classic"], result: "NOT_RUN"}]
include "lib";
refuse_rollup
| ."jobs-102" = jobs([job(1002; "validate"; "failure"; null; [])])
| .runs.workflow_runs[1].conclusion = "failure"
| ."annotations-1002" = [{message: "The job was not started because recent account payments have failed or your spending limit needs to be increased."}]
