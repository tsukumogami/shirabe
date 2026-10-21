# Run 101's "Unit Tests" failed and its "lint" passed; a later run of the
# workflow ran "Unit Tests" alone and passed. The failed job is superseded on
# its own, lint still counts, and the run's own failure is no reason.
# expect: verified
# check: .superseded == [{run: 101, job: 1001, name: "Unit Tests", by: 103}] and .counts.jobs == 3
include "lib";
."jobs-101" = jobs([job(1001; "Unit Tests"; "failure"; "GitHub Actions 1"; [step("failure")]),
                    job(1005; "lint"; "success"; "GitHub Actions 5"; [step("success")])])
| .runs.workflow_runs[0].conclusion = "failure"
| .runs = runs(.runs.workflow_runs + [later(101; 103; "completed"; "success"; "2026-10-21T07:02:00Z")])
| ."jobs-103" = jobs([job(1003; "Unit Tests"; "success"; "GitHub Actions 3"; [step("success")])])
