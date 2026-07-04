# Clarity Verdict: PRD-session-work-summary

## Verdict

PASS

## Assessment

**1. Problem Statement (states a problem, who, why now).** Passes. The Problem
Statement (lines 34-53) describes a gap — PR links scroll away and no surface
recovers them — not a solution. Affected parties are named twice and precisely:
"developers running long or PR-dense sessions, and developers who dispatch
background workers" (lines 40-41). "Why now" is carried by the exploration
findings about the untrustworthy session-list PR chip (lines 46-50). No solution
leaks into the statement; the closing "paradox" framing (lines 52-53) restates
the problem rather than proposing a fix.

**2. Goals are outcomes, not implementation.** Passes. All five goals (lines
57-67) are stated as user-observable outcomes ("a developer can see the full
set...", "the view is trustworthy", "works in single-repo and multi-repo
workspaces"). No mechanism is named. The verb choices stay at the WHAT altitude.

**3. Requirements unambiguous / no vague terms.** Mostly passes. R1-R14 each
resolve to a single reasonable reading. Referents that could have been vague are
defined in place: "absence threshold" is qualified "configurable" (R7) and
"degrade gracefully" is immediately pinned to "producing a clearly-marked
best-effort summary rather than failing the turn" (R13). Two soft spots, neither
producing two-way ambiguity:
  - R13 "a handful of PRs" and "under normal conditions" (lines 141-143) are
    loose, but the parenthetical "sub-second" gives a testable anchor.
  - R15 (lines 147-149) is the weakest: "bounded and small relative to the
    session's context budget" and "favor signal over volume" carry no measurable
    threshold. The PRD format guide asks NFRs to have measurable thresholds
    "where possible." This reads as soft rather than ambiguous (a reader will not
    interpret it two contradictory ways), so it is advisory, not blocking.

**4. Behavior/WHAT vs implementation/HOW.** Passes cleanly, and this is the
PRD's strongest dimension. No requirement names a hook, systemMessage, script,
or file. R1 says "standardized summary block with a fixed marker line" (the
observable artifact) not how it is injected. R10 says "the agent SHALL be kept
aware... restored after the session's context is compacted" — the behavior, with
the mechanism deferred. The one place a mechanism appears (the hook-matcher
defect) is correctly quarantined in Out of Scope (lines 190-192) as prerequisite
context, not a requirement.

**5. Consistency.** Passes with one terminology nit. No requirement contradicts
another; the emission rules (R6 emits on change, R7 emits on return, R8
suppresses when unchanged) compose without conflict, and Out of Scope's "no
timed digests" (lines 182-183) matches R7's "SHALL NOT be emitted on a fixed
timer." "tracked PR set" is used consistently (R6, R8, R10, criteria).
Nit: R1 introduces "tracked work item" (line 94) as the per-entry noun, but every
other reference — R2 onward — uses "PR"/"entry." The lone "work item" reads as a
stray synonym; recommend "tracked PR" for uniformity.

**6. Writing style / AI-tells.** Passes on vocabulary — none of the banned words
(robust, leverage, comprehensive, holistic, facilitate, seamless, tier) appear.
Contractions are used and sentence length varies. The one persistent tell is
em-dash density, which a prior BRIEF review already flagged: the Problem
Statement alone carries three em-dashes across lines 34-38 (one sentence uses two
as a parenthetical: "again — to review, to share, to check CI — the only
recourse"), plus more at lines 12 and 48, and R1/R2 continue the pattern. It
does not impair clarity, so it stays advisory, but it has survived one review
cycle and should be thinned.

**7. Requirements vs Acceptance Criteria distinction.** Mostly clean. Most
criteria verify rather than restate: AC "After the configured absence threshold,
the next exchange leads with a refreshed summary; below the threshold, ordinary
exchanges do not" (lines 158-159) is a testable observation of R7, not a copy.
One criterion drifts toward restatement: AC1 (lines 153-155) re-enumerates R2's
full field list (repo, PR number, state, CI/review status, title, full URL)
rather than asserting a verifiable condition over them. It is defensible as "this
shape is produced and reused across all three emission paths," but it leans on
R2's wording. Advisory only.

## Required Changes (if FAIL)

None — verdict is PASS.

## Advisory Notes

- **R15**: add a measurable or at least falsifiable bound for the per-emission
  context cost, or explicitly note the threshold is design-determined. As written
  it is the one requirement a tester cannot pass/fail objectively.
- **R1 terminology**: replace "tracked work item" with "tracked PR" so the
  per-entry noun matches the rest of the document.
- **Em-dash density**: reduce, especially the double-em-dash parentheticals in
  the Problem Statement (lines 37-38) and R1 (line 95). This was flagged in the
  prior BRIEF review and persists.
- **AC1**: consider tightening to verify reuse-across-emission-paths without
  re-listing every R2 field.
