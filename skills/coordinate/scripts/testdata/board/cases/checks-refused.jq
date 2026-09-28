# The check rollup is refused: the checks are read from the Actions jobs, and the board says so.
# Green that way is actions-green, never verified: the required set may be short.
# expect: actions-green
# check: .source == "actions" and .pr_state == "OPEN" and .reasons == [] and .required == [{name: "validate", source: ["classic"], result: "SUCCESS"}] and any(.notes[]; .code == "checks-refused" and (.detail | contains("acme/widgets")))
include "lib";
refuse_rollup
