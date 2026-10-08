# The rollup read fails for a reason other than a refusal: no fallback, the board is an error.
# expect: error:board-read read-failed
# check: .source == "checks"
include "lib";
.__rc.rollup = 1 | .__err.rollup = "gh: Server Error (HTTP 502)"
