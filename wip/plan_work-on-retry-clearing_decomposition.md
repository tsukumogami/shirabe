# /plan decomposition: work-on-retry-clearing

- `input_type`: design
- Source: `docs/designs/DESIGN-work-on-retry-clearing.md` (Accepted)
- Visibility: Public. Scope: Tactical.
- Milestone: work-on retry clearing

## Strategy: horizontal

The design's components have clear boundaries and one is a prerequisite for the
rest: the mechanism has to exist in the shipped files before a harness that
*extracts the shipped text* can be written against it, and before CI can run
that harness. There is no integration risk to surface early -- the mechanism was
already driven end to end against real koto during the decision -- so a walking
skeleton would buy nothing a horizontal split does not.

## Execution mode: single-pr

Default, and nothing forces the escape. All work lands in one repository; no
cross-repo landing order, no workflow that must reach main before it can be
invoked, no merge gate between steps. The rejected `koto context remove`
alternative is exactly what *would* have forced `coordinated` mode, and the
design records why it lost.

The design also makes atomicity a correctness property rather than a preference:
converting the gates without the clearing block is fail-open, silently
reproducing the defect through a different gate type. Single-pr guarantees the
halves land together whatever order the issues are worked in.

<!-- decision:start id="value-confirmation" status="confirmed" -->
**Value confirmation (3.5a).** Single-pr, so the unit under test is the one PR,
and it clears the bar: it closes issue #304 with the instruction repaired, the
guarantee enforced by the state machine, and a regression test standing behind
both. No sub-unit needs to be independently useful, because none of them ships
alone.
<!-- decision:end -->

## Issues

**1 -- the mechanism, and every place the contract is stated.** The gate
conversion and the clearing block are one issue because the design proved they
cannot land apart. The prose that describes the contract travels with them:
splitting the panel-orchestration summary into its own issue would leave a
reader meeting a corrected mechanism through a stale summary for however long
the two issues sit apart.

**2 -- the harness.** Depends on 1, because it extracts the shipped text rather
than a copy of it; there is nothing to extract until 1 lands.

**3 -- CI wiring.** Depends on 2: `check-bash-floor.sh`'s own self-test asserts
every registered script exists, so registering a suite whose script is not there
yet fails.

**4 -- evals.** Depends on 1. The contract they assert against is what 1
changes.

## Complexity

Issue 1 is `critical`: it changes a state machine's advance conditions, and a
mistake is a workflow that either traps every run or silently passes stale
verdicts. Issues 2 and 3 are `testable`. Issue 4 is `testable` -- the eval run
has a pass/fail outcome to report.

All four are `code`. The files are markdown and YAML rather than Go or Rust, but
`docs` in `/work-on`'s sense skips the scrutiny, review, and QA panels, and this
is behavioural change to the workflow contract those panels exist to check. The
recursion is worth naming: classifying this work `docs` would route it around
the very phases it repairs.
