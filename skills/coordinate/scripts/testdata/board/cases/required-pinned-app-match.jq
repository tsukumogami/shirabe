# Protection pins validate to the app that reported it.
# expect: verified
include "lib";
.branch.protection.required_status_checks = {contexts: [], checks: [{context: "validate", app_id: 15368}]}
