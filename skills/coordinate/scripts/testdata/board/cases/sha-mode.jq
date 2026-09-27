# --sha --base: no pull request; the rollup is the commit's check runs and statuses.
# expect: verified
# args: --sha 0123456789abcdef0123456789abcdef01234567 --base main
# check: .head == H and .merge_state == null and .required == [{name: "validate", source: ["classic"], result: "SUCCESS"}]
include "lib";
del(.snapshot, .files, .ref)
| .checkruns = {total_count: 2, check_runs: [{name: "Unit Tests", status: "completed", conclusion: "success", app: {id: 15368}}, {name: "validate", status: "completed", conclusion: "success", app: {id: 15368}}]}
| .statuses = {total_count: 0, statuses: []}
