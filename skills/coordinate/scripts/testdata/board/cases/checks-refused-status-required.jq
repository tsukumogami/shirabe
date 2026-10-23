# The check rollup is refused and protection requires a status-API check with
# no Actions job: the commit's status answers it, so the board verifies.
# expect: verified
# check: .source == "actions" and any(.required[]; .name == "ci/external" and .result == "SUCCESS")
include "lib";
.branch = protection(["validate", "ci/external"])
| .statuses = {total_count: 1, statuses: [{context: "ci/external", state: "success"}]}
| refuse_rollup
