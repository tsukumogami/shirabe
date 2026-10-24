# The check rollup is refused and the required status-API check is still
# pending: the board is pending, as from the checks.
# expect: pending required-pending
# check: .source == "actions"
include "lib";
.branch = protection(["validate", "ci/external"])
| .statuses = {total_count: 1, statuses: [{context: "ci/external", state: "pending"}]}
| refuse_rollup
