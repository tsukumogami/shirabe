# The check rollup is refused and the run holding the required job is still going.
# expect: pending run-pending required-missing
# check: .source == "actions"
include "lib";
refuse_rollup | .runs = runs([run(101; "completed"; "success"; 1), run(102; "in_progress"; null; 1)]) | del(."jobs-102")
