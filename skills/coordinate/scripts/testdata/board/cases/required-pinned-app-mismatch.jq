# Protection pins validate to another app, so a check run of that name from this app doesn't satisfy it.
# expect: unverified required-missing
include "lib";
.branch.protection.required_status_checks = {contexts: [], checks: [{context: "validate", app_id: 999}]} | ctx(map(.isRequired = false))
