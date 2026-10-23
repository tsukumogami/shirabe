# The check rollup is refused and a ruleset requires workflows: the branch
# rules don't name the checks that rule requires, so the board can't tell
# whether they passed, and it is unreadable rather than verified.
# expect: error:board-read required-unreadable
# check: .source == "actions" and any(.reasons[]; .code == "required-unreadable" and .name == "ruleset rule workflows")
include "lib";
.rules = [{type: "workflows", ruleset_source_type: "Organization", parameters: {workflows: [{path: ".github/workflows/policy.yml", repository_id: 1}]}}]
| refuse_rollup
