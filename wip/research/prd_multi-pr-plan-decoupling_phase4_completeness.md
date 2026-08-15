# Verdict: FAIL

## 1. Required sections present and ordered

Pass. Status (29), Problem Statement (33), Goals (79), User Stories (96),
Requirements (118), Acceptance Criteria (182), Out of Scope (217) all present
in canonical order. Optional Decisions and Trade-offs (240) and Known
Limitations (284) follow correctly. Requirements numbered R1-R19 consecutively.
Frontmatter `status: Draft` matches body `## Status` / `Draft`.

## 2. Upstream coverage

Fail, two gaps.

**a. Three-way tracking preference collapsed to two-way, silently.** BRIEF
Scope Boundary IN states: "A repository-level preference for how a multi-PR
plan's work is tracked -- GitHub issues, issues with a milestone, or neither
-- independent of how many pull requests are involved" (BRIEF line 145-147) --
three distinguishable values. PRD R5 only requires: "The work-tracking
preference SHALL distinguish, at minimum, filing GitHub issues from filing
none" -- a two-way split. No requirement, Out of Scope entry, or Decisions
entry addresses whether "issues with a milestone" is a separately selectable
value from plain issues. (The DESIGN doc later collapses this to a binary
under "On the milestone question," but that is a DESIGN-altitude call
resolving a WHAT-level scope item the PRD itself never named as in-scope,
deferred, or excluded.)

**b. Journey 2's departure-recording case is uncovered and appears to
conflict with R9.** BRIEF Journey "The team that reviews in small increments"
states: "A change that would be awkward to split is still planned as one pull
request when the author says so for this change, and the plan records that
this is a departure from the repository's stated preference" (BRIEF line
113-115). No PRD requirement or acceptance criterion exercises this. Worse,
R9 states the opposite categorically: "A PLAN whose execution_mode is
single-pr SHALL NOT be required to carry the field of R8" -- with no carve-out
for the case where the repo's stated delivery preference is atomic and a
single-PR plan departs from it. The Decisions entry "A single-PR plan records
nothing" addresses the general uniformity question (closing the BRIEF Open
Question) but its reasoning ("one pull request is the shape nobody asks
about") does not engage this narrower journey case, where the repo explicitly
prefers atomic delivery and the reader's open question is exactly why a
single-PR plan overrode that.

All other Scope Boundary IN items are covered (execution-mode
decision-separation via R8's branch-naming language; delivery-shape
preference via R1/R2; R8/R10 durable record; R13/R14 approval-gate and
task-extraction consequences). Journeys 1, 3, and 4 (sole maintainer,
issues-without-PRs team, auditing reviewer) are each exercised by a matching
user story and AC.

## 3. Brief Open Questions closed

Pass. All three land under Decisions and Trade-offs: "Two preferences, not
one" (setting count), "A single-PR plan records nothing" (single-PR record),
"The coordinated altitude is a follow-on, not part of this contract"
(coordinated-altitude record). Each states the question, the answer, and the
reasoning.

## 4. Consequences covered

Fail on one of three.

- Draft->Active approval gate re-key: covered, R13.
- `plan-to-tasks.sh` `#N` parsing dependency: covered, R14.
- Missing conditional-required-field mechanism in `FormatSpec`: **silently
  absent.** Confirmed via exploration artifacts (e.g.
  `wip/explore_multi-pr-plan-decoupling_decision_1_report.md:139`,
  `wip/design_multi-pr-plan-decoupling_summary.md:38`) that this is a real
  carried cost -- `FormatSpec`'s `required_fields` is unconditional, so R8's
  conditional requirement (required unless `single-pr`) has no schema-level
  home. Grepped the PRD for "FormatSpec" and "conditional": zero matches. Not
  named as a requirement, not in Out of Scope, not in Known Limitations. R19
  ("implemented on the validator's existing posture-class mechanism") gestures
  near this territory but never states the schema gap or how R8/R10 are meant
  to be checked given it.

## 5. Citation vs restatement

Pass. Problem Statement is self-contained and stated in full, as required.
Decisions and Trade-offs section cites the BRIEF by name for each closed
question rather than re-narrating it, and adds PRD-specific reasoning (R9,
R17, R18 cross-references) rather than repeating BRIEF prose. User Stories are
a required PRD section and appropriately transform BRIEF Journeys into "As a
/ I want / so that" form rather than restating them verbatim.

## 6. No solution smuggling

Fail, one requirement.

**R18** is fine (an explicit non-functional constraint on record format:
free text vs enumeration, with WHAT-level reasoning).

**R19** crosses the line: "The R10 check SHALL be implemented on the
validator's existing posture-class mechanism rather than as a new enforcement
subsystem." This names an internal implementation choice for the validator
(which mechanism to reuse vs. build) rather than an observable system
behavior. That is exactly the kind of decision the DESIGN should make and
justify with trade-offs -- the PRD should instead state the observable
constraint (e.g., that the check integrates with existing draft/ready
validation posture) without dictating that it reuses a specific named
internal mechanism over an alternative.

## Required Changes

1. Add a requirement (or an explicit Out of Scope / Decisions entry with
   reasoning) covering the "issues vs. issues-with-milestone vs. neither"
   three-way tracking distinction from the BRIEF's Scope Boundary, or narrow
   R5's language and record why the milestone axis collapses to the issues
   axis.
2. Add a requirement or AC covering Journey 2's departure-recording case, or
   add a Decisions and Trade-offs entry explicitly addressing why a single-PR
   plan that departs from a stated atomic preference is exempted from
   recording under R9 -- distinguishing that from the general uniformity
   question already closed.
3. Name the `FormatSpec` conditional-required-field gap: as a requirement
   (if closing it is in scope), in Out of Scope (if deferred), or in Known
   Limitations (if accepted as a permanent weakness of the R10 check).
4. Rewrite R19 to state the observable constraint rather than name the
   validator's internal mechanism, moving the "which mechanism" choice to the
   DESIGN doc.
