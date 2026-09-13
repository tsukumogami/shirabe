# Completeness Review: PRD-work-on-standalone-completeness

## Verdict

FAIL

## Per-criterion findings

**1. Required sections present and in order.** Pass. Status, Problem
Statement, Goals, User Stories, Requirements, Acceptance Criteria, Out of
Scope appear in canonical order (lines 27, 31, 80, 94, 119, 225, 272),
followed by the optional Decisions and Trade-offs and Known Limitations,
which is the correct placement for optional sections.

**2. BRIEF scope boundary served.** Five of the six IN items map cleanly to
requirements: cascade reachability incl. no-chain case -> R1-R5; prose
obligations becoming gated states -> R6-R10; multi-pr execution moving to
the plan-owning skill with routing surface moved -> R14-R18; a
child-non-finalization signal distinct from the shared-branch signal ->
R11-R12; every new obligation reachable by a child -> R10. The third IN
item — "Where the shared cascade machinery lives, given that both entry
points need it and only one owns it today" — has no requirement that
addresses it. R5 comes closest (both callers of "one script" must behave
identically on both failure shapes), which answers a behavioral-parity
question but never states whether the script's current ownership/location
changes, stays fixed, or is explicitly left to the design doc. Nothing in
Problem Statement, Requirements, or Decisions and Trade-offs says so much as
"this feature does not relocate the cascade machinery." A reader cannot tell
whether this was resolved, forgotten, or deliberately deferred.

All six OUT items appear in Out of Scope, each with the same framing the
BRIEF used (definition-of-done cannot-verify, staleness gate missing
script, terminal-tick context loss for pre-existing ticks, review-panel gate
visibility, naming fossils, merging the PR). This half is clean.

**3. BRIEF's three deferred Open Questions closed.** All three are
genuinely closed in Decisions and Trade-offs, each with a decision,
alternatives considered (including one on the record from the earlier
execute-skill split, cited and applied), and reasoning: (a) single-issue
skill refuses a multi-pr plan with a pointer; (b) a no-anchor run is a
pass-through, cascade never invoked, "done" unchanged; (c) the two
contradicted documents are superseded via one decision record rather than
edited in place. None of the three is merely mentioned — each has a real
decided/alternatives/why structure. This criterion passes.

**4. Requirements cover the goals.** Each Goals paragraph traces to a
requirement cluster (mergeable-PR-or-named-stop -> R1-R9; enforcement
altitude and child-reachability -> R6-R10; plan cadence and single entry
point -> R11-R18). No orphan goal. On the requirements-to-AC side, however,
**R21 ("Template authoring SHALL follow the repository's existing rules for
gates and default actions, including the constraints its own linter
imposes") has no corresponding Acceptance Criterion.** Every other
requirement (R1-R20, R22) is cited by at least one AC bullet; R21 is cited
by none. The format reference is explicit that Acceptance Criteria "are the
contract: if all criteria pass, the feature is complete" — a requirement
outside that contract is not verifiable as done.

**5. Gaps an implementer would have to invent.** Mostly well-contained: the
obligation classification table (R8), the exact anchor-detection check
(R2), and the new suppression signal's shape (R12) are properly left open
for design/plan, since R8-R12 impose the constraints that would let a
reviewer check the eventual choice. The one gap worth calling out beyond
items 2 and 4 above: R9 offers a live either/or ("brought within one
reference-hop... or recorded as deliberately optional") with no criterion
in the PRD for which branch is preferred, so two implementations that pick
opposite branches would both satisfy the letter of R9 and AC7 with no way
to say one contradicts the PRD's intent. That's a legitimate open branch
rather than a defect, but it is the widest fork left with no thumb on the
scale.

**6. Content boundaries.** File-path- and mechanism-level specificity
(`skills/work-on/SKILL.md`, `skills/work-on/koto-templates/work-on.md`,
"reference-hop", "dispatch loop") is consistent with this repository's own
precedent for skill/workflow PRDs (PRD-execute-skill.md names state files,
resume ladders, and specific gate mechanisms at the same altitude), so none
of that is a drift into design on its own. R22 ("The work SHALL be
reviewable as two pull requests... The order is a requirement, not a
preference") is the one requirement that reads as delivery/implementation
sequencing rather than product behavior — squarely the kind of question
`/plan` answers ("this is too big for one PR, split it up"). It is
defensible as a hard constraint on how downstream work must be structured
given the routing rewrite underneath it, but it sits closer to the design/
plan boundary than any other requirement in the document.

**7. Out of Scope honesty.** All seven exclusions (six from the BRIEF plus
the PRD's own execution-mode-enum exclusion under R20) are ones a reader
could plausibly assume were in scope, and each carries a reason. No
issue here.

## Required changes

1. Add a requirement (or explicit prose in Problem Statement / Decisions and
   Trade-offs) that closes the BRIEF's third in-scope item: where the
   cascade script/machinery lives once both entry points call it — even if
   the answer is "unchanged; only a new caller is added, and the concrete
   location is a design-time decision," say so on the record. As written,
   this scope item is not traceable to anything in the PRD.
2. Add an Acceptance Criterion for R21, or fold its verification into an
   existing one (e.g., the AC5 bullet or a new bullet next to AC17) so every
   requirement is covered by the "all criteria pass -> feature complete"
   contract.

## Observations

- R9's either/or leaves no signal for which branch (one-reference-hop-plus-
  evidence vs. explicitly-advisory) is preferred; not a failure, but worth a
  sentence of intent if the authors have one.
- R22's PR-sequencing requirement reads closer to a `/plan` decomposition
  concern than a product requirement; likely fine given the routing
  rewrite it protects against, but flagged for the jury's attention since it
  is the one requirement that specifies delivery mechanics rather than
  system behavior.
