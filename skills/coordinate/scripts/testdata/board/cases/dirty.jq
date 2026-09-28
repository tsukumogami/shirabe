# Merge state DIRTY.
# expect: unverified merge-state-dirty
# check: .merge_state == "DIRTY"
include "lib";
pr(.mergeStateStatus = "DIRTY")
