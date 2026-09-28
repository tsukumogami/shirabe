# The check rollup is refused and the required job failed: the Actions jobs show it.
# expect: unverified job-conclusion required-conclusion
# check: .source == "actions" and .required == [{name: "validate", source: ["classic"], result: "FAILURE"}]
include "lib";
refuse_rollup
| ."jobs-102" = jobs([job(1002; "validate"; "failure"; "GitHub Actions 2"; [step("failure")])])
