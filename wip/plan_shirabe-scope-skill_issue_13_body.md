---
complexity: testable
complexity_rationale: Two artifacts to produce — a JSON eval file with 11+ scenarios that must parse, name-prefix correctly, and cover six user stories plus targeted ACs; and a CLAUDE.md edit that mirrors a precedent section verbatim in shape. Verification is mechanical (JSON parse, grep for substrings and name prefixes, visual diff against the /charter precedent section), no runtime behavior change to test.
---

## Goal

Ship the eval surface and shirabe-CLAUDE.md surfacing that close out PR-4's verification loop for `/scope`:

1. Create `skills/scope/evals/evals.json` with at least eleven scenarios — 5 baselines copied-and-adapted verbatim from `skills/charter/evals/evals.json` (per Design Decision 4 — canonical shared baseline, copy-and-adapt-verbatim until a future $ref mechanism mechanically retrofits the baseline) plus 6+ user-story scenarios covering US-1 through US-6 from the PRD (one scenario per user story minimum, per AC24b).
2. Add a "Tactical Chain Entry: /scope" section to shirabe `CLAUDE.md` mirroring the existing "Strategic Chain Entry: /charter" section, surfacing the entry triggers from R17b ("specify a feature called X", "scope feature Y", "walk me through specifying Z", direct `/scope <topic>` invocation).

## Context

Design: `docs/designs/DESIGN-shirabe-scope-skill.md` (Phase C deliverables — eval suite; R17a/R17b CLAUDE.md surfacing).

PRD: `docs/prds/PRD-shirabe-scope-skill.md` (R18 pattern-level eval requirement; AC24b per-user-story coverage; R17a/R17b/AC24a CLAUDE.md surfacing requirement).

This issue is the last of PR-4 and the closing surface of `/scope` v1: it makes the skill body discoverable through the same CLAUDE.md channels that surface `/charter` today, and it ships the eval suite that operationalizes the six user stories as automated checks (R18). The eval baselines (5 scenarios) are copied verbatim from `/charter`'s suite per Decision 4's canonical-shared-baseline contract — they cover slug rejection, malformed state, child-internals isolation, visibility default, team-lead discipline loop ordering, and default-option wording, with names rewritten from `baseline-...` to `baseline-...` (identical name) and prompts rewritten from `/charter` to `/scope` and from STRATEGY/VISION/ROADMAP paths to BRIEF/PRD/DESIGN/PLAN paths.

The 6 user-story scenarios are scope-specific and cover the six user stories from the PRD's User Stories section: US-1 (cold standalone full-run including BRIEF + PRD + DESIGN + PLAN), US-2 (Accepted PRD auto-skips `/brief`), US-3a (re-evaluation at PRD boundary), US-3b (re-evaluation at DESIGN boundary), US-4 (PRD rejection via re-evaluation exit's rejection sub-shape), US-5 (mid-chain abandonment forcing materialization), US-6 (reviewer redirect via manual fallback).

Beyond the per-US-1-to-6 minimum, the design's eval surface (line 217) notes additional Phase C eval coverage targets — AC30c (Phase-N Reject in-chain vs out-of-chain), AC13 (abandonment-forced HTML-comment marker uniformity across artifact types), AC18a/AC18b (drift-detection three-option prompt vocabulary), AC17c (refuse-and-redirect literal substring contract for PLAN-Active and PLAN-Done), and the Security Considerations slug re-validation on resume. These can fold into the eleven minimum scenarios as targeted expectations within the US-based scenarios where the contract surfaces, or as additional scenarios if the suite grows beyond eleven; the floor is eleven scenarios with at least one per user story.

The shirabe `CLAUDE.md` edit mirrors the existing Strategic-Chain-Entry section's shape: it lists the trigger utterances, names direct-invocation syntax with the topic-slug regex pattern, and notes that child skills (`/brief`, `/prd`, `/design`, `/plan`) remain directly invocable. The PRD names this section title verbatim ("Tactical Chain Entry: /scope") as a contractual requirement.

NOTE: the DESIGN status flip from Accepted → Planned (`docs/designs/DESIGN-shirabe-scope-skill.md` frontmatter) is a Phase 7 effect of this /plan workflow and is NOT shipped by this issue.

## Acceptance Criteria

### Eval suite

- [ ] `skills/scope/evals/evals.json` exists, parses as valid JSON, and contains `skill_name: "scope"` plus a `description` field naming the canonical-shared-baseline rationale (per Design Decision 4) and the user-story coverage commitment (per R18 / AC24b)
- [ ] The `evals` array contains at least eleven scenarios; first scenarios use the `baseline-` name prefix and appear first in the array; user-story scenarios use the `us-` name prefix and follow (mirrors `/charter`'s ordering convention)
- [ ] At least 5 scenarios share `baseline-` name prefixes copied-and-adapted from `/charter`'s `baseline-slug-rejection`, `baseline-malformed-state`, `baseline-child-internals-isolation`, `baseline-visibility-default`, `baseline-team-lead-discipline-loop-ordering`, and `baseline-default-option-wording` — adapted means prompts read `/scope` not `/charter` and reference BRIEF/PRD/DESIGN/PLAN paths not STRATEGY/VISION/ROADMAP paths
- [ ] At least one scenario per user story US-1, US-2, US-3a, US-3b, US-4, US-5, US-6 exists, with name prefix `us-` and the relevant US ID embedded in the name (e.g., `us-1-cold-standalone-full-run`, `us-2-prd-auto-skip-brief`)
- [ ] Each scenario specifies `id`, `name`, `prompt`, `expected_output`, `files`, and `expectations` fields (per `/charter`'s suite structure)
- [ ] Each scenario's `expectations` array contains 4 or more atomic checks (single-claim sentences) describing what the plan/Skill MUST do; expectations are observable through grep, file existence, or substring assertions, NOT through subjective adjectives
- [ ] At least one US-5 (or sibling) scenario tests that the force-materialized artifact's HTML-comment marker reads `<!-- scope-status-block: abandonment-forced; triggering-child: <name>; partial-phase-reached: <phase>; chain-started: <ISO-8601 timestamp> -->` (note the `scope-status-block:` prefix, not `charter-status-block:`), inside the host artifact's existing Status section
- [ ] At least one US-3a or US-3b scenario verifies the entry prompt contains the literal substring "Re-evaluate / Revise / Bail" (case-insensitive) AND MUST NOT contain "Continue / Start fresh"
- [ ] At least one scenario (US-2 or a dedicated PLAN-state scenario) verifies AC17c: when PLAN is Active, the prompt contains the literal substring "redirect to /work-on" (case-insensitive); when PLAN is Done, it contains "redirect to /release"; neither case fires the "Re-evaluate / Revise / Bail" triad
- [ ] At least one scenario (US-6 or sibling) verifies AC18a/AC18b drift detection: when `child_snapshots.<child>.status` OR `child_snapshots.<child>.content_hash` differs from the live value, the three-option staleness prompt surfaces with Re-run / Accept / Proceed-without wording
- [ ] At least one US-4 (or sibling) scenario verifies AC30c: when `/prd` or `/design` Phase-N Reject fires OUTSIDE `/scope`, no rejection Decision Record is retroactively written on later `/scope` resume — the discard commit is the durable trace
- [ ] `scripts/run-evals.sh scope` runs all scenarios; all assertions pass before the issue is closed (per CLAUDE.md "Skill Evals" section's authoring convention)

### Shirabe CLAUDE.md tactical-chain entry section

- [ ] `CLAUDE.md` at the shirabe-repo root contains a new section titled `## Tactical Chain Entry: /scope` (heading-2 level) placed immediately after the existing `## Strategic Chain Entry: /charter` section (preserving ordering: VISION/STRATEGY/ROADMAP entry → strategic-chain entry → tactical-chain entry)
- [ ] The new section's prose mirrors the existing "Strategic Chain Entry: /charter" section's shape: opening paragraph names `/scope` as a parent skill walking the tactical chain (BRIEF → PRD → DESIGN → PLAN) and holding state across child boundaries; second paragraph lists trigger utterances using the bullet shape from R17b ("specify a feature called X", "scope feature Y", "walk me through specifying Z"); third paragraph names direct-invocation syntax `/scope <topic-slug>` with the regex `^[a-z0-9-]+$`; closing paragraph notes that child skills `/brief`, `/prd`, `/design`, and `/plan` remain directly invocable
- [ ] The trigger-utterance bullet list contains each phrase from R17b verbatim — `grep -q '"specify a feature called X"' CLAUDE.md`, `grep -q '"scope feature Y"' CLAUDE.md`, and `grep -q '"walk me through specifying Z"' CLAUDE.md` all return 0
- [ ] The section's closing line names the child skills `/brief`, `/prd`, `/design`, and `/plan` (all four named, in chain order)
- [ ] No other content in `CLAUDE.md` is modified beyond the new section addition

### Verification (no DESIGN status flip)

- [ ] `docs/designs/DESIGN-shirabe-scope-skill.md` frontmatter `status:` remains `Accepted` after this issue ships (the flip to `Planned` is Phase 7 of this /plan workflow, NOT this issue's responsibility)
- [ ] CI green (existence check `scripts/check-evals-exist.sh` passes for `scope`; CLAUDE.md edits do not regress any structural validators)

## Dependencies

Blocked by <<ISSUE:10>>, <<ISSUE:11>>, <<ISSUE:12>>.

- <<ISSUE:10>> ships `skills/scope/SKILL.md` (the eval scenarios reference SKILL.md prose; without it the assertions have nothing to verify against).
- <<ISSUE:11>> ships the phase references (Phase 1 discovery / Phase 2 chain orchestration / Phase 3 finalization / resume ladder); several US scenarios assert behavior documented in those phase references.
- <<ISSUE:12>> ships the four Decision Record templates; the US-3a / US-3b / US-4 scenarios assert the templates' five-section ADR-style shape.

## Downstream Dependencies

None — this is the closing leaf issue of PR-4. After it ships, PR-4 squash-merges and the /plan workflow's Phase 7 status flip (DESIGN Accepted → Planned) runs as a separate, downstream effect of the /plan run that produced this issue.
