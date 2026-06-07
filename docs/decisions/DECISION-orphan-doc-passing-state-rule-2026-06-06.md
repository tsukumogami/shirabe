---
status: Accepted
decision: |
  An orphan BRIEF, PRD, or DESIGN — a doc with no downstream PLAN or ROADMAP
  referencing it via `upstream:` — has passing state defined by its target
  state. Orphans at the artifact's target state (BRIEF Done, PRD Done, DESIGN
  Current) pass; orphans at non-terminal status whose own `upstream:` points
  at an Active ROADMAP also pass (ROADMAP-rooted lag is normal); every other
  orphan fails the `--lifecycle` check.
rationale: |
  Orphan-strict-naive is provably unworkable on the current corpus — 28+ docs
  would fail on day one, including every DESIGN at Current whose PLAN was
  deleted post-completion. Orphan-permissive lets the "framing started but
  never specified" drift sit silently, undermining the chain-aware passing-
  state model's stated reason for existing. The terminal-aware refinement
  fits the corpus, encodes the same forcing function as "stale Draft is
  drift" one altitude up, and remains explainable in a single BRIEF CUJ
  paragraph.
---

# DECISION: orphan-doc passing-state rule

## Status

Accepted

## Context

shirabe issue #116 introduces `shirabe validate --lifecycle <root>`, a chain-aware passing-state check. From each PLAN or ROADMAP in the doc tree it walks inverse `upstream:` edges to find the BRIEF/PRD/DESIGN, computes the chain's posture (single-pr vs multi-pr; mid-flight vs work-completing), and verifies each chain member is at its passing state — the frontmatter status required for this PR to merge with green CI.

The model has a hole for docs that have no downstream PLAN or ROADMAP pointing at them. The named candidates were orphan-permissive (skip orphans entirely) and orphan-strict (fail every orphan). Corpus analysis shows orphan-strict-naive fails 28+ docs on day one — every DESIGN at `Current` in `docs/designs/current/` is orphan by that literal definition because the PLAN that drove its work was deleted post-completion, and two PRDs are orphan at non-terminal status because they participate in ROADMAP-rooted multi-pr chains where the downstream lag is normal. Orphan-permissive avoids the corpus problem but undermines the chain-aware passing-state model's stated reason for existing: it lets an Accepted BRIEF with no downstream PRD sit indefinitely, which is exactly the flavor of drift the model is supposed to catch (parallel to the FC08/FC09 reconciliations this PR also lands).

## Decision

An orphan BRIEF, PRD, or DESIGN has its passing state defined by its target state:

- If the orphan's current status equals its artifact-type target state — BRIEF `Done`, PRD `Done`, DESIGN `Current` (a DESIGN is at terminal state when it lives in `docs/designs/current/`) — the orphan passes. This is the post-completion healthy case.
- If the orphan's current status is non-terminal AND its own `upstream:` points at an Active ROADMAP, the orphan passes. This is the in-flight ROADMAP-rooted case where the ROADMAP is the chain root and per-PRD downstream lag is allowed.
- If the orphan's current status is non-terminal AND it is linked into a coherent multi-member tactical chain — a downstream child points at it via `upstream:`, or its own `upstream:` resolves to another BRIEF/PRD/DESIGN/PLAN present in the tree — the orphan passes. This is the pre-PLAN in-flight case (a standalone chain with no ROADMAP root). See the refinement below.
- Every other orphan fails the check, with an `Lnn` error naming the file, its current state, and the expected passing state.

## Options Considered

### Option 1: Orphan-permissive

Skip orphans entirely. The check only applies passing-state computation to docs that participate in a chain rooted at a present PLAN or ROADMAP.

**Rejected.** The check is meant to catch the same flavor of drift the FC08/FC09 corpus reconciliation surfaces, applied one altitude up the chain. A BRIEF stuck at Accepted with no downstream PRD is precisely the silent drift the chain-aware passing-state model exists to catch; orphan-permissive lets that drift sit indefinitely and weakens the rule's stated value.

### Option 2: Orphan-strict (naive)

Fail every orphan regardless of status. The author must either delete the orphan or build the downstream chain.

**Rejected.** The current corpus has 28+ healthy orphans:

| Category | Count | Example |
|----------|-------|---------|
| DESIGN at `Current` with no downstream PLAN | 26 | `docs/designs/current/DESIGN-completion-cascade.md` |
| PRD at non-terminal status, orphan | 2 | `docs/prds/PRD-koto-adoption.md` (Accepted) |

Shipping this rule would require a parallel corpus mass-migration that exceeds this whole feature's scope, with no clear migration target for the legitimately-completed framing docs whose PLANs got deleted post-completion.

### Option 3: Terminal-aware orphan rule (chosen)

An orphan at its target state passes; an orphan at non-terminal status fails, with a ROADMAP-rooted exception for in-flight chains whose own `upstream:` points at an Active ROADMAP. Described in detail in the Decision section above.

**Chosen.** Synthesizes the two named candidates: tolerates the corpus's healthy orphans (the post-completion terminal-state case) while enforcing the discipline on the silent-drift case (orphan at non-terminal status). Single-CUJ explainable; modest implementation cost.

## Consequences

What becomes easier:
- Catching "framing started but never specified" drift as a CI signal, parallel to "stale Draft PLAN is drift."
- Shipping `--lifecycle` against the current corpus without a parallel migration PR.
- Explaining the chain-aware check's behavior in a single BRIEF CUJ paragraph.

What becomes harder:
- The chain-walker carries an artifact-type-keyed target-state map and a ROADMAP-root exception branch. Two more concepts to keep tested.
- A future change to any artifact type's terminal state (e.g., renaming DESIGN's `Current`) requires updating the orphan rule's target-state map alongside.

Accepted trade-off:
- The ROADMAP-root exception creates a small loophole: an orphan PRD whose upstream ROADMAP ages out without ever transitioning to Done sits silently. That case is a ROADMAP-level lifecycle question, not an orphan-rule question, and is left to future work.

## Refinement: in-flight tactical-chain exception (shirabe#188)

The terminal-aware rule above gave a non-terminal orphan exactly one way to pass: its own `upstream:` points at an Active ROADMAP. That escape is unavailable to a legitimate, in-flight tactical chain that has no ROADMAP root — exactly the shape the `/scope` parent skill produces when a BRIEF, PRD, and DESIGN are linked by `upstream:` but no PLAN exists yet (the documented pause-after-design state), and exactly the shape a public repo whose roadmap lives in a private repo must use, since public-clean forbids a public `upstream:` to a private artifact. Such a chain has no PLAN/ROADMAP root, so chain discovery finds no chain and every member falls to the orphan rule, which failed all of them mid-flight.

The refinement adds a third passing condition: a non-terminal orphan passes when it is **linked into a coherent multi-member tactical chain** — it has a downstream child (some doc points at it via `upstream:`) or its own `upstream:` resolves to another BRIEF/PRD/DESIGN/PLAN present in the tree. The drift the rule targets is a *single* isolated artifact (the reason Option 1, orphan-permissive, was rejected); a linked, progressing chain is active work, not drift. A lone non-terminal doc with nothing downstream and no resolvable tactical upstream still fails L02, so the drift-catching value is preserved. The linkage must resolve to an indexed tactical artifact, so a doc whose `upstream:` dangles at a missing path is still treated as drift.

This refinement also surfaced a paired over-strictness in the single-pr posture table: a single-pr chain carries its PRD, DESIGN, and PLAN together, and `/design` bumps the PRD `Accepted -> In Progress`, so mid-PR the PRD is legitimately at `In Progress`. The single-pr mid-PR passing state for the PRD is widened to accept `Accepted` or `In Progress` (mirroring the multi-pr in-flight row) so the chain passes once its PLAN is present.

## Encoding the rule downstream

The BRIEF for this lifecycle feature must include a CUJ paragraph describing the orphan rule with both worked examples (the FC09 post-completion case and the inverted Accepted-BRIEF-no-PRD case), so a reader of the BRIEF grasps the rule before reading the PRD or DESIGN. The chain-walker module enforces the rule via the per-artifact-type target-state map and the ROADMAP-root exception branch.
