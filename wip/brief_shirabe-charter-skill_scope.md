# Brief Scope: shirabe-charter-skill

## Topic

`shirabe-charter-skill` — the `/charter` strategic-progression parent skill that orchestrates the strategic chain (optional vision-update → optional `/comp` → required `/strategy` → optional `/roadmap`) and enforces the three-rule terminal-artifact contract.

## Visibility

Public (shirabe repo). The motivating upstream STRATEGY is private and must be referred to by name only, never by `docs/strategies/...` path.

## Problem framing (ratified Phase 1)

shirabe authors today have no parent skill that walks them through a strategic conversation as a sequenced chain. Each of the four children exists or is in flight, but invoking them sequentially is a manual discipline. The chain has no codification, no resume contract, and no terminal-artifact guarantees. Without a parent skill, the three-rule terminal-artifact contract and the three exit paths (full-run, re-evaluation, abandonment-forced) are unenforceable; the upstream STRATEGY's discipline-vs-artifact decoupling thesis depends on `/charter` existing to enforce them.

## User Outcome altitude (ratified Phase 1)

(a) User-experience altitude, mirroring the BRIEF-shirabe-strategy-skill exemplar. The three exit paths must appear in the outcome explicitly — the Re-evaluation Decision Record is the novel contribution that prevents every `/charter` run from being tempted into a STRATEGY revision when nothing changed.

## Scope exclusions (ratified Phase 1)

- `/scope` (SE7) and `/work-on` migration (SE8) — separate features; share the design doc but each ships its own brief.
- `/comp` (SE11) authoring itself — `/charter`'s consumption contract is in scope, but the skill body isn't.
- SE3 `/strategy` SKILL.md amendments — `/charter` consumes `/strategy` as-is; revisions are a separate PR.
- The koto amplifier-layer migration (SE8 dual-implementation move).
- SE9 redirect mechanism — manual fallback is first-class per the upstream STRATEGY's falsifiability direction.

## Scope nuance

The downstream design doc (`DESIGN-shirabe-progression-authoring.md` per the roadmap) is *shared* across SE4/SE7/SE8. The brief's scope is `/charter`; the design's scope is the parent-skill pattern. Note this constraint — design will be co-authored across features.

## Open Questions to surface

1. SE3 `/strategy` SKILL.md verification gap — actual implementation must be read before `/charter`'s `--upstream` contract is finalized.
2. `/comp` (SE11) ordering — does SE4 ship with `/comp` invocation as documented-but-disabled, or does SE11 land first?
3. Engine extraction location — `skills/_shared/` (new convention) vs keeping engine inside `skills/explore/references/`.
4. **Dual-implementation contract** — the shared design must commit to a logical contract that satisfies both SE4's wip/-based core-layer implementation AND SE8's eventual koto-based amplifier-layer implementation. Flagged as load-bearing for `/design`.

## Defer to /prd or /design

- wip-namespace asymmetry (`/charter` writes its own `wip/charter_*` AND child-skill handoff files like `wip/vision_*`) — correctness concern for `/prd`.
- SE8 back-compat scope on the shared design — `/design` territory.
- Variable-cardinality team-spawn — `/design` territory.

## Upstream evidence

SE4 exploration findings at `/home/dgazineu/dev/niwaw/tsuku/tsuku-3/.niwa/worktrees/vision-2e6c9420/wip/explore_se4-charter-tactical_findings.md` (private; read-only, never linked from the public brief).

## Journey entry-point candidates

- Standalone author invoking `/charter` cold for a new strategic conversation.
- `/charter` run ending in re-evaluation (existing STRATEGY holds; Decision Record produced).
- Mid-chain abandonment forcing materialization of the most-recent intermediate.
- Reviewer redirecting mid-chain via the manual-fallback path.

## Next

Phase 2: draft Problem Statement + User Outcome + Scope Boundary into `docs/briefs/BRIEF-shirabe-charter-skill.md`. Send to team-lead for framing checkpoint.
