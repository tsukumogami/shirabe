# A ruleset requires ci-summary, which never reported, and every run has finished.
# expect: unverified required-missing
# check: .required | map(select(.name == "ci-summary")) == [{name: "ci-summary", source: ["ruleset"], result: "MISSING"}]
include "lib";
.rules = [{type: "required_status_checks", parameters: {required_status_checks: [{context: "ci-summary"}]}}]
