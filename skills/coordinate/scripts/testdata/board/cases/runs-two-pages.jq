# Runs served on two pages, as --paginate prints them.
# expect: verified
# check: .counts.runs == 2
include "lib";
.runs = {__pages: [{total_count: 2, workflow_runs: [.runs.workflow_runs[0]]}, {total_count: 2, workflow_runs: [.runs.workflow_runs[1]]}]}
