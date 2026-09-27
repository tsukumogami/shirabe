# The required check concluded skipped, which fails it.
# expect: unverified required-conclusion
# check: .required == [{name: "validate", source: ["classic", "rollup"], result: "SKIPPED"}]
include "lib";
."jobs-102".jobs[0] = skipped_job(1002; "validate")
| ctx(map(if .name == "validate" then .conclusion = "SKIPPED" else . end))
