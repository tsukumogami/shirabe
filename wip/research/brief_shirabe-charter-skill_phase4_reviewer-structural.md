# Phase 4 Structural Review: brief_shirabe-charter-skill

## Verdict: PASS

The complete draft at `docs/briefs/BRIEF-shirabe-charter-skill.md`
(commit a287929) satisfies all six structural checks against the
`BRIEF-shirabe-strategy-skill.md` exemplar and the brief team-shape
spec's Phase 4 validation criteria.

## Check 1: Required Sections Present and Ordered — PASS

All eight required sections appear in the correct order:

| # | Required Section | Draft Line |
|---|---|---|
| 1 | Status | 27 |
| 2 | Problem Statement | 38 |
| 3 | User Outcome | 101 |
| 4 | User Journeys | 165 |
| 5 | Scope Boundary | 273 |
| 6 | Open Questions | 339 |
| 7 | Downstream Artifacts | 394 |
| 8 | References | 410 |

Section ordering matches the exemplar's
(`docs/briefs/BRIEF-shirabe-strategy-skill.md`) ordering exactly.

## Check 2: Frontmatter Schema Valid — PASS

Frontmatter (lines 1–23):
- `schema: brief/v1` — matches exemplar.
- `status: Draft` — within the allowed set
  (`Draft|Accepted|Active|Sunset`).
- `problem: |` — block scalar present with multi-line content
  (lines 4–13).
- `outcome: |` — block scalar present with multi-line content
  (lines 14–22).

Shape mirrors the exemplar's frontmatter exactly. No required keys
missing, no extraneous keys.

## Check 3: User Journeys Cover Distinct Entry Points — PASS

Four journeys, each with a distinct user, trigger, path through the
chain, and exit shape:

| Journey | User | Trigger | Chain Path | Exit Shape |
|---|---|---|---|---|
| 1 (line 171) | Skill author | Cold `/charter` invocation on a new strategic topic | Discovery → skip `/vision` → skip `/comp` (public) → `/strategy` → `/roadmap` | Full-run: Draft STRATEGY + ROADMAP |
| 2 (line 196) | Same author, six weeks later | Re-invokes `/charter` on existing Accepted STRATEGY topic | Discovery surfaces upstream → falsifiability claims hold → no children re-run | Re-evaluation: Decision Record only |
| 3 (line 221) | Skill author | Session breaks mid-chain; resumes after a week | Resume ladder detects partial state → force-materialize most-recent child | Abandonment-forced: Draft STRATEGY with abandonment-marker Status |
| 4 (line 246) | Reviewer (distinct actor) | Reads existing Draft STRATEGY, decides to tighten directly | Invokes `/strategy` standalone outside `/charter`; later resume warns of staleness without acting | Manual fallback: revised Draft STRATEGY, ROADMAP unchanged |

The four journeys map one-to-one onto the four scenarios the
team-shape spec enumerates: standalone cold full-run; re-evaluation
Decision Record exit; mid-chain abandonment forcing materialization;
reviewer redirecting via manual fallback outside `/charter`. No two
journeys share a trigger shape. Actor mix (3 author + 1 reviewer) and
exit-shape mix (4 distinct exits) confirm distinct entry-point
coverage rather than stylistic variations.

## Check 4: Scope Boundary Has Both Halves — PASS

- "Inside" half: introduced at line 278 with "The scope holds the
  following inside:" — followed by nine substantive bullet items
  covering SKILL.md, delegation contracts, exit paths, resume ladder,
  visibility model, shared design portions, engine-extraction
  consumption, CLAUDE.md updates, artifact-decision contract, and
  manual-redirect workflow.
- "Excluded" half: introduced at line 308 with "The scope explicitly
  excludes:" — followed by nine substantive bullet items covering
  `/scope` skill, `/work-on` migration, `/comp` SKILL.md body,
  `/strategy` revisions, amplifier-layer substrate, review-time
  redirect mechanism, niwa workspace context surface, migration of
  existing artifacts, and tone/style/substrate work.

Both dividers use the exemplar's exact phrasing ("The scope holds the
following inside:" / "The scope explicitly excludes:"). Both halves
are substantive — neither is a placeholder or a single-item list.

## Check 5: Open Questions Are Answerable by /prd or /design — PASS

All six questions are HOW-shaped (asking how `/charter` behaves
mechanically) rather than WHETHER-shaped (which would re-open
Problem Statement framing):

1. **`/strategy` SKILL.md verification** (line 344) — asks how the
   handoff contract reconciles if drifted. PRD-resolvable.
2. **`/comp` skill ordering** (line 352) — asks how to sequence
   `/comp` integration relative to `/charter` ship. PRD-resolvable.
3. **Engine extraction location** (line 363) — asks how directory
   layout should encode shared content. Design-resolvable.
4. **Dual-implementation contract** (line 372) — asks how the shared
   design's logical contract should be shaped. Design-resolvable.
5. **`/charter` auto-handoff from `/explore`** (line 382) — asks how
   integration timing with `/explore` should land. PRD-resolvable.
6. **Resume-ladder source of truth** (line 388) — asks how the resume
   ladder reads state. Design-resolvable.

None re-open the question of whether `/charter` should exist, whether
the three exit paths are the right ones, or whether the parent-skill
pattern is the right abstraction — those framings are committed in
the Problem Statement and User Outcome.

## Check 6: Public-Safety Scan — PASS

Verified the draft contains no:

- private repo paths (no `private/...`, no vision-repo paths)
- project codenames (no "shirabe-evolution")
- SE-prefix issue numbers (no "SE3", "SE4", "SE11", etc.)
- "upstream strategy commits to" / "the upstream strategy" framing
  that anchors to a private artifact

`grep -nE "shirabe-evolution|SE[0-9]+|private/|vision/wip|upstream
strategy commits|upstream strategy"` returned no matches.

Architectural pattern terms in use — *parent-skill pattern*,
*discipline-vs-artifact decoupling*, *terminal-artifact contract*,
*three exit paths*, *re-evaluation Decision Record exit*,
*abandonment-forced materialization* — are architectural language
established within the brief itself or in the exemplar's altitude
vocabulary, and are safe for a public-repo artifact.

## Issues

None. All six checks pass; the draft is structurally ready for
Phase 5 finalization.
