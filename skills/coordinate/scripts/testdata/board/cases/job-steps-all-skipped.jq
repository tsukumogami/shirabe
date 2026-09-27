# A job whose steps were all skipped.
# expect: unverified job-no-succeeded-step
# check: [.reasons[] | select(.code == "job-no-succeeded-step") | .detail] == ["0 of 2 steps succeeded"]
include "lib";
."jobs-101".jobs[0].steps = [step("skipped"), step("skipped")]
