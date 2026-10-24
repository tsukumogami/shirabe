# The check rollup is refused and protection requires a check no Actions job
# and no status reports (another app's check run): once every run finished it
# is unreadable, never a pass and never the worker's red.
# expect: error:board-read required-unreadable
# check: .source == "actions" and any(.required[]; .name == "codecov" and .result == "UNREADABLE")
include "lib";
.branch = protection(["validate", "codecov"])
| refuse_rollup
