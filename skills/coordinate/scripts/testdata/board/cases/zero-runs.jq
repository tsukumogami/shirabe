# No run at the head: an empty board is not green.
# expect: unverified board-empty required-missing
# check: .counts.runs == 0
include "lib";
.runs = runs([]) | del(."jobs-101", ."jobs-102") | ctx([])
