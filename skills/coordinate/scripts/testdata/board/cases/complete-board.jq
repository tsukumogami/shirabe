# A complete board: every job ran on a named runner with a succeeded step, and the required check is green.
# expect: verified
# check: .reasons == [] and .counts == {runs: 2, jobs: 2, jobs_ran: 2, required: 1} and .notes == [] and .merge_state == "CLEAN" and .required == [{name: "validate", source: ["classic", "rollup"], result: "SUCCESS"}]
include "lib";
.
