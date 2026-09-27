# A job that isn't required and was skipped still verifies, and is listed.
# expect: verified
# check: .skipped == [{run: 101, job: 1003, name: "LLM Quality Gate"}] and .counts.jobs_ran == 2
include "lib";
."jobs-101".jobs += [skipped_job(1003; "LLM Quality Gate")] | ."jobs-101".total_count = 2
| ctx(. + [check("LLM Quality Gate"; "COMPLETED"; "SKIPPED"; false)])
