<!-- decision:start id="shared-parent-skill-reference-location" status="assumed" -->
### Decision: Shared parent-skill reference location

**Context**

The shirabe design `DESIGN-shirabe-progression-authoring` commits
to a parent-skill contract surface shared across three features:
`/charter` (the concrete consumer driving the design), `/scope`
(a parallel parent sibling), and the future `/work-on` migration.
Ten of `/charter`'s PRD requirements are tagged `[pattern-level]`
precisely because the same mechanics need to apply to all three
parents. Pattern-level shared content has to live somewhere; the
question is where.

The decision spans two coupled sub-questions. (a) Where does the
discover/converge engine -- currently at
`skills/explore/references/phases/{phase-2-discover.md,
phase-3-converge.md}` -- live? (b) Where do the NEW
pattern-level reference files the design introduces
(`parent-skill-pattern.md`, `state-file-schema.md`,
`resume-ladder-template.md`, `child-doc-inspection.md`) live?

An empirical audit of the codebase yielded two load-bearing
findings. First, every shipped shirabe skill with a "discover"
phase (`/explore`, `/prd`, `/vision`, `/roadmap`, `/strategy`)
ships its own variant of `phase-2-discover.md`; the files diverge
on lead format, role selection, and round-tracking. No skill
consumes another's engine cross-skill. The "engine" is a mental
model, not a physical shared file. Second, the top-level
`references/` directory is the established home for cross-skill
shared content: `decision-protocol.md`,
`cross-repo-references.md`, `pipeline-model.md`, and others are
loaded by skills via `${CLAUDE_PLUGIN_ROOT}/references/<file>.md`.
The pattern is consistent -- bounded, cross-cutting contract
references live at top-level; phase prose specific to one skill
lives under `skills/<skill>/references/phases/`.

**Assumptions**

- The pattern-level references the design authors
  (`parent-skill-pattern.md`, `state-file-schema.md`,
  `resume-ladder-template.md`, `child-doc-inspection.md`) are
  NEW content, not re-exports of existing phase prose. If wrong,
  fragments may already exist in other skills and the move
  affects callers not audited here.
- shirabe's loader resolves
  `${CLAUDE_PLUGIN_ROOT}/references/<file>.md` consistently
  whether referenced from a SKILL.md, a phase file, or an eval.
  Multiple shipped files use the pattern, so this is well-
  supported, but no end-to-end loader test was run as part of
  this decision.
- `/scope` and `/work-on` (migration), when bounded, will each
  author their own Phase 1 discovery prose rather than load the
  engine cross-skill. This matches every shipped shirabe skill
  with a discover phase. If wrong, "engine extraction" becomes
  more load-bearing than the empirical data suggests, and
  Alternative 2 strengthens.
- The decision is made in `--auto` mode without user
  confirmation; status is `assumed` per the decision-block
  threshold.

**Chosen: Hybrid -- top-level for new contract references; engine stays at skills/explore/**

Ship four NEW pattern-level reference files at top-level
`references/`:

| File | Content |
|------|---------|
| `references/parent-skill-pattern.md` | Contract-surface table of contents linking the schema, ladder, inspection rules, three exit paths, CLAUDE.md surfacing rule, eval requirement |
| `references/state-file-schema.md` | YAML schema for `wip/<parent>_<topic>_state.md` per R9, R10 (named fields `chain_started`, `planned_chain`, `chain_ran`, `chain_skipped`, `exit`, `decision_record_sub_shape`, `exit_artifacts`, `child_snapshots`) |
| `references/resume-ladder-template.md` | Ordered ladder per R11, child-snapshots semantics, multi-source consultation rules |
| `references/child-doc-inspection.md` | R14 isolation rules: frontmatter `status:` plus git blob hash, no reads of `wip/research/<child>_*.md` |

Parent skills load these via `${CLAUDE_PLUGIN_ROOT}/references/<file>.md`,
matching the existing convention used by `decision-protocol.md`,
`cross-repo-references.md`, `pipeline-model.md`, and others.

The discover/converge engine STAYS at
`skills/explore/references/phases/{phase-2-discover.md,
phase-3-converge.md}`. Each parent skill ships its OWN
`skills/<parent>/references/phases/phase-1-discovery.md` (or
similarly named) that authors the parent-specific discovery
prompts (e.g., `/charter`'s R4 thesis-shift detection prompt).
Where parents borrow the mental model, the parent's phase file
cites the `/explore` engine prose as "engine reference for the
discover-converge model" but does not require physical reuse.

**Rationale**

Three reasons drive this choice.

First, the top-level `references/` directory is the EMPIRICALLY
ESTABLISHED home for cross-skill shared content in shirabe. The
new pattern-level references are exactly that shape -- bounded,
contract-defining, shared by three consumers. Putting them
anywhere else creates a precedent inconsistency.

Second, the engine move is speculative work. Decision driver 1
("Discover/converge engine extraction") frames the question as
if there were cross-skill consumers waiting for the engine to be
liberated. The audit shows there are none: every shipped skill
with a discover phase ships its own variant, and `/charter`'s
own Phase 1 (R4, R5, R7) is bespoke. Moving the engine now ships
either a leaky shared file (the prose contains `/explore`-
specific filenames and round-tracking) or requires a refactor of
`/explore`'s phase prose that no current feature needs. Both are
out-of-scope cost for `/charter` v1.

Third, the PRD's framing is preserved. `/charter`'s PRD Out-of-
Scope §"The discover/converge engine extraction location" and
Known Limitations §2 explicitly note that `/charter` ships
against the current engine path and the path updates in a
follow-on PR if the engine moves. Choosing "engine stays" is the
non-blocking, PRD-aligned path. If a future feature DOES need
the engine cross-skill (e.g., a hypothetical `/scope` Phase 1
that imports the converge loop verbatim), that PR moves the
engine under load-bearing pressure.

The accepted trade-off: when `/scope` ships, its Phase 1 will
re-author discover/converge prose specific to scope's domain
instead of importing `/explore`'s file. That cost is the same as
every other shipped shirabe skill pays today (five skills, five
discover-phase files) -- accepting it for `/scope` and `/work-on`
is consistent, not regressive.

**Alternatives Considered**

- **Full top-level extraction (engine moves too).** Move
  `skills/explore/references/phases/phase-2-discover.md` and
  `phase-3-converge.md` to top-level `references/` (e.g.,
  `references/discover-converge-engine.md`), update `/explore`'s
  SKILL.md to reference the new location, and consider updating
  `/prd`, `/vision`, `/roadmap`, `/strategy` to consume it. Plus
  the same four new contract reference files at top-level.
  Rejected because the audit found no current cross-skill
  consumer of the engine, and the engine prose contains
  `/explore`-specific round-tracking and filenames that would
  either bleed into the "shared" file or require a refactor of
  `/explore`'s phase prose that no shipping feature needs. The
  move is speculative work; the PRD framing (follow-on PR when
  load-bearing pressure exists) is the better timing.

- **Status quo for everything (engine stays; new references
  ship per-parent).** Engine at current path; new pattern-level
  references shipped under `skills/<parent>/references/` per
  parent (three copies of `parent-skill-pattern.md` when
  `/charter`, `/scope`, and `/work-on` all ship). Rejected
  because it directly contradicts decision driver 14
  ("pattern-level references must be authored such that each
  parent cites them rather than re-implementing them") -- this
  alternative IS re-implementation. The whole reason the shared
  design exists is to prevent the fragmentation that three
  copies create.

**Consequences**

What becomes easier:

- A single canonical home for parent-skill contract content.
  `/scope` and `/work-on` cite the same files `/charter` cites;
  drift is structurally prevented.
- The `${CLAUDE_PLUGIN_ROOT}/references/` loading pattern is
  uniform across all shirabe shared content. No new conventions.
- The PRD's "follow-on PR for engine extraction" framing is
  preserved as a future option, available when a real cross-
  skill consumer appears.

What becomes harder:

- Each new parent skill must author its own Phase 1 discovery
  phase file (e.g., `skills/charter/references/phases/
  phase-1-discovery.md`). This is consistent with every other
  shipped shirabe skill, so the burden is uniform; reviewers
  must verify each parent's discovery file follows the
  discover/converge mental model.
- If a future feature actually needs to consume the engine
  cross-skill, a follow-on PR is required to move it. This is
  acknowledged by the PRD and is the intended path.

What changes:

- The design must include implementation tasks for four new
  top-level reference files. The "engine extraction" task is
  removed from `/charter` v1 scope.
- The pattern-level evals (per R18) verify parent skills cite
  `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`
  rather than embedding the contract surface inline.

What remains as a known limitation:

- The "engine" remains conceptually shared but physically
  duplicated across the five shipped skills that have discover
  phases. This is unchanged by the decision and tracked as
  pre-existing technical debt, not new debt introduced here.
<!-- decision:end -->
