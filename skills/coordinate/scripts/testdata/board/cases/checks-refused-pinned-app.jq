# The check rollup is refused and protection pins `validate` to another app:
# the Actions job of that name can't answer it, so it is unreadable.
# expect: error:board-read required-unreadable
# check: .source == "actions" and any(.required[]; .name == "validate" and .result == "UNREADABLE")
include "lib";
.branch.protection.required_status_checks.checks = [{context: "validate", app_id: 999}]
| .branch.protection.required_status_checks.contexts = ["validate"]
| refuse_rollup
