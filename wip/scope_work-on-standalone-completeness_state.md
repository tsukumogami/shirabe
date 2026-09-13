---
topic: work-on-standalone-completeness
session: scope-work-on-standalone-completeness
visibility: Public
chain_started: 2026-09-13T00:00:00Z
last_updated: 2026-09-13T00:00:00Z
phase_pointer: phase-2
exit: UNSET
exit_artifacts: []
planned_chain:
  - brief
  - prd
  - design
  - plan
chain_skipped: []
chain_ran:
  - child: brief
    started_at: 2026-09-13T00:00:00Z
child_snapshots:
  brief:
    status: Accepted
    content_hash: 55bc4d5432c769175a1590548b7cec9c4d14b5b3
    captured_at: 2026-09-13T00:00:00Z
worktree_rebases:
  - phase: brief
    upstream_commits: [7cd13d1]
    impact: informational
    rebased_at: 2026-09-13T00:00:00Z
    notes: >-
      PR #353 changed skills/execute/koto-templates/execute.md (56 lines) and
      skills/execute/scripts/run-cascade.sh (206 lines), both cited by this
      chain. Re-verified after rebase: execute.md:706 still the run-cascade
      invocation, :640 still pr_finalization's do-not-mark-ready, :305 still the
      materialize_children default_template; skills/work-on/ still has exactly
      one cascade/lifecycle mention (SKILL.md:183), zero --draft, and one
      Fixes # (references/phases/phase-6-pr.md:35). No fact the chain committed
      to was altered. The commit strengthens this chain's no-chain-skip-path
      requirement rather than contradicting it - it fixed the case of a PLAN
      with no resolvable upstream, which is the thin-chain shape the design hop
      has to handle.
---

# /scope state: work-on-standalone-completeness

Setup established. Slug validated against `^[a-z0-9-]+$` as provided.
Visibility read from `CLAUDE.md` (`## Repo Visibility: Public`). No
`--upstream` supplied and no ROADMAP exists in this repo, so
`consumed_upstream:` is absent. No stale `parent_orchestration:` block was
present at session start.

Entered from an `/explore` handoff at
`wip/scope_work-on-standalone-completeness_handoff.md`.

## Phase 1 discovery

Entered via the `/explore` handoff (Slot 7), so the cold-start projection is
suppressed and the framing-shift question was put as a confirmation of the
answer the handoff carries.

**Framing-shift answer: yes, the framing shifted.** Confirmed from the handoff.
The tracking issue frames the problem as five capabilities living in the wrong
skill; the exploration established from the code that two of those are not gaps
at all, and that the remainder is one missing capability plus a difference in
enforcement altitude. The acceptance criteria in the tracking issue rest on the
superseded framing.

**Child-doc globs:** no artifact exists at any canonical path for this topic, so
no child is held back by re-entry protection and `child_snapshots:` is absent.

**R6 predicate verdicts** (P1 and P3 accepted from the handoff with its stated
reasons; P2 recomputed against the tree):

- **P1 fires** — three architectural alternatives are left open by the handoff:
  where the shared cascade script lives, whether `/work-on` retains, refuses or
  drops multi-pr support, and the shape of the per-child "do not cascade"
  signal.
- **P2 does-not-fire** — recomputed against the worktree. The shared-script
  relocation needs no new component: a repo-root `scripts/` already exists and
  already hosts cross-skill machinery, including `scripts/lib/` and
  `scripts/ci-gate-expression_test.sh`, which tests the very CI-gate expression
  `work-on.md` and `execute.md` duplicate on purpose. The likely home for a
  shared cascade script is an existing directory, not a new substrate.
- **P3 fires** — the handoff names architectural complexity directly: a 16-plus
  place routing surface across five skills and two eval suites, a two-PR
  decomposition whose order is load-bearing, and two accepted documents
  (`PRD-execute-skill.md` D5 and `DESIGN-execute-skill.md` Decision 2 R1) that
  must be superseded rather than contradicted.
