# A check an organisation's ruleset requires (the branch rules list it) whose
# only report is a check run from another app: with the rollup refused no job
# and no status answers it, so it is unreadable, never a pass.
# expect: error:board-read required-unreadable
# check: .source == "actions" and any(.required[]; .name == "org-policy" and .result == "UNREADABLE")
include "lib";
ctx(. + [check("org-policy"; "COMPLETED"; "FAILURE"; true) | .checkSuite.app.databaseId = 999])
| .rules = [{type: "required_status_checks", ruleset_source_type: "Organization",
             parameters: {required_status_checks: [{context: "org-policy", integration_id: 999}]}}]
| refuse_rollup
