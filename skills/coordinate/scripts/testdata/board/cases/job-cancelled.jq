# A job concluded cancelled.
# expect: unverified job-conclusion
include "lib";
."jobs-101".jobs[0].conclusion = "cancelled" | .runs.workflow_runs[0].conclusion = "cancelled"
