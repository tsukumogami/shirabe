# A required status context still PENDING.
# expect: pending required-pending
include "lib";
.rules = [{type: "required_status_checks", parameters: {required_status_checks: [{context: "ci/legacy"}]}}]
| ctx(. + [status_ctx("ci/legacy"; "PENDING"; true)])
