---
complexity: testable
complexity_rationale: New documentation prose specifying four child-invocation decisions plus a user-facing prompt with literal-substring requirements; AC verification beyond CI requires file-presence and content-substring grep checks.
---

## Goal

Author `/charter`'s child-invocation decision logic for `/vision`, `/comp`, `/strategy`, and `/roadmap` plus the chain-proposal confirmation prompt with literal Proceed / Adjust / Bail options, completing the Phase 1 discovery prelude and shipping a new Phase 2 chain-orchestration reference file that documents the per-child invocation rules.

## Context

This issue implements `/charter`'s entry-router conclusion: once Phase 1 discovery (authored in <<ISSUE:3>>) has surfaced the discovery prelude — repo visibility, manual-fallback discipline, thesis-shift signal — `/charter` must decide which children to invoke and confirm the chain shape with the author before any child fires. Four invocation decisions converge here: `/vision` (conditional on R4 signals), `/comp` (conditional on R5 + R12 with degenerate-silence rule), `/strategy` (always; the load-bearing child), and `/roadmap` (conditional on R7 shape gates with handoff pre-population). Phase 1 then concludes with the chain-proposal confirmation prompt per R7.5.

Design: `docs/designs/DESIGN-shirabe-progression-authoring.md`

This issue authors against the following PRD section:

```
PRD R4 (/vision invocation), R5 (/comp degenerate-silence), R6 (/strategy three upstream shapes), R7 (/roadmap conditional + handoff pre-population), R7.5 (chain-proposal Proceed/Adjust/Bail)
```

The DESIGN's Decision 6 (Conditional Feeder Invocation Shape) names the three-condition gate every conditional child invocation MUST satisfy: parent-defined Phase 1 discovery signal fires, the feeder skill exists on disk, parent-defined visibility gate passes. `/comp`'s invocation logic is the first concrete consumer of this contract; the chain-orchestration prose cites `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` (authored in <<ISSUE:1>>) as the contract framing.

This issue extends `skills/charter/references/phases/phase-1-discovery.md` (created by <<ISSUE:3>>) with the chain-proposal confirmation prompt prose, and creates a new `skills/charter/references/phases/phase-2-chain-orchestration.md` for the per-child invocation logic.

### /vision invocation (R4)

`/charter` invokes `/vision` when EITHER signal is present:

- No Accepted/Active VISION exists at `docs/visions/VISION-<topic>.md` matching the chain's scope, OR
- The thesis-shift signal surfaced during Phase 1 discovery (the signal detection itself is authored by <<ISSUE:3>>; this issue consumes the surfaced signal).

The invocation passes only the topic slug — `/charter` does NOT pass an API-level "treat as revision" flag because `/vision` has no such API. `/vision`'s own Resume Logic detects the existing-VISION case if one is present at the published path; the parent's responsibility is only to fire the invocation when one or both signals hold.

### /comp invocation (R5 + R12)

`/charter` invokes `/comp` when ALL of the following hold (the three-condition gate per DESIGN Decision 6):

1. Repository visibility is Private (per Phase 1's `## Repo Visibility:` header detection authored by <<ISSUE:3>>),
2. `skills/comp/SKILL.md` exists on disk.

(The third condition — a parent-defined Phase 1 discovery signal — is satisfied implicitly by the visibility gate for `/comp` v1; the contract framing remains the three-condition gate per the pattern reference.)

In public repos OR when `/comp` is not yet shipped, `/charter` SHALL silently skip. The author MUST NOT see a "skill not yet shipped" message or any reference to competitive analysis in either Phase 1 discovery prose or the chain proposal output. The chain proposal output is byte-identical between public-repo invocations and private-repo-without-`/comp` invocations — both omit any `/comp`-related substring. This degenerate-silence shape ensures `/charter` v1 ships without coupling to `/comp`; when `/comp` lands, the integration is live with no `/charter`-side change.

Cite `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` (Conditional Feeder Invocation Shape section) as the contract framing.

### /strategy invocation (R6)

`/charter` ALWAYS invokes `/strategy` — it is the load-bearing child of the chain. The chain completes either at `/strategy`'s exit (no `/roadmap` warranted) or continues to `/roadmap`.

`/charter` passes `/strategy` one of three valid upstream shapes:

1. **Freeform topic string** — when no upstream artifact exists, `/charter` passes the topic slug with no path argument.
2. **VISION path** — when `/vision` ran in the chain OR when an existing Accepted/Active VISION was identified during discovery. This is `/strategy` Input Mode 3.
3. **PRD path** — when the chain operationalizes a feature PRD that exists at a discoverable path. This is also accepted by `/strategy` Phase 1.

`/charter` MUST NOT pass a STRATEGY path to `/strategy`. STRATEGY paths are `/strategy`'s lifecycle-verb mode (Input Mode 2), not the create-new mode, and the three valid upstream shapes are EXCLUSIVE of that mode.

### /roadmap invocation (R7)

`/charter` invokes `/roadmap` when ALL of the following hold:

1. The just-produced STRATEGY's Building Blocks section contains 3 or more blocks, AND
2. The STRATEGY's Coordination Dependencies section contains at least one non-empty entry that references another Building Block by name.

If only 1-2 Building Blocks exist, OR no Coordination Dependencies section is present, OR the Coordination Dependencies section contains no qualifying entries, `/charter` SHALL skip `/roadmap` and complete the chain at full-run with STRATEGY only.

When invoked, `/charter` SHALL pass `/roadmap` BOTH:

- `--upstream <strategy-path>` flag pointing at the just-produced STRATEGY. `/roadmap`'s Phase 3 writes this to ROADMAP frontmatter verbatim; the contract accepts the path with no basename enforcement.
- A pre-populated `wip/roadmap_<topic>_scope.md` file matching the schema `/roadmap` Phase 1 expects (Theme Statement, Initial Scope, Candidate Features, Dependency Sketch, Sequencing Constraints, Downstream Artifact State, Coverage Notes). This handoff causes `/roadmap` to skip its Phase 1, analogous to the existing `/explore` Phase 5 handoff pattern.

### Chain-proposal confirmation prompt (R7.5)

Phase 1 concludes with a **chain-proposal confirmation prompt** (the canonical term: **chain proposal output**) that names the chain shape derived from discovery and the three exit options. The prompt MUST contain the literal substrings "Proceed", "Adjust", and "Bail" (case-insensitive) as the three options.

The prompt MUST list, in order, the children `/charter` plans to invoke, skipping those determined by R4/R5/R7 not to fire. The example shape (which authoring prose should adopt as a template):

> Based on our conversation, here's the chain I propose: [skip `/vision` because <reason> | run `/vision`], run `/strategy`, [run `/roadmap` because <reason> | skip `/roadmap` because <reason>]. Proceed / Adjust chain / Bail?

"Adjust" routes the author back to Phase 1 discovery for chain-shape redirection (e.g., force `/vision` on, opt out of a child that would otherwise fire) BEFORE any child fires. The redirected discovery may surface signals that change the chain shape, after which the prompt re-fires.

"Bail" routes per R8's bail-handling rule: abandonment-forced when any wip state exists for the topic; clean cancel otherwise. The Bail routing implementation (R8's tie-break rule between abandonment-forced and clean-cancel) is OWNED by <<ISSUE:7>>; this issue authors the prompt option and forward-references that routing rule.

### Public-repo discipline

The public-repo silence rule is critical: in public-repo invocations, neither the chain-proposal output nor any Phase 2 invocation prose may leak the substrings "/comp", "competitive analysis", or "competitive framing". The chain-proposal output for a public-repo run is the same string as a private-repo-without-`/comp` run for the same topic.

## Acceptance Criteria

- [ ] `skills/charter/references/phases/phase-2-chain-orchestration.md` exists.
- [ ] `skills/charter/references/phases/phase-1-discovery.md` exists (from <<ISSUE:3>>) and is extended by this issue with the chain-proposal confirmation prompt prose.
- [ ] `phase-2-chain-orchestration.md` starts with a top-level `#` markdown heading naming the chain-orchestration scope.
- [ ] `phase-2-chain-orchestration.md` documents the `/vision` invocation rule: fires when EITHER (a) no Accepted/Active VISION exists at `docs/visions/VISION-<topic>.md`, OR (b) the thesis-shift signal surfaced in Phase 1 discovery.
- [ ] `phase-2-chain-orchestration.md` states that the `/vision` invocation passes only the topic slug (no API-level "treat as revision" signal).
- [ ] `phase-2-chain-orchestration.md` documents the `/comp` invocation rule: fires when ALL of (1) repository visibility is Private, (2) `skills/comp/SKILL.md` exists on disk.
- [ ] `phase-2-chain-orchestration.md` documents the `/comp` degenerate-silence rule: public-repo and private-repo-without-`/comp` invocations produce byte-identical chain-proposal output and silently skip the `/comp` step (no "skill not yet shipped" message, no reference to competitive analysis).
- [ ] `phase-2-chain-orchestration.md` cites `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` (Conditional Feeder Invocation Shape section) as the contract framing for `/comp`'s invocation gate.
- [ ] `phase-2-chain-orchestration.md` documents the `/strategy` invocation rule: ALWAYS fires (load-bearing child).
- [ ] `phase-2-chain-orchestration.md` documents the three valid upstream shapes for `/strategy`: freeform topic, VISION path (`/strategy` Input Mode 3), and PRD path.
- [ ] `phase-2-chain-orchestration.md` documents the exclusion: `/strategy` MUST NOT be passed a STRATEGY path (STRATEGY paths are `/strategy`'s Input Mode 2, not create-new).
- [ ] `phase-2-chain-orchestration.md` documents the `/roadmap` invocation rule: fires when ALL of (1) STRATEGY's Building Blocks section contains 3+ blocks, (2) STRATEGY's Coordination Dependencies section contains at least one non-empty entry referencing another Building Block by name.
- [ ] `phase-2-chain-orchestration.md` documents that when `/roadmap` fires, `/charter` passes BOTH `--upstream <strategy-path>` AND a pre-populated `wip/roadmap_<topic>_scope.md` file matching `/roadmap` Phase 1's expected schema.
- [ ] `phase-2-chain-orchestration.md` documents the `/roadmap` schema fields the handoff pre-populates: Theme Statement, Initial Scope, Candidate Features, Dependency Sketch, Sequencing Constraints, Downstream Artifact State, Coverage Notes.
- [ ] `phase-2-chain-orchestration.md` documents that when the `/roadmap` shape gates do not hold, `/charter` skips `/roadmap` and completes the chain at full-run with STRATEGY only.
- [ ] `phase-1-discovery.md` is extended with the chain-proposal confirmation prompt prose containing the literal substrings "Proceed", "Adjust", and "Bail" (case-insensitive).
- [ ] `phase-1-discovery.md` documents that the chain-proposal output lists the planned children in order, skipping those determined by R4/R5/R7 not to fire.
- [ ] `phase-1-discovery.md` documents the "Adjust" routing: returns the author to Phase 1 discovery for chain-shape redirection BEFORE any child fires.
- [ ] `phase-1-discovery.md` documents the "Bail" routing: routes per R8's bail-handling rule (abandonment-forced if any wip state exists; clean cancel otherwise) — implementation OWNED by <<ISSUE:7>>, this prose forward-references that issue.
- [ ] Public-repo discipline: neither `phase-2-chain-orchestration.md` nor `phase-1-discovery.md` contain prose that would surface "/comp", "competitive analysis", or "competitive framing" in a public-repo run. (The chain-orchestration prose may name the substrings for its own internal logic documentation, but the prompt-output prose MUST omit them when the visibility gate fails.)
- [ ] Content discipline: no private-repo references, no internal tooling names, no pre-announcement features.
- [ ] Must deliver: chain-proposal prompt prose names the "Bail" option and forward-references <<ISSUE:7>>'s tie-break rule (required by <<ISSUE:7>>).
- [ ] Must deliver: `phase-1-discovery.md` and `phase-2-chain-orchestration.md` document the behaviors evals will assert — vision invocation conditions, comp degenerate-silence, roadmap shape gates, chain-proposal substrings (required by <<ISSUE:9>>).

## Validation

```bash
#!/usr/bin/env bash
set -euo pipefail

# File presence
test -f skills/charter/references/phases/phase-2-chain-orchestration.md
test -f skills/charter/references/phases/phase-1-discovery.md

# Top-of-file H1 heading on the new file
grep -qE '^# ' skills/charter/references/phases/phase-2-chain-orchestration.md

# Chain-proposal substrings in phase-1-discovery.md (case-insensitive)
grep -qi 'proceed' skills/charter/references/phases/phase-1-discovery.md
grep -qi 'adjust' skills/charter/references/phases/phase-1-discovery.md
grep -qi 'bail' skills/charter/references/phases/phase-1-discovery.md

# /vision invocation rule
grep -qE '(VISION-<topic>|docs/visions/VISION|/vision)' skills/charter/references/phases/phase-2-chain-orchestration.md
grep -q 'thesis-shift' skills/charter/references/phases/phase-2-chain-orchestration.md
grep -q 'topic slug' skills/charter/references/phases/phase-2-chain-orchestration.md

# /comp degenerate-silence
grep -qE '(degenerate.silence|silently skip)' skills/charter/references/phases/phase-2-chain-orchestration.md
grep -q 'byte-identical' skills/charter/references/phases/phase-2-chain-orchestration.md
grep -q 'skills/comp/SKILL.md' skills/charter/references/phases/phase-2-chain-orchestration.md

# /strategy three upstream shapes
grep -qF 'three' skills/charter/references/phases/phase-2-chain-orchestration.md
grep -qE '(VISION path|PRD path|freeform topic)' skills/charter/references/phases/phase-2-chain-orchestration.md
grep -q 'load-bearing' skills/charter/references/phases/phase-2-chain-orchestration.md
grep -q 'MUST NOT' skills/charter/references/phases/phase-2-chain-orchestration.md

# /roadmap shape gates
grep -q 'Building Blocks' skills/charter/references/phases/phase-2-chain-orchestration.md
grep -q 'Coordination Dependencies' skills/charter/references/phases/phase-2-chain-orchestration.md
grep -qE '(--upstream|wip/roadmap_)' skills/charter/references/phases/phase-2-chain-orchestration.md
grep -q 'Theme Statement' skills/charter/references/phases/phase-2-chain-orchestration.md
grep -q 'Candidate Features' skills/charter/references/phases/phase-2-chain-orchestration.md

# Conditional Feeder Invocation Shape citation (from <<ISSUE:1>>'s pattern reference)
grep -q 'parent-skill-pattern.md' skills/charter/references/phases/phase-2-chain-orchestration.md

# Chain-proposal prompt: skip-listing discipline and Adjust routing prose
grep -q 'in order' skills/charter/references/phases/phase-1-discovery.md
grep -qE '(routes back to Phase 1|return to Phase 1|back to Phase 1)' skills/charter/references/phases/phase-1-discovery.md

echo "All validations passed"
```

## Dependencies

Blocked by <<ISSUE:3>>. Issue 3 creates `skills/charter/references/phases/phase-1-discovery.md` (with the Phase 1 discovery prelude — visibility detection, manual-fallback rule, thesis-shift signal detection); this issue extends the same file with the chain-proposal confirmation prompt prose and consumes the surfaced thesis-shift signal in the `/vision` invocation rule.

Issue 1's pattern reference `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` is cited transitively (via <<ISSUE:3>>'s dependency on <<ISSUE:1>>); the Conditional Feeder Invocation Shape section is the contract framing this issue's `/comp` rule cites.

## Downstream Dependencies

- <<ISSUE:7>> — exit-path orchestration owns the R8 tie-break that decides between abandonment-forced and clean-cancel when the chain-proposal "Bail" option fires. Deliverable: the chain-proposal prompt prose names the "Bail" option and forward-references <<ISSUE:7>>'s tie-break rule, so the prompt names exist at the surface <<ISSUE:7>> binds against.
- <<ISSUE:9>> — eval scenarios cover AC5, AC6, AC7, AC8, AC9, AC10, AC10b, AC10c, AC10d, AC10e, AC10f (vision invocation, comp degenerate-silence, strategy three-shapes, roadmap shape gates, chain-proposal substrings, Adjust routing, Bail routing). Deliverable: `phase-1-discovery.md` and `phase-2-chain-orchestration.md` document the per-rule behaviors so the eval scenarios have published prose to assert against.
