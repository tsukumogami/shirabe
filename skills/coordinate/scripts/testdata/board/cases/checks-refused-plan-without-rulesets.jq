# The check rollup is refused, and the repository is private on a plan without
# rulesets: the branch rules read answers a 403 saying so. Read from the
# Actions jobs, no ruleset applies, so protection alone is the required set and
# the board verifies.
# expect: verified
# check: .source == "actions"
include "lib";
.__rc.rules = 1 | .__err.rules = "gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)"
| refuse_rollup
