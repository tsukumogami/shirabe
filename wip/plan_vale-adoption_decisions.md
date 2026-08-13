# Plan Decisions: vale-adoption

Recorded under `--auto`, per the decision protocol.

## Decomposition strategy: horizontal

The design describes components with stable interfaces and a hard ordering:
the rule source must parse before anything reads it, the scoper must exist
before a frequency rule can measure scoped prose, and the dispatch change must
land before instruction files can be checked. Walking skeleton is for cases
where integration risk is the unknown; here the integration is a function call
inside one crate and the risk is concentrated in the scoper's correctness,
which a thin end-to-end slice would not surface any earlier.

The design's own six phases are already a horizontal decomposition and each was
constructed to leave the tree green. The plan adopts them rather than
re-cutting the work.

## Execution mode: single-pr

Confirmed rather than assumed. Both escape conditions were tested.

**Condition 1, a hard constraint forcing multiple PRs.** None. Every change is
in one repository, one crate plus its skill files. No cross-repo landing order,
no workflow that must reach main before it can be invoked, no merge gate
between phases.

**Condition 2, each PR independently useful.** This is the closer call and it
fails on inspection. Phases 1 through 3 are not independently useful to a
reader: phase 1 moves the rule list into YAML with no behavior change at all
(deliberately, it is behavior-preserving), and phase 2's scoper has no consumer
until phase 3 wires the gate. A reader receiving phase 1 alone receives a
refactor. The value lands when instruction files start being checked and the
frequency rule fires, which is phases 3 and 5.

The workspace preference reinforces it: CLAUDE.md sets
`## PR Grouping Policy: coarsest-legal`, one PR per repository unless a
recorded trigger splits it. No trigger fired.

**The reviewability ceiling is the risk accepted.** Six phases in one PR is
large, and the phases touch the crate's central dispatch signature and three
frozen golden fixtures. The mitigation is that the phases are ordered and each
is independently reviewable as a commit, so the PR reads as a sequence rather
than a pile. If the diff proves unreviewable in practice, the recorded trigger
for splitting is the ceiling itself, and the seam is between phase 3 and phase
4: everything through the gate change is one deliverable, and vocabulary plus
the frequency rule is the second.

## Complexity classification

Phase 3 is `critical`: it changes the signature of the crate's central entry
point, moves three frozen parity fixtures, and can turn shirabe's own CI red if
the frontmatter fallback is wrong. Phases 1, 2, 4, and 5 are `testable`. Phase
6 is `simple` but wide.
