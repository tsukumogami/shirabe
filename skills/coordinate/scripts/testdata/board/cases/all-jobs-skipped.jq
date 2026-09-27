# Runs exist but every job in them was skipped: still an empty board.
# expect: unverified board-empty
# check: .counts.jobs_ran == 0
include "lib";
.branch = {protected: false} | ctx(map(.isRequired = false | .conclusion = "SKIPPED"))
| ."jobs-101".jobs = [skipped_job(1001; "Unit Tests")] | ."jobs-102".jobs = [skipped_job(1002; "validate")]
