# Category D: FAIL

## Dependency graph (unchanged by this round's edits)

```
1 -> 2 -> 3 -> 4 -> 8
5 -> 6
5 -> 7
```

Still acyclic, still complete. The new finding below is a missing edge the
graph should have, exposed only now that Issue 6's ACs got concrete.

## New finding: Issue 6 and Issue 8 contend over the same file with no ordering edge between them (affected_issue_ids: [6, 8])

Real contradiction, not a false alarm. Issue 6's new AC requires: "The four
`leave` sites are byte-identical to their pre-change state, confirmed by
`git diff`." One of those four sites is
`docs/designs/current/DESIGN-roadmap-plan-standardization.md` — and Issue 8's
entire job is to append an amendment to that exact file. Issue 8 depends only
on Issue 4, Issue 6 depends only on Issue 5; nothing in the graph forces
Issue 6 to run (and have its git-diff check pass) before Issue 8 touches the
file. Nothing prevents it either — the two branches (1→2→3→4→8 and 5→6→…) are
declared independent, and the plan's own Implementation Sequence highlights
the critical path 1→2→3→4→8 as the spine to follow, which is precisely the
order that reaches Issue 8 without Issue 6 having run first.

If Issue 8 lands before Issue 6, Issue 6's git-diff check on this file fails
literally as written — the file will no longer be byte-identical to the
pre-plan baseline, even though Issue 6 itself never touches it and Issue 8's
addition is legitimate (an appended, clearly-separated section, per Issue 8's
own AC, that doesn't disturb the historical framing at line 577 the `leave`
designation is protecting). The design doc's own Decision E table already
anticipates the tension and resolves it in prose — the row for this file
reads "leave; amended separately by Decision 6's own amendment" — but that
resolution never made it into a graph edge or into a scoped AC.

Two independent corrections would each close this; either is sufficient:
- Add a declared dependency so Issue 8 also depends on Issue 6 (in addition
  to Issue 4), guaranteeing Issue 6's whole-file diff check runs against a
  still-pristine file.
- Rescope Issue 6's AC from whole-file byte-identity to the specific
  old-framing passage (line 577 and its immediate vicinity), so the check is
  robust regardless of which order 6 and 8 run in. This is the more durable
  fix since it makes the AC match what "leave" is actually protecting
  (the historical framing text, not the file's total byte content) — the
  other three `leave` sites (two untouched historical designs and the golden
  fixture) have no other issue in this plan touching them, so only this one
  site needs it.

Loop target 5 (Dependencies) — a missing edge / an AC whose truth depends on
an unenforced order, exactly the shape phase-4's ordering-error criteria
describe ("the dependency graph would allow parallel execution of issues
that share a critical state dependency").

## Confirmed unaffected: the `lifecycle.rs` overlap between Issues 3 and 6

Issue 6's Files list is unchanged (still `lifecycle.rs` and `transition.rs`
among the seven, comment-only per its own goal text) and the new Goal text
gives exact line numbers for its Rust edits — 52, 61, 764 in `lifecycle.rs`;
263, 469, 1960, 2011 in `transition.rs` — all pre-existing comment lines,
none of which is where Issue 3 appends the new `L09` check. The two issues
still land in disjoint regions of the same file with no AC cross-reference
either direction. Prior conclusion stands: same-file coincidence worth
sequencing consciously on one shared branch, not a missing graph edge.

## Everything else from prior passes still holds

Natural stopping point after Issue 3, and Issue 7 (riskiest) placed last
with nothing depending on it, are unaffected by this round's changes to
Issue 6.
