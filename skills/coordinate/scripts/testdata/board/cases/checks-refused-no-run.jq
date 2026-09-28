# The check rollup is refused and no workflow ran at the head: empty, never green.
# expect: unverified board-empty required-missing
# check: .source == "actions" and .counts.runs == 0
include "lib";
refuse_rollup | .runs = runs([]) | del(."jobs-101", ."jobs-102")
