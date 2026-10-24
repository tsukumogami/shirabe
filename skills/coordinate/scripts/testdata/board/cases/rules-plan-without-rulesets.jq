# A private repository on a plan without rulesets answers the branch rules
# read with a 403 that says so. With the checks readable, that read failing is
# an unreadable required set, as it always was: nothing on the allowed path
# changes.
# expect: error:board-read required-set-unreadable
# check: .source == "checks"
include "lib";
.__rc.rules = 1 | .__err.rules = "gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)"
