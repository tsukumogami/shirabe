---
complexity: critical
complexity_rationale: Most complex single behavior in /charter — 10-row first-match-wins ladder consulting multiple sources (state file + child docs + child wip/ artifacts) with dual-check drift detection (status OR git blob hash), status-aware re-entry suppression, malformed-state hard-error contract, and known /strategy asymmetry accommodation; critical-complexity for contract enforcement plus user-data-adjacent read paths.
---

## Goal

Implement `/charter`'s 10-row first-match-wins resume ladder per PRD R11, child-snapshot dual-check drift detection per R10 + R13 (status OR git blob hash; either differing fires drift), 7-day stale-session boundary per R16, status-aware re-entry suppression so a child's resume prompt cannot hijack `/charter`'s flow, malformed-state hard error with Discard recovery per R11 + AC20c, and R14 child-internals isolation as an acceptance criterion — with explicit accommodation of the known `/strategy` asymmetry (`wip/strategy_<topic>_discover.md` vs the documented `_scope.md`).

## Context

This issue ships the resume entry point for `/charter`. Resume is the single most complex behavior in the skill: a first-match-wins ladder consults the state file, child durable docs, and child `wip/` artifacts in a fixed precedence order, decides whether to start fresh / resume mid-chain / re-evaluate an Accepted upstream / force-materialize an in-flight child / hard-error on contract violation — and surfaces drift between recorded child snapshots and live child state so a downstream child whose upstream changed under it doesn't get silently treated as still-valid.

Design: `docs/designs/DESIGN-shirabe-progression-authoring.md`

This issue authors against the following design + PRD sections:

```
DESIGN Solution Architecture Component 4 (Shared resume-ladder template), Decision 3 (per-child snapshot dual-check drift detection), Decision 4 (R14 widening, child-internals isolation)
PRD R10 (child_snapshots schema), R11 (full resume ladder ordering), R13 (manual-fallback drift detection), R14 (child-internals isolation), R16 (7-day stale-session threshold)
ACs: AC16, AC17, AC18, AC18b, AC19, AC20, AC20b, AC20c, AC23, AC26d
```

The DESIGN's Component 4 names the universal meta-ladder that lives in `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md` (authored in <<ISSUE:1>>); rows 1-4 and 9-10 of `/charter`'s ladder inherit that meta-ladder unchanged, and rows 5-8 are `/charter`'s parent-specific body slots (status-aware re-entry slot, partial-child-run slots, feeder-doc-detected slot). The DESIGN's Decision 3 binds `/charter` to the doc-emitting-children drift surface from the per-parent surface table in `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md` (also <<ISSUE:1>>): drift detection consults frontmatter `status:` AND git blob hash of the child durable doc.

This issue authors `skills/charter/references/phases/phase-resume.md`. The state-file schema this ladder reads from is defined in <<ISSUE:5>>.

### The 10-row resume ladder (R11)

First-match-wins ordering, top to bottom. The ladder stops at the first row whose condition matches and takes that row's action.

```
1. state file malformed                                → Error + offer Discard
2. state file has exit field set                       → Offer revise-equivalent / start fresh based on exit type
3. state file exists, last_updated < 7d                → Resume at recorded phase_pointer
4. state file exists, last_updated ≥ 7d                → Offer Resume / Force-materialize / Discard
5. docs/strategies/STRATEGY-<topic>.md Accepted/Active → Offer "Re-evaluate" / "Revise" / "Bail"
6. docs/strategies/STRATEGY-<topic>.md Draft           → Offer "continue" / "start fresh"
7. wip/strategy_<topic>_discover.md exists             → Resume into /strategy
8. wip/vision_<topic>_scope.md exists                  → Resume into /vision
9. On branch related to topic                          → Resume at Phase 1
10. On main or unrelated branch                        → Start at Phase 0
```

Rows 1-4 and 9-10 inherit the universal meta-ladder from `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md` (cite by relative path in the prose). Rows 5-8 are `/charter`'s parent-specific body slots — the status-aware re-entry slot for an upstream STRATEGY (rows 5-6) and the partial-child-run slots / feeder-doc-detected slot (rows 7-8).

### Row 3 vs Row 4: the 7-day boundary (R16, AC16, AC17)

The 7-day stale-session boundary fires at `≥` 7 days from the state file's `last_updated` timestamp. Fixed in v1; not configurable.

- **Row 3 (`< 7d`)** resumes at the recorded `phase_pointer` without prompting "Force-materialize" or any other intervention prompt. The author sees `/charter` continue where it left off.
- **Row 4 (`≥ 7d`)** surfaces a three-option prompt: **Resume / Force-materialize / Discard**. This prompt fires on every invocation while the state remains stale (i.e., not advanced) until the author chooses. Selecting **Force-materialize** routes into the abandonment-forced exit path (logic owned by <<ISSUE:7>>; artifact authoring owned by <<ISSUE:8>>).

### Row 5: status-aware re-entry vocabulary (R11, AC18, PRD US-2)

When an Accepted or Active STRATEGY exists at `docs/strategies/STRATEGY-<topic>.md` and no state file exists for the current chain, the author has invoked `/charter <topic>` against a settled upstream. The entry prompt MUST contain the literal substrings (case-insensitive) **"Re-evaluate"**, **"Revise"**, and **"Bail"** as the three options. The prompt MUST NOT contain the substring "Continue / Start fresh" — that is `/strategy`'s status-aware re-entry vocabulary and would hijack `/charter`'s flow.

The wording "Do you want to revise?" is explicitly REJECTED by PRD US-2: a "Do you want to revise?" default biases every chain toward STRATEGY revision and destroys the discipline-vs-artifact decoupling that motivates `/charter`. The three options are co-equal — re-evaluation (write a re-evaluation Decision Record without re-running the child), revision (start a fresh chain that may produce a superseding STRATEGY), or bail (no-op exit).

### Row 7: known /strategy asymmetry (R11, AC26d, PRD Out-of-Scope)

`/charter`'s row 7 reads `wip/strategy_<topic>_discover.md` — NOT `_scope.md`. This is the known `/strategy` asymmetry: `/strategy`'s SKILL.md documents `_scope.md` as the Phase 1 scoping artifact name, but `/strategy`'s phase files actually write `_discover.md` when the discover phase runs. `/charter` accommodates the asymmetry: the ladder reads the artifact that exists on disk, not the artifact the documentation claims exists. This is explicitly allowed by R11 and PRD Out-of-Scope ("fix /strategy's `_discover.md` vs `_scope.md` asymmetry" is out of scope for this initiative).

### Row 2: exit-driven re-entry (R11)

When the state file has its `exit:` field set, the chain has already finalized. The action depends on the exit value:

- `full-run` → offer the row-5 "Re-evaluate / Revise / Bail" prompt (the chain's durable artifact is the STRATEGY, which is now Accepted/Active or about to be).
- `re-evaluation` → offer "Revise / Bail" (re-evaluation is itself a finalization; another re-evaluation would write a duplicate Decision Record).
- `abandonment-forced` → offer "start fresh" (the chain abandoned without producing a STRATEGY).

The exact prompt vocabulary for each exit value is authored by this issue alongside the row prose.

### Child-snapshot dual-check drift detection (R10, R13, AC19, AC23)

For each child in `planned_chain`, the state file's `child_snapshots` block records three fields per child (schema defined in <<ISSUE:5>>):

- `path` — the absolute or repo-relative path to the child's durable doc.
- `status` — the child doc's frontmatter `status:` value at snapshot time.
- `content_hash` — the git blob hash of the child doc body at snapshot time (computed via `git hash-object` or equivalent; **read-only** — no writes to git history or to the child doc).

On resume, the ladder compares BOTH live values against the snapshot:

1. Read the child doc's current frontmatter `status:`.
2. Compute the child doc's current `git hash-object` value.
3. **Drift fires when EITHER differs from the snapshot.**

AC19 is explicit about the dual check: blob-hash coverage matters precisely because frontmatter `status:` may stay `Draft` while the body is edited by hand outside the chain (PRD R13's manual-fallback case). Status alone is insufficient.

When drift fires, the ladder surfaces a **three-option staleness prompt**:

1. **Re-run** the downstream child (re-invoke the child, treat the upstream change as material),
2. **Accept** the downstream as still-valid (record acknowledgment in the state file; proceed),
3. **Proceed without** the downstream (skip the affected child for this chain).

The prose MUST cite `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md` (authored in <<ISSUE:1>>) for the contract framing — both the R14-widened isolation rule and the drift-detection semantics. Per the per-parent surface table in that reference, `/charter` binds to the doc-emitting-children surface: `frontmatter status: + git blob hash`.

AC23 forward-references this implementation: out-of-chain hand edits to a child doc trigger staleness detection on the next `/charter` resume. The user-facing prose that names "staleness" is authored in <<ISSUE:3>>'s `phase-1-discovery.md`; the implementation lives here.

### Malformed-state hard error (R11, AC20c)

When `wip/charter_<topic>_state.md` is unparseable (invalid YAML, missing the YAML opening fence), missing required fields for its recorded `phase_pointer`, or has an invalid `exit:` / `decision_record_sub_shape:` combination (e.g., `exit: re-evaluation` with no `decision_record_sub_shape:` set, or `decision_record_sub_shape:` set without `exit: re-evaluation`), `/charter` MUST surface a hard error naming the specific malformation AND offer **Discard** as a recovery path.

`/charter` MUST NOT silently fall through to Phase 0 (row 10) when the state file is malformed. Malformed state is a **contract violation surface**, not a missing-state surface — silently starting fresh would hide upstream chain corruption and risk wedging the topic across invocations. The error message MUST name the specific malformation so the author can decide whether to repair the state file by hand or accept Discard.

### Status-aware re-entry suppression (AC20)

When `/charter` invokes a child whose durable doc is already Accepted (e.g., re-invoking `/strategy` after the chain completes), the next prompt the author sees MUST be from `/charter`'s prompt vocabulary — NOT the child's own status-aware re-entry vocabulary. Concretely: the author MUST NOT see `/strategy`'s "Continue / Start fresh" prompt when `/charter` is orchestrating; the author MUST see `/charter`'s "Re-evaluate / Revise / Bail" prompt instead.

`/charter` decides upfront which re-entry path applies and signals the child accordingly. Two cases:

- **Re-evaluation exit chosen**: `/charter` writes the re-evaluation Decision Record WITHOUT invoking the child at all. The child's status-aware re-entry prompt never fires because the child is never invoked.
- **Fresh chain chosen** (Revise): `/charter` invokes the child with a signal that suppresses the child's status-aware re-entry (e.g., a topic slug whose existing doc is at Accepted status, but `/charter`-orchestrated re-entry is fresh; the child's SKILL.md must respect the parent's orchestration signal). The mechanism by which the signal is conveyed is specified in this prose so the child-side and parent-side contracts align.

AC20 is manual-review for the prompt-vocabulary check; the implementation discipline is recorded here so reviewers can verify by code-path inspection.

### R14 child-internals isolation (AC20b)

`/charter`'s decision logic depends ONLY on:

1. The child doc frontmatter `status:` value (read from the published path, e.g., `docs/strategies/STRATEGY-<topic>.md`),
2. The child doc git blob hash (computed via `git hash-object` against the same path),
3. `/charter`'s own state file at `wip/charter_<topic>_state.md`.

`/charter` MUST NEVER read:

- Child internal phase pointers,
- Child `wip/research/<child>_<topic>_phase<N>_*.md` files,
- Any child `wip/` intermediate beyond the partial-run detection patterns explicitly listed in rows 7-8 of the ladder (`wip/strategy_<topic>_discover.md`, `wip/vision_<topic>_scope.md`),
- Any other child-private state.

This is the R14 widening per Decision 4: the isolation rule extends beyond status to all child internals, with the explicit exception that detecting "a partial child run exists for this topic" is permitted via the named filename patterns in rows 7-8 (this is unavoidable for partial-run detection but is the minimum surface needed).

AC20b is manual-review and is verified by code-path inspection against this prose. The acceptance criterion below records the discipline so the reviewer has a published contract to inspect against.

### US-3a manual-fallback rejection: NOT retroactive (AC18b, PRD US-3a)

When `/strategy` Phase 5 fires Reject OUTSIDE a `/charter` chain (author invokes `/strategy` directly and the strategy is rejected), `/charter` MUST NOT retroactively write a rejection Decision Record on a later `/charter` resume against the same topic. The rejection sub-shape of the Decision Record is `/charter`-orchestrated only.

Manual-fallback rejection leaves only the discard commit as the durable trace, by design. The ladder's row 1 (malformed state) and row 10 (no state file) paths apply normally; nothing in the resume path attempts to reconstruct a Decision Record from external evidence.

### Forward-references

- **Force-materialize routing** (row 4): selecting Force-materialize routes into the abandonment-forced exit path. The exit-path orchestration is OWNED by <<ISSUE:7>>; the abandonment-forced artifact authoring (HTML-comment marker) is OWNED by <<ISSUE:8>>. This issue forward-references both.
- **Re-evaluation routing** (row 5): selecting Re-evaluate routes into the re-evaluation exit path (write Decision Record without invoking the child). The exit-path orchestration is OWNED by <<ISSUE:7>>; the re-evaluation Decision Record template is OWNED by <<ISSUE:8>>. This issue forward-references both.
- **Staleness detection user-facing prose** (AC23): the discovery-side prose that names out-of-chain edits and the staleness detection surface lives in `phase-1-discovery.md` (authored by <<ISSUE:3>>); the implementation lives here.

## Acceptance Criteria

- [ ] `skills/charter/references/phases/phase-resume.md` exists.
- [ ] `phase-resume.md` starts with a top-level `#` markdown heading naming the resume-ladder scope.
- [ ] `phase-resume.md` documents all 10 rows of the resume ladder in order (rows 1-10 named above), with each row's match condition AND action.
- [ ] Row 1 documents: state file malformed → hard error naming the specific malformation + offer Discard. MUST NOT silently fall through to Phase 0 (AC20c).
- [ ] Row 2 documents: state file `exit:` field set → exit-value-specific re-entry prompt (full-run → row-5 prompt; re-evaluation → "Revise / Bail"; abandonment-forced → "start fresh"). Forward-references <<ISSUE:7>> and <<ISSUE:8>>.
- [ ] Row 3 documents: state file `last_updated < 7d` → resume at recorded `phase_pointer` WITHOUT prompting Force-materialize or any other intervention prompt (AC16).
- [ ] Row 4 documents: state file `last_updated ≥ 7d` → surface three-option prompt "Resume / Force-materialize / Discard"; prompt fires on every invocation until author chooses; Force-materialize routes into abandonment-forced exit (forward-references <<ISSUE:7>> and <<ISSUE:8>>) (AC17).
- [ ] Row 5 documents: STRATEGY at `docs/strategies/STRATEGY-<topic>.md` Accepted or Active → entry prompt MUST contain the literal substrings (case-insensitive) "Re-evaluate", "Revise", and "Bail" (AC18).
- [ ] Row 5 prose MUST NOT contain the substring "Continue / Start fresh" inside the row-5 prose block (it is `/strategy`'s vocabulary and would hijack `/charter`'s flow) (AC18, AC20).
- [ ] Row 5 prose names that the "Do you want to revise?" default is explicitly rejected per PRD US-2 (cite the rationale: it biases every chain toward STRATEGY revision and destroys discipline-vs-artifact decoupling).
- [ ] Row 6 documents: STRATEGY Draft → "continue / start fresh" prompt (per the universal meta-ladder body slot).
- [ ] Row 7 documents reading `wip/strategy_<topic>_discover.md` (the `_discover.md` filename, NOT `_scope.md`) → resume into `/strategy` (AC26d). Prose explicitly notes the known `/strategy` asymmetry accommodation per PRD Out-of-Scope.
- [ ] Row 8 documents: `wip/vision_<topic>_scope.md` exists → resume into `/vision`.
- [ ] Row 9 documents: on a branch related to the topic → resume at Phase 1.
- [ ] Row 10 documents: on main or an unrelated branch → start at Phase 0.
- [ ] `phase-resume.md` cites `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md` (or equivalent relative path) as the pattern-level template that rows 1-4 and 9-10 inherit.
- [ ] `phase-resume.md` cites `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md` (or equivalent relative path) as the contract framing for drift detection and the R14-widened isolation rule.
- [ ] Drift detection prose documents the dual-check rule: drift fires when EITHER snapshot field (`status` OR `content_hash`) differs from the live child doc value (AC19).
- [ ] Drift detection prose documents the three-option staleness prompt: (1) Re-run, (2) Accept, (3) Proceed without — and that this is `/charter`'s response to drift (AC19).
- [ ] Drift detection prose documents that `content_hash` is the git blob hash computed via `git hash-object` (or equivalent) against the child doc, READ-ONLY (no writes to child docs or git history).
- [ ] Drift detection prose explains WHY the dual check is needed (status alone is insufficient because the body can be edited by hand while frontmatter `status:` stays Draft — the R13 manual-fallback case).
- [ ] Status-aware re-entry suppression: prose documents that when `/charter` invokes a child whose durable doc is already Accepted, the next prompt shown is from `/charter`'s prompt vocabulary (e.g., "Re-evaluate / Revise / Bail"), NOT from the child's own status-aware re-entry vocabulary ("Continue / Start fresh" or equivalent) (AC20).
- [ ] Status-aware re-entry suppression: prose documents the two cases — re-evaluation exit chosen (child never invoked) versus fresh chain chosen (child invoked with suppression signal) — and names the signal/contract by which `/charter` conveys suppression to the child.
- [ ] 7-day stale-session threshold prose: documents the `≥ 7d` boundary as fixed in v1 (not configurable) and that it gates rows 3 vs 4 (R16, AC17).
- [ ] R14 child-internals isolation: prose enumerates the three (and only three) sources `/charter`'s decision logic consults — (1) child doc frontmatter `status:`, (2) child doc git blob hash, (3) `/charter`'s own state file (AC20b, manual-review).
- [ ] R14 child-internals isolation: prose enumerates the prohibited sources — child internal phase pointers, child `wip/research/<child>_<topic>_phase<N>_*.md` files, any child `wip/` intermediate beyond the named patterns in rows 7-8 of the ladder (AC20b).
- [ ] US-3a manual-fallback rejection: prose documents that `/charter` does NOT retroactively write a rejection Decision Record on a later resume when `/strategy` Phase 5 Reject fired outside the `/charter` chain (AC18b).
- [ ] AC23 forward-reference: prose names that out-of-chain hand edits to child docs trigger drift detection on resume; cross-references that the user-facing staleness prose lives in `phase-1-discovery.md` (from <<ISSUE:3>>).
- [ ] Content discipline: no private-repo references, no internal tooling names, no pre-announcement features (public-repo discipline).
- [ ] Must deliver: ladder prose documents all 10 rows and their behaviors so eval scenarios in <<ISSUE:9>> can assert against AC16, AC17, AC18, AC18b, AC19, AC20, AC20b, AC20c, AC23, AC26d (required by <<ISSUE:9>>).
- [ ] Security review completed.

## Validation

```bash
#!/usr/bin/env bash
set -euo pipefail

# File presence
test -f skills/charter/references/phases/phase-resume.md

# Top-of-file H1 heading
grep -qE '^# ' skills/charter/references/phases/phase-resume.md

# Row 1: malformed-state hard error + Discard recovery
grep -qE '(malformed|Discard)' skills/charter/references/phases/phase-resume.md

# 7-day stale-session threshold (row 3 vs row 4 boundary)
grep -qE '(7.day|stale.session|>= 7d|≥ 7d)' skills/charter/references/phases/phase-resume.md

# Row 5 vocabulary (positive): "Re-evaluate" / "Revise" / "Bail"
grep -qE 'Re-evaluate' skills/charter/references/phases/phase-resume.md
grep -qE 'Revise' skills/charter/references/phases/phase-resume.md
grep -qE 'Bail' skills/charter/references/phases/phase-resume.md

# Row 5 vocabulary (negative): MUST NOT contain "Continue / Start fresh" inside the row-5 prose block.
# This is enforced as a top-level absence check across the file; the row-6 prose may discuss continue/start
# fresh for the Draft case but must not use the literal "Continue / Start fresh" hijacking string.
if grep -qE 'Continue / Start fresh' skills/charter/references/phases/phase-resume.md; then
  echo "ERROR: phase-resume.md contains forbidden substring 'Continue / Start fresh' (row 5 must use /charter vocabulary, not /strategy's hijacking vocabulary)" >&2
  exit 1
fi

# Row 7: known /strategy asymmetry accommodation (_discover.md, NOT _scope.md)
grep -qE '_discover\.md' skills/charter/references/phases/phase-resume.md

# Row 8: /vision wip artifact
grep -qE 'wip/vision_' skills/charter/references/phases/phase-resume.md

# Drift detection: child_snapshots schema fields and dual check
grep -qE '(drift|child_snapshots|content_hash|git blob hash)' skills/charter/references/phases/phase-resume.md
grep -qE '(git hash-object|hash-object)' skills/charter/references/phases/phase-resume.md

# Three-option staleness prompt
grep -qE '(Re-run|Accept|Proceed without)' skills/charter/references/phases/phase-resume.md

# Pattern-level reference citations (from <<ISSUE:1>>)
grep -q 'parent-skill-resume-ladder-template.md' skills/charter/references/phases/phase-resume.md
grep -q 'parent-skill-child-inspection.md' skills/charter/references/phases/phase-resume.md

# Status-aware re-entry suppression
grep -qE '(status.aware|suppress|hijack)' skills/charter/references/phases/phase-resume.md

# Force-materialize forward-references
grep -qE '(Force.materialize|abandonment.forced)' skills/charter/references/phases/phase-resume.md

# R14 child-internals isolation discipline
grep -qE '(R14|child.internals|isolation)' skills/charter/references/phases/phase-resume.md

# US-3a manual-fallback rejection: NOT retroactive
grep -qE '(manual.fallback|US-3a|retroactive)' skills/charter/references/phases/phase-resume.md

echo "All validations passed"
```

## Security Checklist

- [ ] Drift detection computes git blob hashes READ-ONLY via `git hash-object` (or equivalent); no writes to child docs, no writes to git history, no modifications to any path outside `/charter`'s own state file.
- [ ] Ladder reads only documented sources: `/charter`'s own state file at `wip/charter_<topic>_state.md`, child doc frontmatter at published paths (`docs/strategies/STRATEGY-<topic>.md`, etc.), and the two child `wip/` artifact filenames explicitly named in rows 7-8 (`wip/strategy_<topic>_discover.md`, `wip/vision_<topic>_scope.md`). No other child internals are consulted (R14).
- [ ] Malformed state file fails closed: hard error + Discard recovery, no silent fall-through to Phase 0. Prevents state confusion across topic invocations and prevents corrupt state from silently propagating into a fresh chain.
- [ ] Status-aware re-entry suppression prevents child prompts from hijacking `/charter`'s flow: the author always sees `/charter`'s prompt vocabulary when `/charter` is orchestrating, eliminating ambiguity between parent and child re-entry vocabularies.
- [ ] No third-party dependencies introduced; the ladder uses only `git hash-object` (or filesystem-native equivalent) plus filesystem reads.
- [ ] Child-snapshot data in the state file (path + status + content_hash) is metadata, NOT content — the state file MUST NOT copy any child-doc body content. This matters because feature branches with `wip/charter_<topic>_state.md` are visible during PR review; copied child-doc body content could leak pre-publication wording across review surfaces.
- [ ] 7-day stale-session threshold bounds the surface area for any concurrent edits — state older than 7 days requires explicit author intent (Resume / Force-materialize / Discard) before the chain advances, preventing indefinite resume on abandoned state.
- [ ] R14 child-internals isolation enforced as AC20b (manual-review); verified by code-path inspection against the prose enumerating the three permitted sources and the prohibited sources.
- [ ] US-3a manual-fallback rejection is not retroactive: `/charter` does not synthesize Decision Records from external evidence, preventing fabricated audit trails from manual-fallback paths.
- [ ] Security review completed.

## Dependencies

Blocked by <<ISSUE:5>>. Issue 5 defines the state file schema at `wip/charter_<topic>_state.md` (the 5-field minimum plus `/charter`-specific extensions including `planned_chain`, `chain_ran`, `chain_skipped`, `decision_record_sub_shape`, and the `child_snapshots` block); this issue's resume ladder reads from that schema and depends on the field names (`last_updated`, `phase_pointer`, `exit`, `decision_record_sub_shape`, `child_snapshots`) being defined.

Issue 1's pattern-level references are cited transitively (via <<ISSUE:5>>'s dependency on <<ISSUE:1>>): this issue's prose names both `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md` (rows 1-4 and 9-10 inherit the universal meta-ladder) and `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md` (contract framing for drift detection and the R14-widened isolation rule).

## Downstream Dependencies

- <<ISSUE:7>> — exit-path orchestration owns the routing for Force-materialize (row 4) into abandonment-forced and for Re-evaluate (row 5) into the re-evaluation exit path. Deliverable: this issue's ladder prose names "Force-materialize" and "Re-evaluate" as the entry points at the surface <<ISSUE:7>> binds against, and forward-references <<ISSUE:7>> for the routing implementation.
- <<ISSUE:8>> — exit-artifact authoring owns the abandonment-forced HTML-comment marker and the re-evaluation / rejection Decision Record templates. Deliverable: this issue's ladder prose forward-references the artifact names at the points where the row actions trigger them.
- <<ISSUE:9>> — eval scenarios cover AC16, AC17, AC18, AC18b, AC19, AC20, AC20b, AC20c, AC23, AC26d (row 3 < 7d resume, row 4 ≥ 7d three-option prompt, row 5 vocabulary substrings, row 5 negative substring "Continue / Start fresh", `_discover.md` accommodation, drift detection dual-check, three-option staleness prompt, malformed-state hard error, child-internals isolation, manual-fallback non-retroactivity). Deliverable: this issue's ladder prose documents all 10 rows and the drift-detection behavior so the eval scenarios have published prose to assert against.
