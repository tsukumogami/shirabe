---
complexity: critical
complexity_rationale: Five phase reference files together carry every /scope-specific operational contract — slug re-validation on resume, closed write-target set, commit-via-stdin for free-form rationale, stale parent_orchestration self-healing, R8 tie-break, and Decision Record path interpolation — making this the load-bearing security surface of /scope.
---

## Goal

Create the five phase reference files at `skills/scope/references/phases/phase-{0..4}-*.md` that document `/scope`'s per-phase operational contracts. The references cover slug validation + stale-sentinel self-heal (Phase 0), R6 shape-predicate evaluation with worked examples (Phase 1), the child-invocation loop with sentinel write/clear + validator pass-through + Phase-N Reject observability (Phase 2), exit finalization with R8 tie-break + abandonment-forced HTML-comment marker (Phase 3), and `wip/` cleanup (Phase 4). The five security mitigations from the design's Security Considerations section ship inside these files.

## Context

Design: `docs/designs/DESIGN-shirabe-scope-skill.md`

The `/scope` SKILL.md body (shipped by <<ISSUE:10>>) names five Workflow Phases and points its Phase Execution list at this directory. Each phase reference encodes the procedural detail a different agent run would have to re-derive otherwise — Phase 1's R6 walk includes 3-4 worked examples per predicate to bound interpretive drift (Decision 2); Phase 2's Phase-N Reject handling reads the discard-commit signal via `git log` to stay parity-aligned with manual-fallback observability (Component 7.7); Phase 3's HTML-comment marker is uniform single-line across all four artifact types per Decision 7.

The phase references are the load-bearing security surface of `/scope`:

- **Phase 0** carries the slug regex re-validation on resume (Security Considerations § Command injection — slug re-validation), the unconditional stale `parent_orchestration:` self-heal (§ State-file race conditions), and the closed write-target set enforcement gate.
- **Phase 1** carries the R6 structured-checklist walk per Decision 2 with worked examples; the chain-proposal output containing the literal Proceed/Adjust/Bail substrings per R7.5; the Mandatory-with-auto-skip evaluation for `/prd`.
- **Phase 2** carries the `parent_orchestration:` sentinel write/clear sequence; the worktree-staleness check; the structural file-existence check (R20); the `git log` discard-commit observation for Phase-N Reject; the `shirabe validate` pass-through per PRD Decision 10; the state-file enum re-validation before path interpolation.
- **Phase 3** carries the R8 three-exit-path semantics including the most-recently-running tie-break that resolves `triggering_child:` for abandonment-forced; the uniform single-line HTML-comment marker per Decision 7 with the literal substring contract; the R9 hard-finalization check; the `git commit -F` discipline for any author-supplied rationale (§ Command injection — git-commit rationale interpolation); the public-history disclaimer.
- **Phase 4** carries the `wip/` cleanup invariant (the closed write-target set enumerates exactly what may be removed).

This issue is the second-largest deliverable in PR-4 (after <<ISSUE:10>>). Its phase references are cited from `/scope` SKILL.md's Phase Execution list (shipped by <<ISSUE:10>>) and exercised by the eval suite (shipped by <<ISSUE:13>>).

## Acceptance Criteria

### Phase 0 — `skills/scope/references/phases/phase-0-setup.md`

- [ ] File exists at `skills/scope/references/phases/phase-0-setup.md`.
- [ ] Documents the cold-start path: empty `$ARGUMENTS` surfaces a cold-start prompt and stops Phase 0 (no auto-derivation, no looping).
- [ ] Documents byte-for-byte slug validation against `^[a-z0-9-]+$` cited from `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`; no normalization step before validation.
- [ ] Includes at least four concrete rejection examples covering uppercase letters, underscores, dots, and slashes (path-as-topic), each with the rejection wording shape "Topic slug `<input>` does not match the required pattern `^[a-z0-9-]+$`".
- [ ] Documents visibility detection from the repo's `CLAUDE.md` `## Repo Visibility:` header (Public / Private values).
- [ ] **Slug re-validation on resume contract** (Security Considerations § Command injection — slug re-validation): any slug recovered from an on-disk artifact path during resume (Slot 5 file-glob matches against `docs/{briefs,prds,designs/current,designs,plans}/<TYPE>-<topic>.md`) SHALL be re-validated against `^[a-z0-9-]+$` BEFORE entering interpolation into any emitted shell command. An unparseable slug rejects the resume entry, surfaces a diagnostic naming the offending path, and routes to R8 bail-handling.
- [ ] **Stale `parent_orchestration:` self-heal contract** (Security Considerations § State-file race conditions): Phase 0 SHALL unconditionally clear any `parent_orchestration:` block found at session start. The self-heal MUST NOT prompt the author and MUST NOT surface a warning (self-heal is the contract).
- [ ] Documents the initial state-file shape written at the end of Phase 0: `topic`, `chain_started`, `last_updated`, `phase_pointer: phase-0`, `exit: UNSET`, `exit_artifacts: []`, plus an empty `planned_chain: []`.
- [ ] Documents that worktree-discipline (per `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-worktree-discipline.md`) does NOT fire in Phase 0; the trigger is bounded to before each Phase 2 child invocation.
- [ ] Cites `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md` for the slug regex and `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` for the storage substrate convention.

### Phase 1 — `skills/scope/references/phases/phase-1-discovery.md`

- [ ] File exists at `skills/scope/references/phases/phase-1-discovery.md`.
- [ ] **Discovery prompt structure** documented verbatim per R4 — the prompt includes the framing-shift question; the literal prompt text is captured in full for eval-grep checking.
- [ ] **R4 EITHER-signal evaluation for `/brief`**: documents the two independent signals (no upstream BRIEF at the canonical path, or framing-shift signal positive from the discovery prompt). Either signal alone fires `/brief`; both holding fires once.
- [ ] **R5 Mandatory-with-auto-skip evaluation for `/prd`**: documents the auto-skip semantics — if `docs/prds/PRD-<topic>.md` exists at the canonical path in Accepted status, record `/prd` in `chain_skipped` with reason `accepted-prd-at-canonical-path` and proceed to the next gate. The parent MUST NOT silently overwrite an Accepted durable artifact.
- [ ] **R6 shape-predicate walk** documents the three predicates in order (P1 architectural-alternatives count, P2 new-component references, P3 Complex classification). Each predicate emits a `fires` / `does-not-fire` verdict and a one-line reason.
- [ ] R6 walk includes **at least 3 worked examples per predicate** (positive and negative cases), per Decision 2's recommendation, so future authors can calibrate (e.g., P1 positive: "the PRD SHALL use TLS for transport; cipher suite to be decided" → 1 alternative; P1 negative: "the PRD SHALL log to stderr at INFO level" → 0 alternatives).
- [ ] **R7 shape-dependent evaluation for `/design`**: documents that `/design` fires when one or more R6 predicates fire; when zero predicates fire, `/design` is recorded in `chain_skipped` with the per-predicate verdicts as the skip reason.
- [ ] **Chain-proposal output construction (R7.5)**: documents the output structure with the per-gate verdicts assembled. The output SHALL contain the literal substrings `Proceed`, `Adjust`, and `Bail` (case-sensitive, exact spelling per AC9).
- [ ] Documents the `planned_chain:` state-file field population from Phase 1 verdicts (one entry per child that fires; skipped children appear in `chain_skipped:` not `planned_chain:`).
- [ ] Documents that initial `child_snapshots:` are captured for any existing durable artifact discovered during Phase 1 (status + git blob hash per R10).
- [ ] Documents Phase 1's three-way Adjust path: Adjust → re-enter Phase 1 with the author's adjustment input; Proceed → Phase 2; Bail → R8 bail-handling.
- [ ] Cites `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` for the Gate Vocabulary (delivered by <<ISSUE:7>>).

### Phase 2 — `skills/scope/references/phases/phase-2-chain-orchestration.md`

- [ ] File exists at `skills/scope/references/phases/phase-2-chain-orchestration.md`.
- [ ] Documents the per-child invocation loop ordering: (1) worktree-staleness check, (2) sentinel write, (3) child invocation, (4) structural file-existence check, (5) sentinel clear, (6) child-snapshot capture, (7) validator pass-through.
- [ ] **Worktree-staleness check (R21)** fires before each child invocation; executes `git fetch && git status --branch --short`; on divergence surfaces the three-option prompt (`Rebase / Proceed anyway / Bail`). Cites `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-worktree-discipline.md` (delivered by <<ISSUE:1>>).
- [ ] Documents the `worktree_divergences:` list append on "Proceed anyway" — entry shape `{phase: <child-name>, upstream_ahead_by: <count>, accepted_at: <ISO-8601>, rationale: <author-supplied>}`. The author-supplied rationale field is committed via `git commit -F` discipline cited from Phase 3 (no shell interpolation).
- [ ] **`parent_orchestration:` sentinel write** documents the block written immediately before the child invocation:

      ```yaml
      parent_orchestration:
        invoking_child: brief | prd | design | plan
        suppress_status_aware_prompt: true
        rationale: fresh-chain | revise
      ```

- [ ] **Child invocation** documents that `/scope` invokes the child via the child's existing input mode (topic-slug argument). R14 child-isolation preserved: `/scope` reads only the child's durable artifact's frontmatter `status:` + git blob hash; `/scope` does NOT extend the child's `$ARGUMENTS`, env-var consumption, or flag parser per the L13 amendment.
- [ ] **Structural file-existence check (R20)** documents the post-invocation check against the canonical path (`docs/briefs/BRIEF-<topic>.md`, `docs/prds/PRD-<topic>.md`, `docs/designs/DESIGN-<topic>.md`, `docs/plans/PLAN-<topic>.md`). PASS-with-no-artifact maps to STALE and routes via R8's bail-handling using the most-recently-running tie-break.
- [ ] **`parent_orchestration:` cleanup** documents that `/scope` removes the entire block from the state file immediately after the child returns (regardless of PASS/Reject/STALE outcome).
- [ ] **Child-snapshot capture** documents `child_snapshots.<child> = {status: <frontmatter-status>, content_hash: <git-blob-hash>, captured_at: <ISO-8601>}` per R10.
- [ ] **Phase-N Reject handling (Component 7.7)** documents observation via `git log` on the current branch — `/scope` searches for the most recent `docs(prd): discard PRD draft for <topic>` or `docs(design): discard DESIGN draft for <topic>` commit between the sentinel write and the child return. Presence of that commit identifies the Reject outcome.
- [ ] Documents that on Reject, `/scope` captures the discard commit SHA and the rejection rationale (from the commit body) into `discard_commit_sha:` and `rejection_rationale:` state-file fields, then advances to Phase 3 with `exit: re-evaluation`, `boundary: prd|design`, `decision_record_sub_shape: rejection`.
- [ ] Documents that the `git log`-based observability mechanism preserves R13 manual-fallback parity (the discard commit is the durable signal whether the child ran in-chain or out-of-chain).
- [ ] **Validator pass-through** documents `shirabe validate` running against each intermediate after the structural file-existence check passes (per PRD Decision 10). Failed validation halts the chain and routes to R8 bail-handling.
- [ ] Documents that the per-child rule reads — `/brief` R4 EITHER-signal, `/prd` R5 Mandatory-with-auto-skip, `/design` R6 shape-predicate (re-evaluated via state-file cached verdicts from Phase 1, not re-walked), `/plan` ALWAYS — pull from `planned_chain:` populated in Phase 1 rather than re-evaluating gates.
- [ ] Cites `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` (Gate Vocabulary, L13 amendment) and the worktree-discipline reference.

### Phase 3 — `skills/scope/references/phases/phase-3-exit-finalization.md`

- [ ] File exists at `skills/scope/references/phases/phase-3-exit-finalization.md`.
- [ ] **Three exit paths (R8)** documented as the only valid `exit:` values: `full-run`, `re-evaluation`, `abandonment-forced`. UNSET fails the R9 hard-finalization check.
- [ ] **Full-run exit** documents: terminal `/plan` returned successfully; PLAN already lives at `docs/plans/PLAN-<topic>.md` (Draft in single-pr mode; Active in multi-pr mode alongside a GitHub milestone). State-file fields populated: `exit: full-run`, `chain_completed: <ISO-8601>`, `plan_execution_mode: single-pr | multi-pr` (gated by `/plan` appearing in `chain_ran`).
- [ ] **Re-evaluation exit** documents: writes Decision Record at `docs/decisions/DECISION-{prd|design}-<topic>-{re-evaluation|rejection}-<YYYY-MM-DD>.md` per Interface I.2. State-file fields populated: `exit: re-evaluation`, `boundary: prd | design`, `decision_record_sub_shape: re-evaluation | rejection`, `referenced_artifact: <path>`.
- [ ] Documents the four boundary × sub-shape combinations and which template each uses (`skills/scope/references/decision-record-{prd|design}-{re-evaluation|rejection}.md`, delivered by <<ISSUE:12>>).
- [ ] On `decision_record_sub_shape: rejection`, the Decision Record body references the discard commit SHA and the author-supplied rationale captured in Phase 2.
- [ ] **Abandonment-forced exit** documents: force-materialize the most-recently-running child's intermediate as a Draft artifact at its canonical path, with the HTML-comment marker inside the artifact's existing Status section.
- [ ] **R8 tie-break for `triggering_child:`** documents the most-recently-running rule: when multiple children have unfinished `wip/` intermediates, `triggering_child:` is set to the child whose Phase 2 invocation began most recently (read from the state file's per-child Phase 2 start timestamps). The tie-break is deterministic; no author prompt.
- [ ] **HTML-comment marker (Decision 7)** documents the literal text:

      ```
      <!-- scope-status-block: abandonment-forced; triggering-child: <name>; partial-phase-reached: <phase>; chain-started: <ISO-8601 timestamp> -->
      ```

      The marker SHALL be a single line; whitespace inside is significant; the four fields are populated from `triggering_child:`, `partial_phase_reached:`, `chain_started:` in the state file. The marker is placed at the END of the artifact's existing Status section.
- [ ] Documents that the marker uniformly applies to all four artifact types (BRIEF / PRD / DESIGN / PLAN) without per-child variation; the grep-checkable substring is `scope-status-block: abandonment-forced`.
- [ ] **R9 hard-finalization check** documents: refuse finalization if any of (`exit:` is UNSET or not in enum; `exit_artifacts:` empty when exit requires artifacts; conditional fields gated by `exit:` value are UNSET or out-of-enum; `boundary:` + `decision_record_sub_shape:` discriminators both set when `exit: re-evaluation`; `plan_execution_mode:` set if and only if `/plan` appears in `chain_ran`).
- [ ] **`git commit -F` discipline** (Security Considerations § Command injection — git-commit rationale interpolation): any author-supplied free-form string written into a commit body (rejection rationale captured from Phase 2, "Proceed anyway" rationale from worktree-staleness divergence) SHALL be passed to `git commit` via `-F <tmpfile>` or stdin (`git commit -F -`). Inlining rationale text into `git commit -m "..."` is forbidden.
- [ ] **Public-history disclaimer** (Security Considerations § Visibility-boundary binding): `/scope` v1 binds to public-repo tactical chains exclusively; any rejection rationale becomes part of the repository's permanent git history. The Phase-N Reject prompt's literal text (shipped by <<ISSUE:3>> and <<ISSUE:5>>) includes the substring "Rationale will be committed to git history"; Phase 3 documents this contract for traceability.
- [ ] **Closed write-target set** (Security Considerations § Filesystem-write boundaries) documents the enumerated set of write targets Phase 3 may touch:
    - `docs/decisions/DECISION-{prd|design}-<topic>-{re-evaluation|rejection}-<YYYY-MM-DD>.md`
    - `docs/{briefs,prds,designs}/{BRIEF,PRD,DESIGN}-<topic>.md` (force-materialization only, on abandonment-forced exit)
    - `wip/scope_<topic>_*` (state file + ancillary)
  Writes outside this set fail the R9 hard-finalization check.
- [ ] **State-file enum re-validation** (Security Considerations § Filesystem-write boundaries): before constructing Decision Record paths via interpolation, `boundary:` is validated against `{prd, design}`, `decision_record_sub_shape:` against `{re-evaluation, rejection}`, `triggering_child:` against `{brief, prd, design, plan}`, `plan_execution_mode:` against `{single-pr, multi-pr}`. Out-of-enum values fail finalization and route to R8 bail-handling.
- [ ] Cites Interface I.2 from the design and `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md` (R9 hard-finalization spec).

### Phase 4 — `skills/scope/references/phases/phase-4-cleanup.md`

- [ ] File exists at `skills/scope/references/phases/phase-4-cleanup.md`.
- [ ] Documents that Phase 4 runs ONLY after Phase 3's R9 hard-finalization check has passed.
- [ ] Documents the `wip/` cleanup invariant: remove `wip/scope_<topic>_state.md` and any `wip/scope_<topic>_*` ancillary files. The terminal artifact (PLAN / Decision Record / force-materialized child doc) remains on disk.
- [ ] Documents that Phase 4 does NOT remove `wip/{brief,prd,design,plan}_<topic>_*` or `wip/research/{prd,design}_<topic>_*` — these are owned by the child skills and removed by the child's own cleanup (or by the Phase-N Reject branch's discard handling per <<ISSUE:3>> / <<ISSUE:5>>).
- [ ] Documents that Phase 4's removal set is part of the closed write-target enumeration (read-back from Phase 3's documented set).
- [ ] Documents that Phase 4 emits a single-line success summary naming the terminal artifact path and the `exit:` value.

### Cross-file requirements

- [ ] All five files use the same heading discipline as the existing `skills/charter/references/phases/phase-*.md` files (Markdown `#` for title, `##` for major sections, `###` for sub-sections; prose at 65-72 char wrap).
- [ ] No reference to private repos, internal resources, or pre-announcement features (shirabe is a public repo).
- [ ] No reference to any `wip/...` path from a *committed final artifact* perspective — references to `wip/scope_<topic>_*` as a runtime concern are permitted (the workflow operates on these files); the wip-hygiene rule applies to durable artifacts citing wip paths, not phase references documenting the workflow's runtime substrate.
- [ ] Markdown lints clean per repo conventions; no emojis; no AI attribution lines.
- [ ] Must deliver: five phase reference files at the documented paths (required by <<ISSUE:13>>'s eval scenarios; required by <<ISSUE:10>>'s SKILL.md Phase Execution citations).
- [ ] Tests pass (`go test ./...` in repo root; CI green).
- [ ] Security review completed.

## Validation

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# 1. All five phase reference files exist.
for phase in phase-0-setup phase-1-discovery phase-2-chain-orchestration phase-3-exit-finalization phase-4-cleanup; do
  test -f "skills/scope/references/phases/${phase}.md" || {
    echo "FAIL: missing skills/scope/references/phases/${phase}.md"
    exit 1
  }
done

# 2. Phase 0 carries the slug regex and self-heal contracts.
grep -q '\^\[a-z0-9-\]\+\$' skills/scope/references/phases/phase-0-setup.md
grep -qi 'parent_orchestration' skills/scope/references/phases/phase-0-setup.md
grep -qi 'self-heal\|self heal' skills/scope/references/phases/phase-0-setup.md

# 3. Phase 1 carries the literal chain-proposal substrings and the R6 walk.
grep -q 'Proceed' skills/scope/references/phases/phase-1-discovery.md
grep -q 'Adjust' skills/scope/references/phases/phase-1-discovery.md
grep -q 'Bail' skills/scope/references/phases/phase-1-discovery.md
grep -qi 'P1\|predicate' skills/scope/references/phases/phase-1-discovery.md
grep -qi 'auto-skip\|chain_skipped' skills/scope/references/phases/phase-1-discovery.md

# 4. Phase 2 carries the sentinel write/clear + git log + validator.
grep -q 'parent_orchestration' skills/scope/references/phases/phase-2-chain-orchestration.md
grep -qi 'git log' skills/scope/references/phases/phase-2-chain-orchestration.md
grep -qi 'shirabe validate' skills/scope/references/phases/phase-2-chain-orchestration.md
grep -qi 'discard' skills/scope/references/phases/phase-2-chain-orchestration.md
grep -qi 'worktree' skills/scope/references/phases/phase-2-chain-orchestration.md

# 5. Phase 3 carries the three exits, the R8 tie-break, the HTML-comment marker.
grep -q 'full-run' skills/scope/references/phases/phase-3-exit-finalization.md
grep -q 're-evaluation' skills/scope/references/phases/phase-3-exit-finalization.md
grep -q 'abandonment-forced' skills/scope/references/phases/phase-3-exit-finalization.md
grep -q 'scope-status-block: abandonment-forced' skills/scope/references/phases/phase-3-exit-finalization.md
grep -qi 'most-recently-running\|most recently running' skills/scope/references/phases/phase-3-exit-finalization.md
grep -qi 'git commit -F\|git commit.*stdin\|commit -F' skills/scope/references/phases/phase-3-exit-finalization.md
grep -q 'Rationale will be committed to git history' skills/scope/references/phases/phase-3-exit-finalization.md

# 6. Phase 4 documents the wip cleanup set.
grep -qi 'wip/scope_' skills/scope/references/phases/phase-4-cleanup.md

# 7. No emojis (basic check on UTF-8 emoji presence in the BMP supplementary planes).
if grep -Pn '[\x{1F300}-\x{1FAFF}]|[\x{2600}-\x{27BF}]' skills/scope/references/phases/phase-*.md; then
  echo "FAIL: emoji detected in phase reference files"
  exit 1
fi

# 8. No AI attribution lines.
if grep -qi 'co-authored-by:.*claude\|generated with claude' skills/scope/references/phases/phase-*.md; then
  echo "FAIL: AI attribution line detected"
  exit 1
fi

echo "All validations passed"
```

## Security Checklist

- [ ] **Slug re-validation on resume** is documented in `phase-0-setup.md` as an unconditional check before any slug recovered from an on-disk artifact path enters shell interpolation. Phase 0's wording matches the Security Considerations § Command injection — slug re-validation contract.
- [ ] **Stale `parent_orchestration:` self-heal** is documented in `phase-0-setup.md` as unconditional, silent, and required on every session start. The wording rules out conditional self-heal (e.g., "if author confirms") and prompt-on-clear behavior.
- [ ] **Closed write-target set** is enumerated in `phase-3-exit-finalization.md` and read-back by `phase-4-cleanup.md`. Writes outside the enumerated set fail R9.
- [ ] **State-file enum re-validation** is documented in `phase-3-exit-finalization.md` before path interpolation. Enums covered: `boundary`, `decision_record_sub_shape`, `triggering_child`, `plan_execution_mode`.
- [ ] **`git commit -F` discipline** is documented in `phase-3-exit-finalization.md` covering all author-supplied free-form strings written to commits. Phase 2's worktree-staleness "Proceed anyway" rationale and Phase 2/3's rejection rationale both fall under this discipline.
- [ ] **Public-history disclaimer** is documented in `phase-3-exit-finalization.md` with the literal substring "Rationale will be committed to git history" for the in-chain rejection path's traceability.
- [ ] No phase reference invents a new write target outside the closed set documented in Phase 3.
- [ ] No phase reference invents a new code execution surface beyond `git` commands and `shirabe validate`.

## Dependencies

Blocked by <<ISSUE:10>>, <<ISSUE:3>>, <<ISSUE:5>>.

- <<ISSUE:10>> ships `skills/scope/SKILL.md`. The phase references are cited from SKILL.md's Phase Execution list; the phase references in turn cite SKILL.md's section names. Landing SKILL.md first establishes the citation surface.
- <<ISSUE:3>> ships `/prd` Phase 4 step 4.5 (the 3-option Approved/Reject/Continue-revising gate plus the discard-commit shape `docs(prd): discard PRD draft for <topic>`). Phase 2's `git log`-based discard-commit observation relies on the commit shape this issue defines.
- <<ISSUE:5>> ships `/design` Phase 6 step 6.7 (symmetric to <<ISSUE:3>>, with the discard-commit shape `docs(design): discard DESIGN draft for <topic>`). Phase 2's discard-commit observation for the DESIGN boundary relies on this commit shape.

## Downstream Dependencies

- <<ISSUE:13>> — the eval suite at `skills/scope/evals/evals.json` exercises eleven scenarios that read against contracts documented in these phase references (R6 walk verdicts, chain-proposal substring contract, HTML-comment marker uniformity, refuse-and-redirect substring contract, slug re-validation on resume, Phase-N Reject observability). The phase reference files are the contract surface the eval scenarios assert against; without them the evals cannot grade.
