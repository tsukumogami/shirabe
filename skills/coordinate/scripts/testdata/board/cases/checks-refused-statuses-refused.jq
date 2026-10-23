# The check rollup and the commit's statuses are both refused, and protection
# requires a status-API check: nothing can answer it, so it is unreadable, and
# a note names the refusal.
# expect: error:board-read required-unreadable
# check: .source == "actions" and any(.notes[]; .code == "statuses-refused") and any(.required[]; .name == "ci/external" and .result == "UNREADABLE")
include "lib";
.branch = protection(["validate", "ci/external"])
| .__rc.statuses = 1 | .__err.statuses = "gh: Resource not accessible by personal access token (HTTP 403)"
| refuse_rollup
