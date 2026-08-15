```yaml
topic: skill-adherence-enforcement
chain_started: 2026-08-15T19:59:34Z
last_updated: 2026-08-15T20:02:00Z
phase_pointer: phase-2
exit: UNSET
exit_artifacts: []
planned_chain:
  - brief
  - prd
  - design
  - plan
chain_skipped: []
chain_ran: []
visibility: Public
execution_mode: auto
max_rounds: 5
child_snapshots:
  design:
    status: Proposed
    content_hash: 2ce6abdd1cf9c4096855159c63eeab687c7b386c
    captured_at: 2026-08-15T20:02:00Z
worktree_rebases:
  - phase: brief
    upstream_commits:
      - 7eb98ec
      - fc9133e
      - 778913e
      - 83d29e1
      - b8b20eb
      - e227d7a
    impact: intent-changing-resolved-in-place
    rebased_at: 2026-08-15T20:06:00Z
    notes: >-
      fc9133e made a missing schema field an incomplete validator outcome
      rather than a pass; the DESIGN skeleton this chain inherited from the
      /explore handoff carried none, so shirabe validate returned
      outcome=incomplete and would have halted the Phase 2 validator
      pass-through. Resolved in place by adding schema: design/v1. The
      document now reports violations for six missing sections and two
      missing frontmatter fields, which are precisely the sections /design
      authors later in this chain. Kept rather than reverted because an
      absent schema field is the worse failure mode: the structural pass
      never runs at all and the document reports clean.
```

## Phase 1 Notes

**Discovery.** One topic artifact exists on disk:
`docs/designs/DESIGN-skill-adherence-enforcement.md` at `status: Proposed`,
written by the `/explore` Phase 5 handoff earlier today. `Proposed` is not a
settled status for `/design` (settled = Accepted, Planned, Current), so
re-entry protection does not hold `/design` back; the skeleton is a handoff
stub meant to be authored against, and `/design` re-authors it.

**Framing-shift answer (auto):** no shift. The exploration that produced the
skeleton concluded today; its findings, incident evidence, and decision report
are the inputs this chain consumes, and nothing about the problem shape,
audience, scope boundary, or success criterion has moved since.

**R6 predicate verdicts** (against the projected PRD shape; re-evaluated after
`/prd` returns):

- **P1 — architectural alternatives: FIRES.** The decision report leaves at
  least two implementation choices explicitly open for the DESIGN to settle:
  the off-machine publishing mechanism (a `Koto-Session:` PR trailer versus a
  run-report emit) and which predicate strengthening the delegation detector
  asserts (`currentState` advance, `scheduler_ran` with `spawned_count >= 1`,
  or child session directories).
- **P2 — new-component references: DOES-NOT-FIRE.** Every component the
  mechanism touches exists: `crates/shirabe/` for the check binary (the
  adherence check is a new subcommand on a shipped binary, not a new
  component), `skills/execute/` for the frontmatter registration, and koto's
  existing publishing path. No new binary, service, library, or runtime
  substrate is introduced.
- **P3 — Complex classification: FIRES.** The DESIGN skeleton names five
  interlocking open decisions spanning two repositories, and the crystallize
  evaluation scored the topic as multiple interrelated technical decisions
  rather than a single choice.

Roster shape: two of three predicates fire, so `/design` runs with a
full decision roster rather than the minimum.

**Pre-authoring upstream notice:** fired (both conditions held — `/brief` is in
`planned_chain:` and no `consumed_upstream:` was recorded).

**Proceed / Adjust / Bail:** auto-mode resolved to **Proceed**.

## Phase 0 Notes

Slug `skill-adherence-enforcement` validated against `^[a-z0-9-]+$` as
provided. `shirabe slug-prefix-detect` returned `no-prevailing-prefix`, so no
prefix recommendation was surfaced.

Visibility read from `CLAUDE.md` line 6 (`## Repo Visibility: Public`).

No `--upstream` supplied, so `consumed_upstream:` is absent per invariant I-5.

No `parent_orchestration:` block existed at session start; the unconditional
self-heal was a no-op.

**Coordination intent: absent (single-repo path).** The resolution stack is
`flag > CLAUDE.md-header > default`. No flag was passed. Both
`## PR Grouping Policy: coarsest-legal` and `## Reviewability Ceiling: default`
are present in this repo's CLAUDE.md, which is the header-level signal for
coordinated defaults on routine efforts. Resolved against it deliberately, as a
lightweight (Tier-2) call rather than a `/decision` escalation, on three
grounds: all four tactical-chain artifacts (BRIEF, PRD, DESIGN, PLAN) land in
this repo, so the planning chain itself is single-repo; whether *implementation*
spans shirabe and koto is `plan_execution_mode`, which `/plan` decides at the
terminal hop and which the coordinated-execution path in `/execute` already
handles; and coordination-PR creation is an outward-facing, up-front action that
would post a real PR before any artifact exists. If `/plan` concludes the
implementation is genuinely multi-repo, it records that as the execution mode
rather than requiring this chain to have been coordinated.
