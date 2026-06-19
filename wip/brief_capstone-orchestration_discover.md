# /brief Discovery: capstone-orchestration

## Problem Candidate

An author coordinating a multi-repo effort has no durable, tool-supported way to
express and track how the effort hangs together — which artifacts drive it, which
PRs implement it, and in what order they merge. The chain tools operate one repo at
a time, so the author re-states the entire coordination contract by hand every
session and maintains the cross-repo merge state manually. The effort's framing and
its running state live only in the author's head and a pasted prompt: nothing
persists, nothing is enforced, and mistakes (a missed merge dependency, a planning
artifact that never lands, an orphaned reference) are easy to make and hard to catch.

## Outcome Candidate

An author starts a coordinated multi-repo effort and the workflow carries the
coordination for them: the plan and its upstream framing live in one coordinating
place created up front, implementation work is grouped to one reviewable PR per repo,
the merge order is derived and tracked, and that coordinating record is the last
thing to merge — once, as the signal the whole effort is complete. The author
expresses the intent once (or sets it as a workspace default) instead of re-pasting
a contract, and trusts that the effort's framing and running state are persisted and
checkable rather than held in their head.

## Grounding Anchor

conversation only (the recurring manual operating-contract prompt), grounded by the
committed exploration artifacts on this branch (wip/explore_capstone-orchestration_*).

## Journey Sketch

- **Kickoff:** author begins a coordinated effort with capstone intent; the workflow
  creates the coordinating artifact and seeds it with the plan + upstream framing.
- **Implementation:** author works the plan; each repo's work becomes one PR; the
  coordinating record's PR-index and merge-order update as PRs open and merge.
- **Tracing:** a reviewer or future reader lands on the coordinating PR and sees the
  whole effort at a glance — plan, artifacts, per-repo PRs, merge order, done-state.
- **Completion:** every per-repo PR merged + the consume cascade run → the
  coordinating record merges last as the completion signal.

## Open Questions for Drafting

- Naming: surface as "capstone" in the artifact, or a more self-explanatory term for
  external readers? (defer exact naming to PRD/design)
- The exact split of which conventions are smart-defaults vs the one durable
  workspace preference is settled in exploration but the PRD owns the precise contract.
