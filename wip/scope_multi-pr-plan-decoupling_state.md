```yaml
topic: multi-pr-plan-decoupling
chain_started: 2026-08-15T19:45:00Z
last_updated: 2026-08-15T20:45:00Z
phase_pointer: phase-4
exit: full-run
exit_artifacts:
  - docs/plans/PLAN-multi-pr-plan-decoupling.md
  - docs/designs/DESIGN-multi-pr-plan-decoupling.md
  - docs/prds/PRD-multi-pr-plan-decoupling.md
visibility: Public
planned_chain:
  - brief
  - prd
  - design
  - plan
chain_skipped: []
chain_ran:
  - name: brief
    started_at: 2026-08-15T19:58:00Z
  - name: prd
    started_at: 2026-08-15T20:12:00Z
  - name: design
    started_at: 2026-08-15T20:30:00Z
  - name: plan
    started_at: 2026-08-15T20:50:00Z
consolidation_judgments:
  - hop: brief->prd
    stage: judgment
    carry_check:
      Problem Statement: {target: Problem Statement, carried: true}
      User Outcome:      {target: Goals, carried: true}
      User Journeys:     {target: User Stories, carried: true}
      Scope Boundary:    {target: Out of Scope + Requirements, carried: true}
    verdict: absorb
    absorbed: docs/briefs/BRIEF-multi-pr-plan-decoupling.md
    into: docs/prds/PRD-multi-pr-plan-decoupling.md
  - hop: prd->design
    stage: judgment
    verdict: keep
    finding: >-
      The PRD holds two things the DESIGN does not and a contribution section
      could not carry. First, twenty numbered requirements that the DESIGN
      cites by number throughout -- R12, R13, R14 and others appear in the
      DESIGN's own prose, so a fold would leave those citations pointing at
      nothing unless the section reproduced the set, which is a rewrite rather
      than a distillation. Second, the acceptance criteria, which the DESIGN
      carries none of and needs none of, but which are the testable contract
      the downstream PLAN decomposes against. The adequacy test fails on its
      second clause: a reader could not follow the DESIGN's own argument
      without the document the fold would delete.
plan_execution_mode: single-pr
worktree_rebases:
  - phase: brief
    upstream_commits: [83d29e1, 778913e, b8b20eb, e227d7a]
    impact: informational
  - phase: plan
    upstream_commits: []
    impact: none
child_snapshots:
  brief:
    status: Draft
    content_hash: f6d6abeea9a20fd68ec9f480f14a4b8d2fbeb2e8
    captured_at: 2026-08-15T20:10:00Z
  prd:
    status: In Progress
    content_hash: ce492b083475315da6944ab3eceea2d0a83dd530
    captured_at: 2026-08-15T20:20:00Z
  design:
    status: Accepted
    content_hash: 8aeb7b7810afc5acc98242a8b6727c6f7d0b23ff
    captured_at: 2026-08-15T20:45:00Z
```

## Phase 0 Notes

Slug validated as provided against `^[a-z0-9-]+$`: passes.
`shirabe slug-prefix-detect multi-pr-plan-decoupling --docs-root docs` returned
`no-prevailing-prefix`, so no recommendation surfaced.

Visibility read from `CLAUDE.md:6` (`## Repo Visibility: Public`).

No `--upstream` supplied, so `consumed_upstream:` is absent per invariant I-5.

No stale `parent_orchestration:` block found (no prior state file for this topic).

**Coordination intent: absent.** Resolved deliberately rather than by the
header rule. shirabe's own `CLAUDE.md` carries both `## PR Grouping Policy:`
(line 46) and `## Reviewability Ceiling:` (line 59), which by the letter of
`/scope`'s resolution stack signals coordinated defaults. This effort is
entirely within the `shirabe` repository, so the multi-repo coordination
contract has nothing to coordinate: creating a coordination PR up front would
produce an unmergeable node with a single-repo merge order. Recorded here rather
than silently, because it is a finding this chain's own subject matter bears on
directly -- see Phase 1 notes.

## Phase 1 Notes

### Discovery

| Canonical path | State |
|---|---|
| `docs/briefs/BRIEF-multi-pr-plan-decoupling.md` | absent |
| `docs/prds/PRD-multi-pr-plan-decoupling.md` | absent |
| `docs/designs/DESIGN-multi-pr-plan-decoupling.md` | present, `status: Proposed` |
| `docs/designs/current/DESIGN-multi-pr-plan-decoupling.md` | absent |
| `docs/plans/PLAN-multi-pr-plan-decoupling.md` | absent |

`Proposed` is not among `/design`'s settled statuses (Accepted, Planned,
Current), so re-entry protection does not hold `/design` back. The document is
the `/explore` handoff skeleton produced earlier in this session; `/design` will
author against it rather than around it.

### Framing shift (R4)

No. The DESIGN on disk was written from this exploration's own findings within
the same session, and its problem statement is the framing the chain is about to
elaborate. Nothing has moved since.

### R6 shape-predicate verdicts

- **P1 (architectural-alternatives count) -- fires.** The exploration closed the
  principle question and deliberately left implementation choices open: what the
  two headers are named, the structural check that keeps a free-text
  `split_rationale` from degrading to a non-emptiness test, the
  conditional-required-field mechanism `FormatSpec` lacks, the third source-var
  scheme for issueless multi-pr in `plan-to-tasks.sh`, the `/work-on M<N>`
  substitute, and whether the reviewability ceiling gets a concrete value or is
  named as deferred. Each names multiple acceptable implementations.
- **P2 (new-component references) -- does not fire.** Every component named
  already exists in the repo: `crates/shirabe-validate`, `skills/plan`,
  `skills/work-on`, `plan-to-tasks.sh`, and the CLAUDE.md convention-header
  channel with its `resolve_claude_md_header` walker. No new binary, service,
  library, or runtime substrate.
- **P3 (Complex classification) -- fires.** The work amends a numbered workflow
  principle cited by name from skill surfaces, amends a prior design's decision,
  and must distinguish itself from a prior rejection of an adjacent shape.

Roster shape for `/design`: P1 fires, P2 does-not-fire, P3 fires.

### Chain proposal

Emitted; the author's standing instruction to run the full workflow is taken as
**Proceed**. No Adjust or Bail selected.
