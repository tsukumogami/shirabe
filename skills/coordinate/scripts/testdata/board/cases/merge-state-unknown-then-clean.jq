# UNKNOWN, then CLEAN on the re-read, verifies.
# expect: verified
# check: .merge_state == "CLEAN"
include "lib";
.snapshot = {__seq: [(.snapshot.data.repository.pullRequest.mergeStateStatus = "UNKNOWN"), .snapshot]}
