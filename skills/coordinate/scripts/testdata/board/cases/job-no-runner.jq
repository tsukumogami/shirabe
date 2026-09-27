# A job that concluded success with no runner.
# expect: unverified job-no-runner
include "lib";
."jobs-101".jobs[0] |= (.runner_name = null | .runner_id = null)
