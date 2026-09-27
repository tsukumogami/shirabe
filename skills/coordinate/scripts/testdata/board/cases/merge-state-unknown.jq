# UNKNOWN twice (GitHub computes it lazily) is pending.
# expect: pending merge-state-unknown
include "lib";
.snapshot = {__seq: [(.snapshot | .data.repository.pullRequest.mergeStateStatus = "UNKNOWN"), (.snapshot | .data.repository.pullRequest.mergeStateStatus = "UNKNOWN")]}
