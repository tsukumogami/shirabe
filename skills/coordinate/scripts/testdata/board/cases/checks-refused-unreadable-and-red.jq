# The check rollup is refused, a required check no job or status answers, and
# a job failed: the red job is the worker's and reads first, unverified, before
# the unreadable check is put to a person.
# expect: unverified job-conclusion required-unreadable
# check: .source == "actions" and any(.required[]; .name == "codecov" and .result == "UNREADABLE")
include "lib";
.branch = protection(["validate", "codecov"])
| ."jobs-101".jobs[0].conclusion = "failure" | .runs.workflow_runs[0].conclusion = "failure"
| refuse_rollup
