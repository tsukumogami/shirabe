# Completeness review: Issue 1 (reconcile-report.sh) -- round 2

Scope: `skills/coordinate/scripts/reconcile-report.sh`,
`skills/coordinate/scripts/reconcile-report_test.sh`. Commits reviewed:
`git log -3` shows 08ac6e3 (workflow scaffolding, out of scope here),
745ff37 (round-1 diff, already reviewed), and 8aa14a6 ("fix(coordinate):
carry every re-check through the reconcile report"), the round-2 fix this
review covers via `git diff HEAD~1`. Acceptance criteria: Issue 1 in
`docs/plans/PLAN-coordinate-reconcile.md`; requirements R4, R12, R16-R21 in
`docs/prds/PRD-coordinate-reconcile.md`.

`bash skills/coordinate/scripts/reconcile-report_test.sh` was run: 48
assertions, all pass.

## Round-1 blocking findings: both closed

**Finding 1 (leg fact dropped).** 8aa14a6 adds `leg_of` and
`grade_of(fact("leg"))`, a `leg` field on `holdings[]`, renders it beside
the pull request state ("leg resolved: merged (measured)"), and adds it to
`not_verified` when the read fails. Tested both ways: a successful leg
alongside a `merge_state`-bearing pull request read
(`the holding line carries the merge state and the leg's result beside the
pull request state`), and a failed leg read (`an unreadable leg is not
verified`, asserting `.holdings[0].leg == null` and the not-verified entry).
This satisfies R12 and the rendering half of Issue 3's AC that Issue 1 owns.
Verified by re-reading the diff and rerunning the suite.

**Finding 2 (docs/-path boundary untested).** 8aa14a6 changes the `files`
fact from a precomputed `outside_docs` bool to a raw `paths[]` array and
adds `outside_docs` as a jq function in `reconcile-report.sh` itself,
classifying by `startswith("docs/")`. New fixtures cover exactly the
AC's named cases: `src/x` changed -> flagged; only `docs/x/y.md` and
`docs/plans/PLAN-a.md` changed -> not flagged; `docsx/a` -> flagged (proving
the classifier requires the trailing slash, not just the `docs` substring);
and an executing-phase holding with `src/x` -> never flagged. All four
pass. This is the exact boundary check Issue 1's AC asked for and it now
has a committed home and fixtures.

## Blocking findings (round 2)

None. Every Issue 1 acceptance-criteria bullet has both an implementation
and a test that would catch a wrong one, and the two round-1 blocking
findings are closed with tests that exercise the literal cases the AC
named.

## Advisory findings (non-blocking)

### D. `nowhere_else[].grade` is implemented but has no test at all (new in round 2)

8aa14a6 adds a `grade` field to `nowhere_else[]`
(`grade: (if ok($inv) then "measured" else "not verified" end)`) and
renders it (`"- \(.topic): \(.why); \(.inventory) (\(.grade))."`), closing
part of round 1's Advisory A (the header's grade rubric had claimed more
than the schema implemented). But no assertion anywhere -- not the
combined `== grades ==` jq check (which covers holdings, waiting,
deferrals, changes, side_effects but omits `nowhere_else`), not the
line-bound fixture, not the "not found" fixture -- checks this field's
value. I confirmed by hand that it computes correctly today (a holding
with an `ok` inventory and unpushed work renders `unpushed work; repo: file
x.go (measured)`; a missed-worker holding with a `not_verified` inventory
renders `... (not verified)`), but a regression here (inverted condition,
hardcoded string, wrong key) would pass the full suite. Not blocking:
Issue 1's literal AC5 text names only three grade categories to test
(state/branch -> measured, confirmed merge/board -> verified by reading,
phase/next -> inferred); `nowhere_else`'s inventory grade sits outside that
literal list, same as round 1's Advisory A did for the whole field before
it existed. Fix: add `nowhere_else` to the `== grades ==` assertion (e.g.
`and (.nowhere_else | all(.grade == "measured" or .grade == "not verified"))`)
plus one case distinguishing the two.

### E. `merge_state` (new, R4) has no dedicated test for its null-suppression path

R4 requires merge state to "appear in the holding's line," and 8aa14a6
adds `merge_state` to `holdings[]`, rendered only when non-null
(`", merge state \(.merge_state)"`) with no grade of its own -- it rides on
`.grade.state` since it comes from the same `pr` fact atomically. I
verified by hand that a failed pull request read correctly suppresses it
(`(): executing; not verified (not verified). Next: ...` with no "merge
state" clause), so the behavior is right, but no fixture exercises that
suppression or a mismatched-state case. Not blocking: this bundging
decision is defensible (state and merge_state share one read and one
success/failure outcome) and the field isn't named in Issue 1's literal AC
list. Fix: fold a `merge_state`-present-but-pr-unreadable case into the
existing "grades follow the read" test group.

### B (carried from round 1, unchanged). Header's grade rubric documentation test stays weak

The AC1 test is still a 3-substring grep over the header comment; not
re-examined in depth since 8aa14a6 didn't touch that test, only the header
text and schema it checks against. Still can't be verified against scripts
that don't exist yet (`reconcile-check.sh`, `reconcile-read.sh`,
`reconcile-pass.sh`). Non-blocking, as in round 1.

### C (carried from round 1, unchanged). Job-id leak coverage is still thin

`board.detail` is still free text copied straight into the rendered
"fails: ..." line with no fixture simulating a run id inside it. Untouched
by 8aa14a6. Non-blocking until Issue 2 defines what `detail` contains.

## Evidence-claim spot check (round 2 commit message)

- "Grades now follow whether the read succeeded" -- true and tested
  (`grades follow the read` section: failed pr -> `not verified` state and
  null board grade).
- "the holding line carries the pull request's merge state and a bound
  leg's result" -- true and tested (`merge state and legs` section).
- "a deferral whose disposal check failed lands under Not verified" --
  true and tested (`deferrals` section: d3 with `status: not_verified`
  lands in `not_verified`, not in `deferrals[]` either disposed or not).
- "the docs/ classification ... happens here from the paths themselves" --
  true and tested (see Finding 2 above).
- "phase values are matched whole: an unrecognised one is marked executing
  and listed as not verified" -- true and tested (`phase":"scoped"` case).

## Conclusion

Both round-1 blocking findings are closed with real implementation and
fixtures that would catch a regression. No new blocking gaps found: every
Issue 1 AC bullet has both code and a test exercising its literal cases.
Two new non-blocking test-coverage gaps surfaced in the round-2 diff itself
(`nowhere_else.grade` untested; `merge_state`'s null-suppression path
untested), alongside the two carried-over advisories from round 1.
