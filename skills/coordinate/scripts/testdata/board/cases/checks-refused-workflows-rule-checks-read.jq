# A ruleset requires workflows, and the checks can be read: the rollup names
# those checks, so the rule itself adds nothing and the board verifies.
# expect: verified
# check: .source == "checks"
include "lib";
.rules = [{type: "workflows", ruleset_source_type: "Organization", parameters: {workflows: [{path: ".github/workflows/policy.yml", repository_id: 1}]}}]
