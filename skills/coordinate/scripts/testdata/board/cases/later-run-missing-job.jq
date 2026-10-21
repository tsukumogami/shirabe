# Run 101's "Unit Tests" and "lint" both failed; a later run of the workflow
# ran "Unit Tests" alone and passed. lint was never run again, so its failure
# stands, and so does the run's.
# expect: unverified run-conclusion job-conclusion
# check: .superseded == [{run: 101, job: 1001, name: "Unit Tests", by: 103}] and any(.reasons[]; .job == 1005) and all(.reasons[]; .job != 1001)
include "lib";
."jobs-101" = jobs([job(1001; "Unit Tests"; "failure"; "GitHub Actions 1"; [step("failure")]),
                    job(1005; "lint"; "failure"; "GitHub Actions 5"; [step("failure")])])
| .runs.workflow_runs[0].conclusion = "failure"
| .runs = runs(.runs.workflow_runs + [later(101; 103; "completed"; "success"; "2026-10-21T07:02:00Z")])
| ."jobs-103" = jobs([job(1003; "Unit Tests"; "success"; "GitHub Actions 3"; [step("success")])])
