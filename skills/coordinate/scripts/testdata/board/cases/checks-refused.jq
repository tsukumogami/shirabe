# The check rollup is refused: the checks are read from the Actions jobs, and the board says so.
# expect: verified
# check: .source == "actions" and .pr_state == "OPEN" and .reasons == [] and .required == [{name: "validate", source: ["classic"], result: "SUCCESS"}] and any(.notes[]; .code == "checks-refused")
include "lib";
refuse_rollup
