# Decision 1 Research: Shared parent-skill reference location

## Research conducted

- Read `docs/designs/DESIGN-shirabe-progression-authoring.md`
  (Decision Driver 1, system boundaries, Open Questions).
- Read relevant sections of
  `docs/prds/PRD-shirabe-charter-skill.md` (R1, R9, R10, R11, R14,
  Out of Scope, Questions Deferred to Design, Known Limitations).
- Inventoried the top-level `references/` directory: 7 files
  (`cross-repo-references.md`, `decision-block-format.md`,
  `decision-presentation.md`, `decision-protocol.md`,
  `decision-report-format.md`, `pipeline-model.md`,
  `wip-hygiene.md`).
- Inventoried the discover/converge engine at
  `skills/explore/references/phases/`: 14 phase files including
  `phase-2-discover.md` (174 lines), `phase-3-converge.md` (205
  lines), `phase-5-produce-*.md` family.
- Inventoried every shipped skill that has a "discover" phase:
  `/explore`, `/prd`, `/vision`, `/roadmap`, `/strategy` -- five
  skills, each with its own `phase-2-discover.md` (or
  `phase-1-discover.md` for `/strategy`).
- Diff'd `/prd`'s `phase-2-discover.md` against `/explore`'s:
  files differ in lead format, role selection, output filename
  conventions, and round-tracking. Not identical; not a verbatim
  re-export.
- Grepped for cross-skill consumption: NO shipped skill loads
  `skills/explore/references/phases/phase-2-discover.md` from
  outside `skills/explore/`. The only references to that path
  are in `docs/briefs/`, `docs/designs/current/` (planning
  documents about modifying it), and `docs/prds/` (deferred
  questions about its location).
- Grepped for shared-reference loading patterns: skills use
  `${CLAUDE_PLUGIN_ROOT}/references/<file>.md` as the canonical
  pattern (`design/SKILL.md:51`, `design/references/phases/
  phase-4-architecture.md:90`, `plan/references/phases/
  phase-7-creation.md:350,372`, `roadmap/references/roadmap-format.md:43`,
  `strategy/references/strategy-format.md:46`, `vision/references/
  phases/phase-3-draft.md:90`, multiple eval files). Bare
  `references/decision-protocol.md` also works inside SKILL.md
  prose because the loader resolves relative paths from the
  skill's location.

## Findings

### Finding 1: The "engine" is conceptual, not physical

Despite the framing as a "discover/converge engine," there is no
shared physical file that the five existing skills consume. Each
skill ships its own `phase-2-discover.md`, customized to its
artifact type (PRD picks user/codebase/UX roles; VISION picks
strategic roles; ROADMAP picks dependency-graph roles). The
phrase "engine extraction" presupposes a code-reuse story that
does not match the current codebase.

What IS shared across these skills is the **mental model**: scope
-> diverge (research leads) -> converge (synthesis) -> draft.
That mental model lives implicitly in the SKILL.md template and
in shirabe's `pipeline-model.md`. No one consumes a single
discover.md file across skills.

### Finding 2: Top-level `references/` is the established home for cross-skill shared content

Every reference in the top-level `references/` directory today is
cross-skill content: `decision-protocol.md` is cited by
`/explore`, `/design`, `/decision`, `/prd`, `/plan`, `/work-on`.
`cross-repo-references.md` is cited by `/design`, `/plan`,
`/roadmap`, `/strategy`. `pipeline-model.md` is the workflow
overview cited from CLAUDE.md and multiple skills. These
references are SMALL (under 200 lines each), bounded, and
content-stable -- they describe contracts and conventions, not
phase prose.

The pattern is consistent: when content is shared across skills,
it lives at top-level `references/` and is loaded via
`${CLAUDE_PLUGIN_ROOT}/references/<file>.md`. When content is
phase prose specific to one skill, it lives at
`skills/<skill>/references/phases/<file>.md`.

### Finding 3: `/charter`'s own Phase 1 is bespoke, not a verbatim engine consumer

`/charter`'s PRD requirements for Phase 1 (R4 thesis-shift
detection, R5 `/comp` invocation gating, R7 `/roadmap` invocation
conditions) bake `/charter`-specific decision points into the
discovery flow. `/charter` borrows the discover/converge MENTAL
MODEL but authors its own discovery prompts -- it does not
re-export `/explore`'s Phase 2 verbatim. The same will be true
for `/scope` and `/work-on`: each parent has its own discovery
shape.

This collapses sub-question (a). The "engine" is not a single
file to move; each parent ships its own discover phase prose.
What gets shared is the parent-skill CONTRACT (state schema,
resume ladder, child-doc inspection), not the engine.

### Finding 4: The PRD ships either way

`/charter`'s PRD §"Known Limitations" §2: "If the design team
moves it to a top-level `references/` directory, the `/charter`
SKILL.md reference path updates in a follow-on PR." The PRD does
not block on this decision -- `/charter` ships against the
current path (`skills/explore/references/phases/`) and a future
PR updates the path if the engine moves. This means the design
can commit to either location without holding `/charter` up.

## Assumptions made (--auto mode)

- **Assumption A1**: The pattern-level references the design
  introduces (`parent-skill-pattern.md`, `state-file-schema.md`,
  `resume-ladder-template.md`, `child-doc-inspection.md`) are
  NEW content the design authors, not re-exports of existing
  phase prose. If wrong: some of these may already exist as
  fragments in other skills and the "move" decision affects
  callers I haven't audited.
- **Assumption A2**: shirabe's loader resolves
  `${CLAUDE_PLUGIN_ROOT}/references/<file>.md` consistently
  whether the file is referenced from a SKILL.md, a phase file,
  or an eval. The empirical evidence (7+ files using this
  pattern across 5+ skills) supports this. If wrong: top-level
  extraction has a loader-mechanics risk I am ignoring.
- **Assumption A3**: `/scope` and `/work-on` (migration), when
  they ship, will each author their own Phase 1 discovery prose
  rather than load the engine cross-skill. This is consistent
  with every shipped shirabe skill that has a "discover" phase.
  If wrong: the "engine extraction" framing becomes more
  load-bearing than the empirical data suggests.

## Summary of the problem and critical unknowns

The decision is framed as "where does the engine live," but the
engine is a mental model spread across five skill-local
`phase-2-discover.md` files, none of which consume the others.
The real decision is **where does the NEW pattern-level shared
content the design introduces live**: at top-level `references/`
(matching the precedent for cross-skill shared content) or at
per-parent `skills/<parent>/references/` (matching the precedent
for skill-local phase prose).

Critical unknowns:
- None remaining for the new-content placement: top-level
  `references/` is the established convention for cross-skill
  shared content and the new files (parent-skill-pattern,
  state-file-schema, resume-ladder-template,
  child-doc-inspection) are the same shape -- bounded contract
  references shared by multiple consumers.
- For the engine extraction half of the decision, the unknown
  is whether the design team views the engine as eventually-to-
  be-extracted (and thus should be moved now to set the
  precedent) or as a non-extraction (and thus a no-op for v1).
  The empirical data suggests "no shipped consumer wants it
  cross-skill, so moving is premature." But this is a forward-
  looking judgment.
