# The check rollup is refused and the required status-API check failed: the
# commit's status says so, and the board is unverified, as from the checks.
# expect: unverified required-conclusion
# check: .source == "actions" and any(.required[]; .name == "ci/external" and .result == "FAILURE")
include "lib";
.branch = protection(["validate", "ci/external"])
| .statuses = {total_count: 1, statuses: [{context: "ci/external", state: "failure"}]}
| refuse_rollup
