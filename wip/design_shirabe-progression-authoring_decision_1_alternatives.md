# Alternatives: Shared parent-skill reference location

## Alternative 1: Hybrid — top-level for new contract references; engine stays put

**Description.** Ship four NEW pattern-level reference files at
top-level `references/`:

- `references/parent-skill-pattern.md` — contract surface
  (state schema link, resume-ladder link, child-doc-inspection
  link, three exit paths, CLAUDE.md surfacing rule, eval
  requirement). The "table of contents" for the pattern.
- `references/state-file-schema.md` — YAML schema for
  `wip/<parent>_<topic>_state.md` covering R9, R10, named fields
  (`chain_started`, `planned_chain`, `chain_ran`, `chain_skipped`,
  `exit`, `decision_record_sub_shape`, `exit_artifacts`,
  `child_snapshots`).
- `references/resume-ladder-template.md` — ordered ladder per
  R11, child-snapshots semantics, multi-source consultation
  rules.
- `references/child-doc-inspection.md` — R14 isolation rules
  (frontmatter `status:` + git blob hash; NO reads of
  `wip/research/<child>_*.md`).

The discover/converge engine STAYS at
`skills/explore/references/phases/{phase-2-discover.md,
phase-3-converge.md}`. Each parent skill (`/charter`, `/scope`,
`/work-on`) ships its OWN `skills/<parent>/references/phases/
phase-1-discovery.md` (or similar) that authors the
parent-specific discovery prompts. Where overlap exists with
`/explore`'s engine prose, the parent's phase file cites
`skills/explore/references/phases/phase-2-discover.md` as
"engine reference for the discover-converge mental model."

All four NEW files are loaded by parent skills via
`${CLAUDE_PLUGIN_ROOT}/references/<file>.md` — matching the
established pattern for `decision-protocol.md`,
`cross-repo-references.md`, etc.

**Source.** Synthesis from research findings (empirical
codebase audit shows top-level `references/` is the established
home for cross-skill content; engine is conceptual, not a
physical shared file).

**Key characteristics.**
- Honors the established `${CLAUDE_PLUGIN_ROOT}/references/`
  pattern for shared content.
- No `/explore` callers break — engine stays where it lives.
- New pattern-level references have one canonical home.
- Per-parent discovery prose lives skill-local (matching every
  other shipped shirabe skill).
- `/charter` ships against current paths; future parents
  inherit the four new top-level files.
- The PRD's "engine extraction follow-on PR" stays available
  as a future option if cross-skill engine consumption ever
  becomes load-bearing.

## Alternative 2: Full top-level extraction — engine moves too

**Description.** Move the discover/converge engine prose from
`skills/explore/references/phases/{phase-2-discover.md,
phase-3-converge.md}` to a new top-level location:
`references/discover-converge-engine.md` (or split into
`references/discover-phase.md` and
`references/converge-phase.md`). Update `/explore`'s SKILL.md to
reference the new location. Update the four other shipped
skills with discover phases (`/prd`, `/vision`, `/roadmap`,
`/strategy`) to either consume the moved engine cross-skill or
note they each have their own variant.

In addition, ship the same four new pattern-level reference
files at top-level (`parent-skill-pattern.md`,
`state-file-schema.md`, `resume-ladder-template.md`,
`child-doc-inspection.md`) as in Alternative 1.

Result: ALL shared parent-skill references — including the
engine — live at top-level `references/`, signaling "this is
cross-cutting infrastructure" with one canonical home.

**Source.** Coordinator brief's "move to top-level
`references/`" framing (the strongest version of the move).

**Key characteristics.**
- Maximal abstraction: every shared reference at one location.
- Touches `/explore`'s SKILL.md and potentially four other
  skills (path updates).
- Signals strongest commitment to shared infrastructure.
- Empirically, no current caller consumes the engine
  cross-skill, so the move is speculative — done to set the
  pattern for future parents.
- Risk: the engine's prose is bespoke to `/explore`'s round-
  tracking semantics (round number, `wip/explore_<topic>_
  findings.md`). Lifting it cleanly requires either editing the
  prose to be skill-agnostic or living with `/explore`-specific
  language in a "shared" file.

## Alternative 3: Status quo — engine stays; new content lives per-parent

**Description.** Engine stays at
`skills/explore/references/phases/`. New pattern-level shared
references (`parent-skill-pattern.md`, `state-file-schema.md`,
`resume-ladder-template.md`, `child-doc-inspection.md`) are NOT
shipped at top-level. Instead, each parent skill ships its own
copy under `skills/<parent>/references/` (`charter/references/
parent-skill-pattern.md`, `scope/references/parent-skill-pattern.md`,
etc.). Where parents need to assert consistency, the design doc
prose names the contract; each skill self-documents.

**Source.** Pure no-change path. The PRD's deferred-question
status quo extended one level deeper: not just engine, but ALL
references stay skill-local.

**Key characteristics.**
- Zero changes to the existing top-level `references/` directory.
- Each parent owns its references — no cross-skill coupling.
- Costs: three copies of `parent-skill-pattern.md` when the
  three parents ship; pattern drift risk is high (the entire
  reason the design exists is to prevent fragmentation).
- Directly contradicts the design's reuse-load-bearing driver
  (decision driver 14: "Maintainability across the three
  parents. Pattern-level references ... must be authored such
  that each parent cites them rather than re-implementing
  them"). This alternative IS re-implementation.

## Comparison

| Dimension | Alt 1 (Hybrid) | Alt 2 (Full extract) | Alt 3 (Status quo) |
|-----------|---------------|---------------------|-------------------|
| Honors established `${CLAUDE_PLUGIN_ROOT}/references/` pattern | Yes | Yes | No (re-derives per parent) |
| Pattern-level references have one canonical home | Yes | Yes | No (3 copies) |
| `/explore` and 4 other skills require path updates | No | Yes | No |
| Engine cross-skill consumption becomes possible | Future option | Yes | No |
| Speculative work done now for hypothetical future | Minimal | Yes (engine move) | None |
| Matches design driver 14 (no re-implementation) | Yes | Yes | No |
| Blast radius | Low (only new files) | Medium (engine move + 4-5 SKILL.md updates) | Low (no new shared files) |
| Risk of pattern drift across 3 parents | Low | Low | High |
| Aligns with PRD "engine extraction is follow-on PR" framing | Yes | Conflicts (does extraction now) | Yes |

## Recommendation (--auto mode)

**Alternative 1: Hybrid.** This is the alternative that earns
the design driver (single canonical home for pattern-level
references) without paying for speculative engine extraction
that no caller currently demands. The empirical evidence shows
the "engine" is a mental model, not a shared file — moving it
now is work without consumers. The new pattern-level references
ARE shared content with three consumers (`/charter`, `/scope`,
`/work-on`), so they belong at top-level `references/` matching
the precedent set by `decision-protocol.md` and
`cross-repo-references.md`.

The PRD's framing "engine extraction is a follow-on PR" is
preserved: if a future feature actually needs the engine
cross-skill (e.g., `/scope`'s Phase 1 imports the same converge
loop as `/explore`'s Phase 3), that PR moves the engine then,
under load-bearing pressure. Until then, the engine stays.

Alt 3 is rejected because it directly contradicts decision
driver 14 (pattern-level references must be cited, not
re-implemented). Three copies of `parent-skill-pattern.md` is
the failure mode the design exists to prevent.

Alt 2 is rejected because the engine extraction is speculative
work: no shipped or scoped caller consumes it cross-skill, and
the engine's prose is `/explore`-specific (round numbers,
`findings.md` filenames). A move now either ships a leaky
"shared" file or requires a refactor of `/explore`'s phase
prose. Both are out-of-scope cost for `/charter`'s v1.

Fast path (Tier 3) proceeds to Phase 6 with Alternative 1 as
the chosen option.
