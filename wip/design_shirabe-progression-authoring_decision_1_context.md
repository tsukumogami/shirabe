# Decision Context: Shared parent-skill reference location

## Question

Where do shared parent-skill references live -- including the
discover/converge engine currently at
`skills/explore/references/phases/{phase-2-discover,phase-3-converge}.md`
-- and what content lives at the shared location for the three
parent skills (`/charter`, `/scope`, future `/work-on` migration)?

## Complexity

Standard (Tier 3). Fast path: Phases 0, 1, 2, 6. No validator agents.

## Coupled sub-questions

(a) **Location of the discover/converge engine.** Stay at
`skills/explore/references/phases/` (cross-skill reference, status
quo) vs. move to top-level `references/` (signaling shared
infrastructure).

(b) **What other pattern-level references ship alongside.**
Candidates per coordinator brief:
- `references/parent-skill-pattern.md` (contract surface)
- `references/state-file-schema.md` (YAML schema, R9/R10/R11)
- `references/resume-ladder-template.md` (ladder ordering and
  child-snapshots semantics, R11)
- `references/child-doc-inspection.md` (R14 isolation rules)

Treat (a) and (b) as one decision: the location is the same problem
at different granularities. If the engine moves, the other shared
content moves with it; if it stays, the other content stays at
parent-specific reference paths.

## Constraints (from Decision Drivers)

- **Reuse-load-bearing.** Three parent skills (`/charter`,
  `/scope`, `/work-on` migration) inherit this location. The
  contract must be the same place all three parents reference, OR
  it must be location-agnostic so each parent can point wherever
  the engine actually lives.

- **Cross-skill reference precedent.** shirabe already has a
  top-level `references/` directory containing
  `cross-repo-references.md`, `decision-protocol.md`,
  `decision-block-format.md`, `decision-presentation.md`,
  `decision-report-format.md`, `pipeline-model.md`,
  `wip-hygiene.md`. These are content multiple skills share. The
  engine fits the same shape if moved.

- **`/explore` still uses the engine in its own context.** If
  moved, `/explore`'s reference paths must update. If kept,
  `/explore` references `skills/explore/references/phases/` and
  so do all parent skills.

- **`/charter`'s PRD §"Out of Scope"** explicitly defers the
  extraction location to design. Status quo (keep where it is) is
  the no-change path; the PRD ships `/charter` referencing the
  current path either way (per "Known Limitations" §2:
  "No automatic engine extraction. ... If the design team moves
  it to a top-level `references/` directory, the `/charter`
  SKILL.md reference path updates in a follow-on PR.").

## Empirical findings from codebase audit

- Every shipped skill that ships a "discover" phase
  (`/explore`, `/prd`, `/vision`, `/roadmap`, `/strategy`)
  maintains its OWN `references/phases/phase-{1,2}-{scope,
  discover}.md` file. The five files are NOT identical -- they
  diverge on lead format, role selection, output filename
  conventions, and round-tracking semantics.

- No shipped skill consumes
  `skills/explore/references/phases/phase-2-discover.md`
  cross-skill today. The "cross-skill reference" framing in the
  PRD describes a hypothetical, not an established precedent.

- shirabe's top-level `references/` directory contains
  cross-cutting content that ALL skills cite (decision protocol,
  wip-hygiene, pipeline-model, cross-repo references). These are
  smaller, well-bounded reference files.

- `/charter`'s own Phase 1 is bespoke (R4 thesis-shift detection,
  R5 `/comp` invocation gating, R7 `/roadmap` invocation
  conditions). It is not a verbatim consumer of `/explore`'s
  Phase 2 + Phase 3 -- it borrows the discover/converge mental
  model and authors its own discovery prompts.

## Known options (from coordinator brief)

1. **Status quo**: engine stays at
   `skills/explore/references/phases/`; pattern-level references
   live at `skills/<parent>/references/` per-parent. Each parent
   may import from `skills/explore/...` for the engine prose.

2. **Top-level extraction**: engine moves to
   `references/discover-converge-engine.md` (or similar); other
   pattern-level references (parent-skill-pattern, state-file
   schema, resume-ladder template, child-doc inspection) ship as
   top-level `references/*.md` files alongside the engine.

3. **Hybrid**: top-level for the contract-surface references
   (parent-skill-pattern, state-file schema, resume-ladder,
   child-doc inspection) which are NEW shared content the design
   creates, but engine stays at `skills/explore/...` because no
   shipped skill actually consumes it cross-skill today.

## Background

The design is **shared** across the parent-skill pattern's three
features. It commits to a parent-skill contract surface (state
schema, resume ladder, three exit paths, child-doc inspection
rules, CLAUDE.md surfacing, eval requirement) that downstream
parents inherit. Pattern-level shared content lives somewhere; the
question is where.

The driver tension: shared = move (DRY signal, clean abstraction);
status-quo = keep (no caller is broken, minimal blast radius,
honors PRD's "no automatic engine extraction" framing). The
hybrid splits the diff: top-level for NEW shared content the
design authors; per-skill or as-is for content already shipped
elsewhere.
