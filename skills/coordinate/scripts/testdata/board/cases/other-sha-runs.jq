# Runs exist, but only for another sha; they're ignored.
# expect: unverified board-empty
# check: .counts.runs == 0
include "lib";
.runs.workflow_runs |= map(.head_sha = OTHER) | del(."jobs-101", ."jobs-102") | ctx([])
