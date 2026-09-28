# --sha --base with the check runs refused and the required job failed.
# expect: unverified job-conclusion required-conclusion
# args: --sha 0123456789abcdef0123456789abcdef01234567 --base main
# check: .source == "actions"
include "lib";
del(.snapshot, .files, .ref)
| .statuses = {total_count: 0, statuses: []}
| refuse_checkruns
| ."jobs-102" = jobs([job(1002; "validate"; "failure"; "GitHub Actions 2"; [step("failure")])])
