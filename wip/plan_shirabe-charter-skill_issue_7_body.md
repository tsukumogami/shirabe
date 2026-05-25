---
complexity: critical
complexity_rationale: Three-exits invariant enforcement is the contract spine for every /charter chain (every run must end at exactly one durable artifact; bail must never silently lose), and the Reject-vs-Bail distinction plus the tie-break clean-cancel fallthrough are load-bearing for the design's discipline-vs-artifact decoupling — mis-routing collapses two distinct contract paths and silently corrupts terminal state.
---

## Goal

Ship `skills/charter/references/phases/phase-finalization.md` specifying the three exit-path orchestration LOGIC for `/charter`: which exit fires for each terminal trigger (full-run, re-evaluation with re-evaluation and rejection sub-shapes, abandonment-forced), the R8 three-step tie-break for resolving "most-recently-running" with its clean-cancel fallthrough, the load-bearing distinction between `/strategy` Phase 5 Reject (deliberate finalization judgment → rejection sub-shape) and mid-chain Bail (R7.5 Bail / "wrap it up" / Force-materialize / stale-session → abandonment-forced), and the state-field assignments each exit produces so Issue 8's artifact authoring knows what to write.

## Context

`/charter` is the first parent skill in the shirabe parent-skill pattern; semantic invariant I-2 from the pattern says every chain ends at a durable file (the three-exits invariant). This issue is the contract enforcement surface for that invariant: a `/charter` chain that terminates without firing exactly one of the three named exits is a violation. Exit-path orchestration answers "when does each exit fire?" — Issue 8 answers "what files get written?" Splitting these two concerns lets the orchestration logic be inspected and tested separately from the artifact authoring rules.

The pattern-level reference `references/parent-skill-pattern.md` (landed by `<<ISSUE:1>>`) names the three exits. `/charter`'s parent-specific binding lives here: the sub-shape distinctions inside re-evaluation, the routing rules for each trigger, and the R8 tie-break procedure for "most-recently-running." The state-file schema landed by `<<ISSUE:5>>` defines every field this issue's orchestration writes (`exit`, `decision_record_sub_shape`, `chain_ran`, `chain_completed`, `exit_artifacts`, `referenced_strategy`, `discard_commit_sha`, `rejection_rationale`, `triggering_child`, `partial_phase_reached`), and the R9 hard finalization check from `<<ISSUE:5>>` is the contract violation surface that runs after this issue's orchestration completes.

The Phase 5 Reject vs Bail distinction is the most subtle and most load-bearing element of this issue. They look superficially similar — both terminate a chain without producing a Draft STRATEGY in the usual full-run shape — but they are distinct contract paths:

- **`/strategy` Phase 5 Reject** is `/strategy`'s deliberate finalization judgment: the author worked through `/strategy` to its terminal phase, weighed the draft on its merits, and consciously chose to reject it. `/strategy` runs the discard (removes `docs/strategies/STRATEGY-<topic>.md`, cleans `wip/strategy_<topic>_*.md`, commits a discard message) and returns control to `/charter`. This path produces a **rejection sub-shape** of the **re-evaluation** exit — a durable Decision Record citing the discard commit SHA.
- **Bail mid-chain** is the author abandoning the chain before any child reaches a deliberate finalization judgment. It fires from four triggers: explicit "wrap it up", "Bail" at the R7.5 chain-proposal prompt (Issue 4), "Force-materialize" at the resume-ladder row 4 stale-session prompt (Issue 6), or the resume ladder row 4 firing on a stale session (≥ 7 days) where the author chooses Force-materialize. This path produces the **abandonment-forced** exit — the most-recently-running child's intermediate is force-materialized as a Draft with an HTML-comment marker.

Collapsing these two paths would erase the design's discipline-vs-artifact decoupling: a deliberate Reject would become indistinguishable from an interrupted Bail, and Decision Records would silently absorb chain abandonments that have nothing to do with strategic judgment.

The R8 tie-break for "most-recently-running" is the procedural mechanism that resolves which child's intermediate gets force-materialized when the author bails. Its three steps must be evaluated in order, and step 3 (clean-cancel fallthrough) is critical: when nothing exists to materialize — no `chain_ran` history AND no `planned_chain` entry with a non-empty wip/ intermediate — the chain ends with no state file and no terminal artifact. This is NOT abandonment-forced; it is clean-cancel. Missing the fallthrough writes incomplete state and silently violates the three-exits invariant.

Design: `docs/designs/DESIGN-shirabe-progression-authoring.md` (Solution Architecture Component 1 — three exit paths named in `parent-skill-pattern.md`; Solution Architecture Component 3 — Two-Layer Contract with semantic invariant I-2 every chain ends at a durable file; Decision 6 — Conditional Feeder Invocation Shape; Security Considerations — public-repo pre-merge feature-branch exposure).

PRD: `docs/prds/PRD-shirabe-charter-skill.md` (R8 three exit paths + tie-break for most-recently-running; R7.5 Bail option routing per R8; ACs AC11a, AC11b, AC12b, AC12c, AC13 logic half, AC14 logic half, AC14b, AC18b context).

## Acceptance Criteria

### File presence

- [ ] `skills/charter/references/phases/phase-finalization.md` exists.
- [ ] The file is cited from `skills/charter/SKILL.md` (from the Phase Execution section or the Reference Files table) so the exit-path orchestration is discoverable from the SKILL entrypoint.

### Pattern-level citation

- [ ] The file cites `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` as the source of the three named exits (full-run, re-evaluation, abandonment-forced) — citation, not re-derivation.
- [ ] The file names the three exits explicitly and states they correspond to `/charter`'s parent-specific binding of the pattern-level Three Exit Paths section.

### Exit 1 — full-run (R8)

- [ ] The file documents Exit 1 (full-run) fires when `/strategy` completes with a Draft STRATEGY and no `/strategy` Phase 5 Reject occurs; optionally `/roadmap` also fires per `<<ISSUE:4>>`'s R7 gates.
- [ ] State-field assignments documented for full-run: `exit: full-run`; `chain_completed` set; `chain_ran` lists children that ran; `exit_artifacts` lists STRATEGY (and ROADMAP if it ran).
- [ ] **AC11a coverage**: STRATEGY-only chain produces `exit: full-run` with `exit_artifacts` containing exactly one entry (the STRATEGY path with status `Draft`).
- [ ] **AC11b coverage**: STRATEGY + ROADMAP chain produces `exit: full-run` with `exit_artifacts` containing exactly two entries (STRATEGY path + ROADMAP path, each with status `Draft`).
- [ ] The file states conditional fields (`decision_record_sub_shape`, `referenced_strategy`, `discard_commit_sha`, `rejection_rationale`, `triggering_child`, `partial_phase_reached`) MUST be absent for full-run per the R9 conditional-field gating enforced by `<<ISSUE:5>>`.

### Exit 2 — re-evaluation (R8), re-evaluation sub-shape (US-2)

- [ ] The file documents the re-evaluation sub-shape fires when the entry-router row 5 prompt (STRATEGY Accepted/Active offering "Re-evaluate / Revise / Bail") selects "Re-evaluate" AND the chain walks through Bet-Specific Falsifiability claims AND all claims hold.
- [ ] State-field assignments documented for re-evaluation sub-shape: `exit: re-evaluation`; `decision_record_sub_shape: re-evaluation`; `referenced_strategy: <strategy-path>`; `chain_completed` set.

### Exit 2 — re-evaluation (R8), rejection sub-shape (US-3a) and the Reject-vs-Bail distinction

- [ ] The file documents the rejection sub-shape fires when `/strategy` Phase 5 Reject fires INSIDE a `/charter` chain.
- [ ] The file states explicitly that Phase 5 Reject is `/strategy`'s deliberate finalization judgment, NOT a bail. This distinction is load-bearing for the design's discipline-vs-artifact decoupling.
- [ ] The flow is documented end-to-end: `/charter` invokes `/strategy` → `/strategy` runs to Phase 5 → user picks Reject → `/strategy` runs `git rm docs/strategies/STRATEGY-<topic>.md`, cleans up `wip/strategy_<topic>_*.md`, commits `docs(strategy): discard STRATEGY draft for <topic>` → control returns to `/charter` → `/charter` captures the discard commit SHA via read-only `git log` → state file written.
- [ ] State-field assignments documented for rejection sub-shape: `exit: re-evaluation`; `decision_record_sub_shape: rejection`; `discard_commit_sha: <sha>`; `rejection_rationale: <text>`; `chain_completed` set. The Decision Record itself is authored by `<<ISSUE:8>>` referencing the SHA + rationale.
- [ ] `/charter` issues NO git writes during rejection orchestration; the discard commit is `/strategy`'s responsibility. `/charter` only captures the SHA via `git log` (read-only).
- [ ] **AC18b context**: the file states that outside a `/charter` chain (manual fallback: author invokes `/strategy` directly and picks Reject), `/charter` does NOT retroactively produce a rejection Decision Record. The rejection sub-shape is `/charter`-orchestrated only. `<<ISSUE:6>>`'s resume-ladder behavior enforces this.

### AC12b — Revise branch

- [ ] The file documents the AC12b "Revise" branch: when the author picks "Revise" at the entry router for an Accepted STRATEGY, `/charter` invokes `/strategy` with the existing STRATEGY path (Input Mode 2 — `/strategy`'s resume-from-Accepted offer-to-revise flow).
- [ ] The file states the Revise branch produces a revised Draft and the chain exits at `exit: full-run` with the revised artifact in `exit_artifacts`. This is full-run, NOT re-evaluation, because `/strategy` produced a revised Draft.
- [ ] The file states the Revise branch does NOT produce a Decision Record.

### Exit 3 — abandonment-forced (R8)

- [ ] The file documents Exit 3 (abandonment-forced) fires when the author bails mid-chain. Four triggers enumerated:
  1. Author explicitly says "wrap it up".
  2. Author picks "Bail" at the R7.5 chain-proposal prompt (originating from `<<ISSUE:4>>`).
  3. Author picks "Force-materialize" at the resume-ladder row 4 stale-session prompt (`≥ 7 days`) (originating from `<<ISSUE:6>>`).
  4. Resume ladder row 4 fires AND the author chooses Force-materialize.
- [ ] State-field assignments documented for abandonment-forced: `exit: abandonment-forced`; `triggering_child: <name>`; `partial_phase_reached: <phase>`; `chain_completed` set.
- [ ] The file states `decision_record_sub_shape` MUST be ABSENT for abandonment-forced per R9 conditional-field gating (`<<ISSUE:5>>`'s finalization check enforces this).
- [ ] The file states the force-materialized artifact is the child that was running at time of bail, resolved via the R8 tie-break (below).
- [ ] The file states the force-materialized artifact gets an HTML-comment marker `<!-- charter-status-block: abandonment-forced; ... -->` authored by `<<ISSUE:8>>`.

### AC14b — bail inside a child

- [ ] The file documents **AC14b**: when the author bails inside an invoked child (`/vision`, `/comp`, or `/roadmap` — not just `/strategy`), the resume ladder on the next entry routes to abandonment-forced per US-3b semantics; the artifact force-materialized is the child that was running at time of bail (resolved via the tie-break).

### AC12c — chain-proposal Bail and clean-cancel

- [ ] The file documents **AC12c**: at the R7.5 chain-proposal Bail (or entry-router Bail) with no prior wip/ intermediate AND no `chain_ran` history, the chain ends with clean-cancel. With prior wip/ intermediate OR `chain_ran` history, the chain ends with abandonment-forced.

### R8 tie-break for "most-recently-running"

The file specifies the tie-break as a three-step procedure with explicit clean-cancel fallthrough:

- [ ] Step 1: take the last entry in the state file's `chain_ran` field. If non-empty, that child is the most-recently-running; tie-break resolves to it. Otherwise proceed to step 2.
- [ ] Step 2: take the first entry in `planned_chain` that has a non-empty wip/ intermediate on disk. If found, that child is the most-recently-running; tie-break resolves to it. Otherwise proceed to step 3.
- [ ] Step 3: if neither step resolves to a child (no `chain_ran` history, no `planned_chain` entry with a wip/ intermediate), the chain ends with **clean-cancel** — NOT abandonment-forced. No state file is written. No terminal artifact is produced. No contract violation is recorded; there is simply nothing to force-materialize.
- [ ] The file states clean-cancel is NOT a contract violation of the three-exits invariant. Clean-cancel applies only when no chain progress has been made; the chain never started in a load-bearing sense.
- [ ] The file states when the tie-break resolves to a child (step 1 or step 2), Issue 7 directs `<<ISSUE:8>>` to force-materialize that child's intermediate as a Draft artifact with the `<!-- charter-status-block: abandonment-forced; ... -->` marker.
- [ ] **AC12c clean-cancel coverage**: the tie-break documentation makes the clean-cancel case reachable when no wip state exists.

### Reject vs Bail distinction documented

- [ ] The file documents the Reject-vs-Bail distinction as a dedicated section (named or clearly headed) so a future reader cannot conflate the two paths.
- [ ] The file states `/strategy` Phase 5 Reject → rejection sub-shape of re-evaluation exit (Exit 2).
- [ ] The file states Bail mid-chain (closed session, "wrap it up", R7.5 Bail option, stale ≥ 7 days + Force-materialize) → abandonment-forced (Exit 3).
- [ ] The file states these two paths are distinct contract paths despite their surface similarity, and conflating them collapses the design's discipline-vs-artifact decoupling.

### State-field citations to Issue 5

- [ ] The file references `<<ISSUE:5>>`'s state-schema specification for the field definitions of `exit`, `decision_record_sub_shape`, `triggering_child`, `partial_phase_reached`, `discard_commit_sha`, and `rejection_rationale`. Field semantics are NOT re-derived here.

### Routing-source citations

- [ ] The file states R7.5 chain-proposal Bail routing originates from `<<ISSUE:4>>` (chain-proposal prompt) but the routing decision logic lives here.
- [ ] The file states resume-ladder row 4 Force-materialize routing originates from `<<ISSUE:6>>` (resume ladder) but the routing decision logic lives here.

### Downstream deliverables

- [ ] Must deliver: every exit's triggering condition + state-field assignments + (for re-evaluation) sub-shape determination is documented so `<<ISSUE:8>>` knows which exit fired and which artifact + state-field shape to write (required by `<<ISSUE:8>>`).
- [ ] Must deliver: the tie-break resolution procedure is documented so `<<ISSUE:8>>` knows which child's intermediate to force-materialize (required by `<<ISSUE:8>>`).
- [ ] Must deliver: every exit-triggering behavior is documented (all four abandonment-forced triggers, both re-evaluation sub-shape triggers, full-run trigger, AC12b Revise branch, AC12c clean-cancel) so `<<ISSUE:9>>`'s eval scenarios can assert each one against the expected exit + state fields (required by `<<ISSUE:9>>`).

- [ ] Security review completed

## Validation

```bash
#!/usr/bin/env bash
set -euo pipefail

# Phase file presence
test -f skills/charter/references/phases/phase-finalization.md

# Three exits named explicitly
grep -qF "full-run" skills/charter/references/phases/phase-finalization.md
grep -qF "re-evaluation" skills/charter/references/phases/phase-finalization.md
grep -qF "abandonment-forced" skills/charter/references/phases/phase-finalization.md

# Both sub-shapes named
grep -qF "rejection" skills/charter/references/phases/phase-finalization.md
grep -qE "re.evaluation.sub.shape" skills/charter/references/phases/phase-finalization.md

# Tie-break procedure references state-file fields
grep -qE "(chain_ran|planned_chain)" skills/charter/references/phases/phase-finalization.md
grep -qF "chain_ran" skills/charter/references/phases/phase-finalization.md
grep -qF "planned_chain" skills/charter/references/phases/phase-finalization.md

# Clean-cancel fallthrough documented
grep -qE "(clean.cancel)" skills/charter/references/phases/phase-finalization.md

# Reject vs Bail distinction
grep -qE "(Reject|Bail)" skills/charter/references/phases/phase-finalization.md
grep -qF "Reject" skills/charter/references/phases/phase-finalization.md
grep -qF "Bail" skills/charter/references/phases/phase-finalization.md

# Pattern-level citation
grep -qF "parent-skill-pattern.md" skills/charter/references/phases/phase-finalization.md

# State-field references (forward to Issue 5)
grep -qE "(triggering_child|partial_phase_reached|discard_commit_sha|rejection_rationale)" skills/charter/references/phases/phase-finalization.md
grep -qF "triggering_child" skills/charter/references/phases/phase-finalization.md
grep -qF "partial_phase_reached" skills/charter/references/phases/phase-finalization.md
grep -qF "discard_commit_sha" skills/charter/references/phases/phase-finalization.md
grep -qF "rejection_rationale" skills/charter/references/phases/phase-finalization.md

# State-file canonical path named
grep -qF "wip/charter_" skills/charter/references/phases/phase-finalization.md

# AC12b Revise branch documented
grep -qiE "(revise|revised draft)" skills/charter/references/phases/phase-finalization.md

# Force-materialize trigger documented
grep -qiE "(force.materialize|force-materialize)" skills/charter/references/phases/phase-finalization.md

# Stale-session 7-day threshold cited
grep -qE "(7.day|≥.7|7 days)" skills/charter/references/phases/phase-finalization.md

# HTML-comment marker forwarded to Issue 8
grep -qF "charter-status-block" skills/charter/references/phases/phase-finalization.md

# SKILL.md cites the phase-finalization file
grep -qF "phase-finalization.md" skills/charter/SKILL.md

echo "All validations passed"
```

## Security Checklist

`/charter`'s exit-path orchestration is the contract enforcement surface for semantic invariant I-2 (every chain ends at a durable file). Mis-routed exits, silently-lost bails, and conflated Reject/Bail paths are all contract violations with durable evidence on public-repo feature branches from push time. The checklist below enforces the contract paths and prevents the orchestration from being weaponized.

- [ ] Three-exits invariant enforced: every chain orchestrated by `/charter` terminates at exactly one of `{full-run, re-evaluation, abandonment-forced}` OR at clean-cancel when nothing exists to materialize. Bail never silently loses (semantic invariant I-2 from `parent-skill-pattern.md`).
- [ ] Tie-break clean-cancel fallthrough explicitly prevents writing incomplete state when nothing exists to force-materialize: step 3 of the tie-break must end the chain with NO state file, NO terminal artifact, and NO `exit:` value written.
- [ ] Reject (deliberate `/strategy` Phase 5 finalization judgment) and Bail (mid-chain abandonment) are documented as distinct contract paths; conflating them would collapse the design's discipline-vs-artifact decoupling and silently absorb chain abandonments into Decision Records.
- [ ] Discard commit SHA is captured via read-only `git log` for the rejection sub-shape; `/charter` issues NO git writes during exit orchestration. The discard commit is `/strategy`'s responsibility.
- [ ] `rejection_rationale` is free-text from the author — exit orchestration MUST NOT echo back its content into other state fields where it could be parsed differently. Treat as opaque text passed to `<<ISSUE:8>>`'s Decision Record body.
- [ ] AC18b enforced: manual-fallback `/strategy` Reject (outside a `/charter` chain) does NOT retroactively produce a rejection Decision Record. The rejection sub-shape is `/charter`-orchestrated only; `<<ISSUE:6>>`'s resume-ladder behavior enforces this.
- [ ] R9 conditional-field gating enforced: each exit's state-field assignments include the explicit absence requirement for fields that do not apply (e.g., `decision_record_sub_shape` MUST be absent for `exit: full-run` and `exit: abandonment-forced`).
- [ ] No third-party dependencies introduced (documentation-only file; no executable code).
- [ ] Public-repo durable-evidence surface: orchestration documentation surfaces that state-file `exit:`, `triggering_child:`, and free-text fields (`rejection_rationale`) are durably public on feature branches; authors are warned no secrets/customer-identifiable context/unpublished competitive positioning may flow into `rejection_rationale`.
- [ ] Security review completed.

## Dependencies

Blocked by `<<ISSUE:4>>` (child-invocation logic must exist so exit orchestration can route off the "STRATEGY produced" event and so the R7.5 chain-proposal Bail option routes here).

Blocked by `<<ISSUE:5>>` (state-file schema must exist so exit orchestration's state-field assignments cite defined fields; the R9 hard finalization check from Issue 5 is the contract violation surface that runs immediately after this orchestration completes).

## Downstream Dependencies

- `<<ISSUE:8>>` — exit-artifact authoring (Decision Records both sub-shapes + abandonment-forced HTML-comment marker + STRATEGY validation pass-through) consumes Issue 7's exit-decision + state-field values. Deliverable: `phase-finalization.md` fully specifies which exit fires for each trigger AND which state fields populate, so Issue 8 knows what artifact to write and what content to populate.
- `<<ISSUE:9>>` — evals cover AC11a, AC11b, AC12b, AC12c, AC13, AC14, AC14b. Deliverable: `phase-finalization.md` documents all exit-triggering behaviors (full-run STRATEGY-only, full-run STRATEGY + ROADMAP, re-evaluation re-evaluation sub-shape, re-evaluation rejection sub-shape, abandonment-forced from each of four triggers, AC12b Revise branch, AC12c chain-proposal Bail with and without prior wip state) so eval scenarios can assert the expected exit + state-field shape for each.
