# The check rollup is refused: the checks are read from the Actions jobs and
# the commit's statuses, the board says so, and green that way is verified.
# expect: verified
# check: .source == "actions" and .pr_state == "OPEN" and .reasons == [] and .required == [{name: "validate", source: ["classic"], result: "SUCCESS"}] and any(.notes[]; .code == "checks-refused" and (.detail | contains("acme/widgets")))
include "lib";
refuse_rollup
