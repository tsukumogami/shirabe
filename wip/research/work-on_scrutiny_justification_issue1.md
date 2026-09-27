# Justification review: coordinate-reconcile Issue 1 (reconcile-report.sh) -- round 2

Reviewed: `git show HEAD` (commit 8aa14a6, "fix(coordinate): carry every
re-check through the reconcile report"), against `docs/plans/PLAN-coordinate-reconcile.md`
Issue 1's acceptance criteria, `docs/designs/DESIGN-coordinate-reconcile.md`,
and `docs/prds/PRD-coordinate-reconcile.md`. Round 1's findings are in this
same file's prior revision (see git history); this pass re-checks whether B1
closed and whether the fix commit introduced anything new that needs
justifying.

## Round 1 blocking finding: resolved

**B1 (phase matched by an unexplained 4-letter prefix)** is closed. `phase_of`
now compares the row's `phase` value whole and case-insensitively against the
literal strings `"scoping"` and `"scoping-ahead"` (else `"executing"`), falls
back to entry point/mode only when `phase` is empty, and any other non-empty
value is treated as `"executing"` *and* surfaced under "Not verified" with
"unrecognised phase value; marked executing" (`phase_known`, the
`not_verified` bullet at line 239-240). The header comment now states exactly
which strings are recognized (lines 73-81). A new fixture (`"scoped"`) proves
a near-miss doesn't silently pass, and `"Scoping-Ahead"` proves the
case-fold is deliberate. This is exactly the remedy round 1 asked for: either
pin the literal values with a documented, bounded assumption and a
near-miss test, or match exactly -- the commit did the former, precisely.
Ran `reconcile-report_test.sh` directly: 48/48 pass, including all the new
phase, grade, merge-state/leg, and deferral-status cases.

## Blocking findings (round 2)

None found.

## New territory in this commit, checked for justification

### The docs/ classification moved from the files re-check into the report function

The `files` fact used to carry a precomputed `outside_docs` boolean (implying
`reconcile-check.sh`, Issue 2, did the `docs/`-prefix comparison); this commit
changes it to carry raw `paths[]`, and `reconcile-report.sh` now does the
`startswith("docs/")` comparison itself (`def outside_docs`, line 128; header
comment "classified here, see phase below", lines 40-42, 79-81). This is a
real split change from what round 1 read out of DESIGN Decision 2's
Implementation Approach ("files (the scoping-ahead contradiction)" listed
under `reconcile-check.sh`) and the Decision Outcome table's "Reported as"
column ("consistent, or flagged as contradicting its mark").

It is, however, well grounded elsewhere: PRD R17 states the phase mark *and*
the outside-docs contradiction as one rule ("A holding marked scoping ahead
whose live pull request changes any path outside `docs/` is flagged as
contradicting its mark"), and DESIGN Decision 2's own Chosen text assigns
`reconcile-report.sh` the job of carrying "phase, next-line, waiting and
grading rules (R16 to R19)" -- R17 is in that range. Read that way, the
Decision Outcome table's "Reported as" column describes the final report
output, not which script computes it, and "files (the scoping-ahead
contradiction)" in the Implementation Approach can be read as naming what the
files subcommand is *for* rather than asserting it does the comparison.
Issue 2's own AC text ("returns renamed and removed files by both paths")
already matches a raw-paths contract, so this doesn't create a conflict
Issue 2 would need to un-do. The change also directly satisfies Issue 1's own
AC line word for word: this commit's tests now include exactly the three
fixtures the AC names (`src/x` flagged, `docs/x/y.md` not, `docsx/a` not
inside `docs/`), closing round 1's A2 finding by fixing the gap rather than
just documenting around it.

Net: defensible and grounded in the PRD text that actually governs this rule,
not a silent guess -- but the DESIGN doc's Implementation Approach step 2 and
Decision Outcome table were not touched to reflect the new split, so a future
reader comparing only those two spots to the code would still be confused
about which script owns the comparison. Advisory, not blocking (see A1
below).

## Advisory findings

### A1 (was A2 in round 1, now a documentation-lag note, not a gap)

DESIGN's Implementation Approach step 2 ("files (the scoping-ahead
contradiction)" under `reconcile-check.sh`) and the Decision Outcome table's
"Reported as" column for the files re-check read as if the classification
happens in Issue 2. It now happens in Issue 1's `reconcile-report.sh`,
correctly per PRD R17 and Decision 2's "phase...rules (R16 to R19)" framing,
but the DESIGN text wasn't updated to say so. Recommend a one-line edit to
Decision 2's Implementation Approach ("files: fetches and returns the pull
request's changed paths; the docs/ comparison itself is R17, in
`reconcile-report.sh`") so a reader of the design doesn't have to reconstruct
this from the PRD.

### A2 (was A1 in round 1): "same run" design wording still not reconciled

Unchanged from round 1 and still open: DESIGN Decision 3 says the rendering
is "derived from the JSON by the same run, so the two never disagree," but
the script (unchanged in this respect) exposes `json`/`md` as two
invocations, and its own header says the pass "calls this twice... so the two
forms always agree" -- a different mechanism (purity/determinism) than "the
same run." Still non-blocking: the design's actual goal holds, and the
script documents its own reasoning; the wording mismatch just wasn't touched
by this fix commit. Worth folding into whatever documentation pass happens at
Issue 5/6 or a design addendum.

### A3 (was round-1 A3): resolved

Round 1 flagged that the header listed a deferral's disposal as graded
"verified by reading" while the output schema carried no `grade` field for
deferrals. This commit adds `grade: "verified by reading"` to every
undisposed deferral entry (line 231) and a `status`/`reason` pair for
deferrals whose disposal check itself failed (routed to `not_verified`
instead, lines 241-242). The header and the code now agree. Closed.

### A4 (new, minor): the new leg-disposition enumeration may be incomplete

The header now documents `leg` as "disposition (open|resolved|abandoned)"
(line 46). Elsewhere in this codebase, the same request-leg/koto vocabulary
is documented with four values: "disposition (open, resolved, abandoned,
missing)" (`docs/designs/current/DESIGN-scope-then-execute.md:876`). Nothing
in `reconcile-report.sh` branches on the specific disposition string --
`leg_of` (line 140-142) just concatenates whatever value it's given with the
result -- so an omitted "missing" value causes no functional bug today, only
a documentation gap versus a sibling design's enumeration of what looks like
the same underlying concept. Worth a glance when Issue 3 implements the
actual `koto request get` read, to confirm whether "missing" is a case
reconcile needs to represent (e.g., a request id that was never created).

### A5 (new, cosmetic): a refused holding with an unrecognized phase would double up in "Not verified"

`not_verified` is assembled as an unconditional concatenation of several
`select()` passes (lines 234-244): one for `.refused != null` and a separate
one for `phase_known | not`. A holding that is both refused and carries a
garbage `phase` value would produce two "Not verified" bullets. This is an
edge case with no fixture exercising it, doesn't affect correctness of any
graded claim, and refused rows are unlikely to also have meaningful phase
noise given the refusal reasons in scope. Not worth blocking on; flagging
only in case future fixtures should dedupe by topic.

## Checked and found adequately justified (no finding)

- **The CI workflow's scope** -- unchanged since round 1, still consistent
  with the repo's per-feature-area workflow convention and the plan's
  `single-pr` execution mode.
- **New `merge_state` and `leg` fields on `holdings[]`** -- both are named
  explicitly in DESIGN's Decision Outcome table ("state, draft flag, head
  sha, merge state" for the pull request row; "disposition and result...
  shown beside the GitHub state" for the leg row) and Issue 1's own AC1
  ("every field the other scripts produce or read"), so carrying them in the
  schema now, ahead of Issues 2/3 actually populating the facts, is
  consistent with the plan's "build the schema first" decomposition
  rationale.
- **Grades now following whether the read succeeded** (`grade.state`,
  `grade.board`, `grade.leg` each turning `null`/"not verified" on failure or
  absence, instead of round 1's unconditional "measured"/"verified by
  reading") -- this is a correctness fix squarely inside R19 ("Every claim is
  graded" -- with the corollary that a claim never read carries no
  measured/verified grade), not a new deviation.

## Summary

0 blocking findings. Round 1's blocking finding (B1, the phase-prefix match)
is fully resolved, matching the fix the round-1 review itself proposed, and
verified by a passing test run (48/48). Round 1's A3 (grade/deferral
documentation mismatch) is also resolved. One round-1 advisory (the
DESIGN's "same run" wording) remains open and unaddressed by this commit,
which is fine since it was never blocking. This commit's one substantive
architectural change -- moving the `docs/`-prefix classification from the
files re-check into the pure report function -- is a legitimate, PRD-grounded
correction (R17 assigns the rule to the report; Decision 2 assigns R17 to
`reconcile-report.sh`) that finally exercises Issue 1's own AC fixtures
verbatim, but leaves DESIGN's Implementation Approach and Decision Outcome
table wording stale; recommend a one-line design touch-up, not a blocker.
Two new minor/cosmetic advisories (leg-disposition enumeration possibly
missing a fourth value; a theoretical double "Not verified" entry) round out
the list.
