# base.jq -- the passing board every case starts from: two runs at the head,
# each with one job that ran on a named runner with succeeded steps, the
# required check `validate` reported and green, a clean merge state, and the
# remote ref still at the head.
include "lib";
{
  snapshot: snapshot("CLEAN"; [check("Unit Tests"; "COMPLETED"; "SUCCESS"; false),
                              check("validate"; "COMPLETED"; "SUCCESS"; true)]),
  runs: runs([run(101; "completed"; "success"; 1), run(102; "completed"; "success"; 1)]),
  "jobs-101": jobs([job(1001; "Unit Tests"; "success"; "GitHub Actions 1"; [step("success"), step("success")])]),
  "jobs-102": jobs([job(1002; "validate"; "success"; "GitHub Actions 2"; [step("success")])]),
  branch: protection(["validate"]),
  rules: [],
  files: [{filename: "src/main.go", status: "modified"}],
  ref: {ref: "refs/heads/feat/x", object: {sha: H, type: "commit"}}
}
