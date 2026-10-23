# A private repository on a plan without rulesets answers the branch rules
# read with a 403 that says so: no ruleset applies, so protection alone is the
# required set and the board verifies.
# expect: verified
include "lib";
.__rc.rules = 1 | .__err.rules = "gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)"
