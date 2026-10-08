# The annotations read fails: the job is still not run; only the reason
# loses GitHub's wording.
# expect: not-run job-not-run
# check: [.reasons[] | {code, detail}] == [{code: "job-not-run", detail: "no step ran (failure); GitHub's reason was not read"}]
include "lib";
."jobs-101".jobs[0] |= (.conclusion = "failure" | .runner_name = null | .runner_id = null | .steps = [])
| .runs.workflow_runs[0].conclusion = "failure"
| .__rc["annotations-1001"] = 1 | .__err["annotations-1001"] = "gh: Not Found (HTTP 404)"
