# --sha --base with the commit statuses refused and a required status: it reads
# missing, never a pass, and the note names the refusal.
# expect: unverified required-missing
# args: --sha 0123456789abcdef0123456789abcdef01234567 --base main
# check: .source == "checks" and any(.notes[]; .code == "statuses-refused") and any(.required[]; .name == "ci/external" and .result == "MISSING")
include "lib";
del(.snapshot, .files, .ref)
| .branch = protection(["validate", "ci/external"])
| .checkruns = {total_count: 2, check_runs: [{name: "Unit Tests", status: "completed", conclusion: "success", app: {id: 15368}}, {name: "validate", status: "completed", conclusion: "success", app: {id: 15368}}]}
| .__rc.statuses = 1 | .__err.statuses = "gh: Resource not accessible by personal access token (HTTP 403)"
