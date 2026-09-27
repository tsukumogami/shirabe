# --sha --base with the required check never reported.
# expect: unverified required-missing
# args: --sha 0123456789abcdef0123456789abcdef01234567 --base main
include "lib";
del(.snapshot, .files, .ref)
| .checkruns = {total_count: 1, check_runs: [{name: "Unit Tests", status: "completed", conclusion: "success", app: {id: 15368}}]}
| .statuses = {total_count: 0, statuses: []}
