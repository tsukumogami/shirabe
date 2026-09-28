# A check only the rollup's isRequired names (an organisation's required
# workflow, say, that protection and the branch rules don't list) whose job
# never ran. With the rollup refused it is invisible, not missing, so the board
# must not verify: it is actions-green, which nothing lands on.
# expect: actions-green
# check: .source == "actions" and ([.required[].name] | index("org-policy") == null)
include "lib";
ctx(. + [check("org-policy"; "COMPLETED"; "FAILURE"; true)])
| refuse_rollup
