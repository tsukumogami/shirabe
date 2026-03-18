# Phase 3 Research: Extraction Audit

## Questions Investigated

1. For each of the five core skills (/explore, /design, /prd, /plan, /work-on): what content is generic (can move to shirabe as-is) vs. project-specific (must be stripped or redirected)?
2. Which helpers are portable (move to shirabe) vs. project-specific (stay in tools)?
3. What cross-references exist between skills, and to the broader koto/tools ecosystem?
4. Which project-specific behaviors belong in CLAUDE.md vs. per-skill extension files?
5. How much line reduction would extraction cause per skill?

Base path examined: `/home/dangazineu/dev/workspace/tsuku/tsuku-5/private/tools/plugin/tsukumogami/`

---

## Findings

### /explore

**File:** `skills/explore/SKILL.md` — 453 lines

**Generic content (stays in shirabe as-is):**

- Artifact type routing guide and decision tables (PRD vs. design vs. plan vs. no-artifact)
- Crystallize framework summary (deferred types list does reference "Feature 5" — see below)
- Lead conventions (3-8 leads, questions not solutions, round evolution)
- Convergence patterns (key insights, tensions, gaps, open questions)
- Handoff artifact formats for /prd, /design, /plan, and "no artifact"
- Full workflow phases (0-5), phase execution mechanics, loop management
- Resume logic (wip/ artifact-based state detection)
- wip/ artifact naming conventions and decisions file format
- Input detection (empty, issue number, topic string)
- Cross-repo issue handling logic (repo-path-based visibility inference)

**Project-specific content (must be removed or parameterized):**

- The example cross-repo reference uses the actual GitHub org: `` `gh issue view 42 --repo tsukumogami/tsuku` `` (line 239). This is illustrative but hardcodes the org name.
  - **Classification: Extension file behavior** — the org name and example repo are project-specific; the pattern is generic.
- `"Feature 5"` reference in the Crystallize framework summary (line 66): `` (recognized but not yet routable -- Feature 5) ``. This internal roadmap reference is opaque to external users.
  - **Classification: Extension file behavior** — in shirabe base, this should be reworded (e.g., "not yet implemented") without a roadmap pointer.
- Visibility detection reads `## Repo Visibility: Private/Public` from CLAUDE.md and falls back to `private/` vs. `public/` in the repo path. The path-based fallback is tsuku workspace-specific (their workspace has `private/` and `public/` subdirectories).
  - **Classification: CLAUDE.md behavior** — the `## Repo Visibility:` key is already the canonical mechanism; the `private/`/`public/` path heuristic is a tools-specific fallback that shirabe shouldn't need.
- Scope detection reads `## Default Scope: Strategic` from CLAUDE.md. This key is used across the workspace but is a project convention.
  - **Classification: CLAUDE.md behavior** — shirabe's CLAUDE.md already sets `## Planning Context: Tactical`; the skill reads this from the extension-layer CLAUDE.md, which is correct.

**Helper references:**
- `../../helpers/writing-style.md` — loaded at the top of the skill. Generic; must move to shirabe.
- `../../helpers/decision-presentation.md` — referenced for the post-Phase-3 loop decision (line 352). Generic; must move to shirabe.
- Phase files (`references/phases/phase-0-setup.md` through `phase-5-produce.md`) — skill-internal; move to shirabe as part of the skill.
- `references/quality/crystallize-framework.md` — skill-internal; move to shirabe.

**Cross-skill references:**
- Routes to /prd, /design, /plan (handoff format section). These are inter-skill references describing format contracts, not runtime invocations. Generic.
- References `needs-triage` label in input detection (Phase 0 checks for this label on an issue). Label vocabulary is project-wide.
  - **Classification: CLAUDE.md behavior** — the label names (`needs-triage`, etc.) should be defined in the project CLAUDE.md or the label-reference helper. The skill's use of them is generic once the vocabulary is injected.

**Cross-references to koto:**
- None explicit in SKILL.md. The orchestration pattern (fan-out agents, phases, wip/ artifacts) is the koto model implemented in instructions rather than via a runtime koto system call.

**Estimated line change:** Remove ~5 lines (org-specific example, "Feature 5" wording, path-based visibility fallback). ~1% reduction. The skill is almost entirely generic.

---

### /design

**File:** `skills/design/SKILL.md` — 340 lines

**Generic content (stays in shirabe as-is):**

- Frontmatter schema (status, problem, decision, rationale fields)
- Required sections list (all 9 sections in order)
- Context-aware sections table (Strategic+Private, Strategic+Public, Tactical columns)
- Lifecycle (Proposed → Accepted → Planned → Current/Superseded) and status directory rules
- Status transition script reference (`transition-status.sh`) — generic utility
- Validation rules by consumer phase (/design drafting, /plan phase-1, /plan phase-6)
- Quality guidance (problem statement, considered options)
- File location conventions
- Workflow phases (0-6), input modes, resume logic
- Critical requirements (no premature commitment, equal-depth investigation, etc.)
- Helper references: writing-style, private-content, public-content, design-approval-routing

**Project-specific content (must be removed or parameterized):**

- **Security section is tsuku-specific** (lines 193-208). The section heading says "Security (tsuku-specific)" and the four mandatory dimensions (download verification, execution isolation, supply chain risks, user data exposure) are specific to tsuku's domain as a binary package manager.
  - **Classification: Extension file behavior** — shirabe's base skill should have a generic "Security Considerations" guidance block. The four tsuku-specific dimensions belong in an extension file (`skill-extensions/design.md`) that injects them when working in tsuku repos.
- **"NEVER empty for tsuku"** qualifier on the Security Considerations required section (line 68). Same issue — this absolute rule applies to tsuku because it downloads and executes binaries.
  - **Classification: Extension file behavior** — same as above.
- **Common pitfalls include tsuku-specific examples** (lines 205-208): `"Too broad ('Improve tsuku')"` and `"Missing security -- never skip for tsuku"`.
  - **Classification: Extension file behavior** — the pitfall examples should be generic in the base; tsuku-specific examples go in the extension.
- **Label lifecycle section** (lines 113-161): `needs-design`, `tracks-design`, `tracks-plan`, `Mermaid class` names, `swap-to-tracking.sh` script references. These presuppose the tsuku label vocabulary, the two-stage jury triage system, and specific scripts.
  - **Classification: Extension file behavior** — the label lifecycle is a project-specific workflow integration. The base skill should say "check your project's label vocabulary" and defer specifics to an extension.
- **`planning-context` skill reference** (line 71): `use the `planning-context` skill`. This is an internal skill in the tools plugin, not a shirabe skill.
  - **Classification: Extension file behavior** — in shirabe, this would reference a different mechanism or be removed; scope/visibility detection comes from CLAUDE.md.
- **`implementation-diagram` skill reference** (line 219). Another tools-internal skill.
  - **Classification: Extension file behavior** — shirabe base can describe the Implementation Issues section format without deferring to an internal skill.

**Helper references:**
- `../../helpers/writing-style.md` — generic; move to shirabe.
- `../../helpers/private-content.md` — generic; move to shirabe.
- `../../helpers/public-content.md` — generic; move to shirabe.
- `../../helpers/design-approval-routing.md` — generic; move to shirabe.
- `../../helpers/label-reference.md` — references tsuku label vocabulary. The helper itself is project-specific (see Helpers section). In shirabe base, this reference should be to a project-provided label vocabulary, with the specific labels being injected via extension or CLAUDE.md.

**Cross-skill references:**
- `/triage`, `/plan`, `/explore` — referenced by name in the label lifecycle section. These are workflow integration points that belong in the extension layer.

**Cross-references to koto:**
- `${CLAUDE_SKILL_DIR}` and `${CLAUDE_PLUGIN_ROOT}` environment variables (lines 339-340). These are koto-defined variables for script path resolution. Generic; shirabe skills use the same koto plugin infrastructure.

**Estimated line change:** Remove or replace ~60-70 lines (security tsuku block ~20 lines, label lifecycle section ~50 lines, planning-context and implementation-diagram skill references ~5 lines). ~20% reduction.

---

### /prd

**File:** `skills/prd/SKILL.md` — 340 lines

**Generic content (stays in shirabe as-is):**

- Frontmatter schema (status, problem, goals, upstream, source_issue)
- Required sections list (all 7 in order)
- Optional sections (Open Questions, Known Limitations, Decisions and Trade-offs, Downstream Artifacts)
- Content boundaries (what PRDs don't contain)
- Lifecycle (Draft → Accepted → In Progress → Done), no Superseded state rule
- Validation rules (drafting, finalization, reference by /design or /plan)
- Quality guidance (problem statement, user stories, requirements, acceptance criteria, out of scope)
- Common pitfalls (one instance references tsuku — see below)
- File location (`docs/prds/PRD-<name>.md`)
- Downstream routing complexity table
- Workflow phases (0-4), input modes, context resolution, resume logic
- Critical requirements (conversational first, research before drafting, etc.)

**Project-specific content (must be removed or parameterized):**

- **Label lifecycle section** (lines 108-133): `needs-prd`, `tracks-plan`, two-stage jury trigger from `/triage`, `swap-to-tracking.sh` script call. Same pattern as /design.
  - **Classification: Extension file behavior** — the label vocabulary and script integrations are project-specific.
- **`source_issue` frontmatter field interaction** (lines 124-125): removing `needs-prd` from a source issue by reading `source_issue` frontmatter. This assumes the tsuku GitHub label workflow.
  - **Classification: Extension file behavior** — the label management automation belongs in an extension.
- **`"Too broad ('Improve tsuku')"` pitfall** (line 201). Minor but project-specific example.
  - **Classification: Extension file behavior** — replace with generic example in shirabe base.
- **Repo Visibility section** (lines 222-229): reads `../../helpers/private-content.md` and `../../helpers/public-content.md`.
  - **Classification: CLAUDE.md behavior** — these helpers are generic and move to shirabe; the visibility mechanism itself is project-wide.

**Helper references:**
- `../../helpers/writing-style.md` — generic; move to shirabe.
- `../../helpers/private-content.md` — generic; move to shirabe.
- `../../helpers/public-content.md` — generic; move to shirabe.
- `../../helpers/label-reference.md` — project-specific vocabulary; see Helpers section.

**Cross-skill references:**
- `/triage`, `/design`, `/plan`, `/work-on`, `/implement` — referenced in routing sections. The inter-skill routing logic is generic (describes the workflow graph). The label-swapping integration with `/triage` and `/plan` is project-specific.

**Cross-references to koto:**
- `${CLAUDE_PLUGIN_ROOT}` in the swap script path (line 132). Koto infrastructure variable; generic.

**Estimated line change:** Remove ~35-40 lines (label lifecycle section ~25 lines, source_issue automation ~5 lines, tsuku example ~1 line, minor wording). ~11% reduction.

---

### /plan

**File:** `skills/plan/SKILL.md` — 399 lines

**Generic content (stays in shirabe as-is):**

- PLAN doc structure (frontmatter schema, required sections)
- Decomposition strategies (walking skeleton, horizontal, feature-by-feature for roadmaps)
- Complexity classification table (simple, testable, critical)
- Placeholder conventions (`<<ISSUE:N>>`)
- Validation rules by consumer phase
- Workflow phases (1-7), input detection, context resolution, resume logic
- Execution mode selection (single-pr vs. multi-pr)
- Phase execution details (all 7 phases)
- Critical requirements

**Project-specific content (must be removed or parameterized):**

- **Roadmap input type** (`docs/roadmaps/ROADMAP-*.md` pattern, `input_type: roadmap`, feature-by-feature planning). Roadmaps are a tsuku-specific artifact class. Generic users might not have roadmaps at all, or they might use a different structure.
  - **Classification: Extension file behavior** — the roadmap path pattern and roadmap-specific phase behavior belong in an extension. Shirabe base should support design and PRD inputs; roadmap support is a project add-on.
  - **Impact:** This affects Phase 1 (input detection), Phase 2 (milestone derivation), Phase 3 (decomposition strategy selection gate), Phase 7 (creation output), and handoff validation. Roughly 40-50 lines scattered throughout.
- **`needs_label` for roadmap planning issues** (`needs-prd`, `needs-design`, `needs-spike`, `needs-decision` per planning issue). Another label vocabulary reference tied to tsuku.
  - **Classification: Extension file behavior** — the specific label names belong in an extension or CLAUDE.md; the concept of a "needs_label" on planning issues is generic.
- **Visibility and scope detection** (reads `## Repo Visibility:` and `## Default Scope:` from CLAUDE.md). These keys are project conventions, but they're already the designed extension mechanism.
  - **Classification: CLAUDE.md behavior** — correct as-is; shirabe's CLAUDE.md defines these.
- **`implement-doc` skill reference** (lines 14, 134). Another tools-internal skill; shirabe may or may not include it.
  - **Classification: Extension file behavior** — remove from shirabe base if /implement-doc is not included in the plugin's initial five skills; it can be added by extension.

**Helper references:**
- `../../helpers/writing-style.md` — generic; move to shirabe.
- `references/quality/plan-doc-structure.md` — skill-internal; move to shirabe.
- Phase files and templates — skill-internal; move to shirabe.
- `${CLAUDE_SKILL_DIR}/scripts/build-dependency-graph.sh`, `create-issues-batch.sh`, `create-issue.sh`, `render-template.sh`, `apply-complexity-label.sh` — koto-infrastructure scripts. Some may be generic (dependency graph, batch creation), some may touch tsuku-specific label application.

**Cross-skill references:**
- `/work-on`, `/implement-doc`, `/explore` — generic routing references.
- `swap-to-tracking.sh` — label lifecycle script; project-specific.

**Cross-references to koto:**
- `${CLAUDE_SKILL_DIR}` and `${CLAUDE_PLUGIN_ROOT}` for script paths. Koto infrastructure; generic.

**Estimated line change:** Remove or redirect ~50-60 lines (roadmap input type scattered through multiple sections ~40 lines, needs_label vocabulary ~5 lines, implement-doc references ~5 lines). ~13-15% reduction.

---

### /work-on

**File:** `skills/work-on/SKILL.md` — 136 lines (shortest of the five)

**Generic content (stays in shirabe as-is):**

- Input resolution (issue number, milestone reference, URL formats)
- Workflow phases (0-6): context injection, setup, introspection, analysis, implementation, finalization, pull request
- Resume logic (artifact and commit-based detection)
- Critical requirements (atomic commits, quality gates, CI completion)

**Project-specific content (must be removed or parameterized):**

- **`go-development` skill invocation** (line 97): `Invoke the `go-development` skill for code quality requirements`. This hardcodes Go as the language for quality gate checks.
  - **Classification: Extension file behavior** — language-specific quality skill is entirely project-specific. In shirabe base, this should say "invoke your project's language skill for quality requirements" or simply omit it; the tsuku extension injects `go-development`.
- **`pr-creation` skill invocation** (line 97): `and the `pr-creation` skill for PR requirements`. This references another tools-internal skill.
  - **Classification: Extension file behavior** — could be a shirabe-bundled skill or a project override.
- **`upstream-context` skill invocation** (line 23) in needs-triage handling. Another tools-internal skill.
  - **Classification: Extension file behavior** — in shirabe base, inline triage can proceed without a separate upstream-context skill, or the hook can be left for extension.
- **Label blocking section** (lines 36-54): full label vocabulary (`tracks-design`, `tracks-plan`, `needs-design`, `needs-prd`, `needs-spike`, `needs-decision`) with specific routing messages. Same label vocabulary dependency as other skills.
  - **Classification: Extension file behavior** — the label names and routing messages are project-specific. Shirabe base should have a generic "check your project's blocking labels" pattern; the tsuku extension injects the specific vocabulary.
- **`/implement-doc` routing** (line 40-42): directs to `/implement-doc` for tracked artifacts.
  - **Classification: Extension file behavior** — this is a tsuku-ecosystem routing rule.
- **`/triage` inline invocation** (lines 21-32): the jury-based triage pattern with 3 agents. This references the /triage skill which is not one of the five packaged skills.
  - **Classification: Extension file behavior** — /triage is a project-level skill outside the five shipped in shirabe. The inline triage behavior belongs in an extension.

**Helper references:**
- `helpers/label-reference.md` — referenced for blocking label vocabulary. Project-specific; see Helpers section.

**Cross-skill references:**
- `/triage`, `/explore`, `/implement-doc` — all referenced in label-routing sections. Project-specific integration; extension layer.
- `go-development`, `pr-creation`, `upstream-context` — tools-internal skills.

**Cross-references to koto:**
- None explicit. Phase files are under `references/phases/` within the skill directory (standard koto layout).

**Estimated line change:** Remove ~40-45 lines (label blocking section ~20 lines, go-development/pr-creation/upstream-context invocations ~5 lines, inline triage section ~15 lines). ~30-33% reduction. This skill has the highest project-specific content ratio by percentage.

---

### Helpers

Six helpers exist. Assessment of each:

#### `writing-style.md` — **Portable (move to shirabe)**

Entirely generic guidance on avoiding AI writing patterns, overused words, and structural anti-patterns. No tsuku-specific content. References three external URLs for further reading. This helper moves to shirabe verbatim.

#### `decision-presentation.md` — **Portable (move to shirabe)**

Defines the project convention for structuring agent decisions (selection vs. approval, recommended-first ordering, evidence grounding). Entirely generic. References `AskUserQuestion` tool by name, which is Claude Code infrastructure, not tsuku-specific. Moves to shirabe verbatim.

#### `design-approval-routing.md` — **Portable (move to shirabe)**

Post-approval routing logic for design documents. Complexity assessment criteria (1-3 files vs. 4+, new tests, API surface) are generic. The `Ref #<N>` vs. `Fixes #<N>` PR convention and `spawned_from` frontmatter handling are generic GitHub conventions. References `swap-to-tracking.sh` script and the `design` skill's lifecycle section for label updates — these are the only project-specific hooks, but they're already delegated to the label lifecycle (handled in extension). Moves to shirabe with minor note that the label update step is optional/extension-provided.

#### `public-content.md` — **Portable (move to shirabe)**

Generic public repo content guidelines. The only line that could be considered project-specific is the explicit mention that internal workflows (`/explore`, `/work-on`, `/plan`) should not be referenced in public content. This is ironic — in shirabe, these ARE the public workflows. The restriction in the original is about tsuku's internal development process, not about the skills themselves. The helper should be kept but this specific restriction should be dropped or reworded for shirabe's context.

**Estimated change:** ~3 lines removed/reworded. Otherwise portable.

#### `private-content.md` — **Portable (move to shirabe)**

Generic private repo content guidelines. No tsuku-specific content. Moves verbatim.

#### `label-reference.md` — **Project-specific (stays in tools)**

Defines the tsuku label vocabulary: `needs-triage`, `needs-design`, `needs-prd`, `needs-spike`, `needs-decision`, `tracks-plan`, plus Mermaid class names and color codes. This is tightly coupled to the tsuku GitHub repo label setup.

In shirabe, the equivalent should be a template or a prompt asking projects to define their own label vocabulary. The helper could be restructured as a template: `label-reference.md` becomes a starter file that projects copy and populate. The base shirabe version would ship with a near-empty template that explains the pattern; tsuku's version (in `skill-extensions/label-reference.md` or CLAUDE.md) would inject the specific labels.

**Classification: Extension file behavior** — label vocabulary is per-project, not per-skill. Belongs in CLAUDE.md (for simple label lists) or in a project-level helper loaded by extension files.

---

## Implications for Design

**1. The extension file surface is larger than anticipated for /work-on.**

/work-on has the highest removal percentage (~33%) because three separate concerns are project-specific: the language skill (Go), the label routing table, and the inline /triage invocation. All three need extension points. The base skill needs three clearly marked "see extension" hooks.

**2. Label vocabulary is the single most pervasive project-specific element.**

Every skill except /explore (minimally) references the tsuku label vocabulary. Rather than duplicating label names across five extension files, CLAUDE.md is the right home. A single `## Label Vocabulary` section in CLAUDE.md can define the label names, and skills read them from context. This reduces the extension file burden significantly.

**3. The roadmap input type in /plan is a meaningful chunky extraction.**

It's not a few lines — it's a structural branching path woven through multiple phases. Extracting it cleanly requires either (a) a separate `roadmap-extension` file that adds the roadmap path to the skill, or (b) keeping roadmap support in the base because it's a commonly needed artifact type. The latter is defensible: roadmaps are not tsuku-specific, just the label vocabulary attached to them is. The labels (`needs-prd`, `needs-design`, etc.) can be injected by extension; the roadmap structural logic stays in base.

**4. The tsuku security block in /design is the cleanest extraction candidate.**

It's self-contained, clearly labeled "tsuku-specific," and has no tentacles into other sections. It's the model case for an extension file: `skill-extensions/design.md` adds the four security dimensions when working in tsuku repos.

**5. Three tools-internal skills are referenced across the five skills.**

`go-development`, `upstream-context`, and `planning-context` are not among the five packaged skills. `pr-creation` and `implementation-diagram` are also referenced. These internal skill invocations need extension hooks in the base. The base skill should document what the hook is for; the extension provides the skill name to invoke.

**6. Path-based visibility fallback (`private/` vs. `public/`) is tools-workspace-specific.**

This heuristic appears in /explore and /plan. It should be removed from shirabe's base. The `## Repo Visibility:` key in CLAUDE.md is the canonical mechanism and is sufficient.

**7. `public-content.md` needs one targeted reword for shirabe.**

The prohibition on mentioning `/explore`, `/work-on`, `/plan` in public content was written from tsuku's perspective (those are internal development commands). In shirabe, those ARE the product. The reword is straightforward.

---

## Surprises

**1. /design's label lifecycle section is much longer and more complex than expected (~50 lines).**

The section covers forward transitions, reverse transitions (superseded child design), Mermaid class updates, and two different scripts. It's the most sophisticated project-specific block in any skill, and it's buried mid-document in the reference section rather than separated into its own sub-heading that would make extraction obvious.

**2. /explore is almost entirely generic.**

Despite being the most complex skill by line count (453 lines), it has almost no project-specific content — just two lines (the `tsukumogami/tsuku` org name and "Feature 5") and the path-based visibility fallback. The convergence framework, lead conventions, handoff formats, and phase logic are all portable.

**3. The "Feature 5" reference in /explore is a live internal roadmap pointer.**

This is the kind of reference that would be meaningless and potentially confusing to external users. It implies shirabe's /explore is incomplete and references an internal planning artifact. It should become "not yet implemented" in the shirabe base.

**4. /work-on invokes `/triage` inline, but /triage is not one of the five packaged skills.**

This creates a hidden dependency: /work-on's needs-triage handling calls into /triage, which relies on the full jury infrastructure. If /triage is absent (as it would be in a minimal shirabe install), this path silently fails or produces an error. The base skill should either include fallback behavior (proceed without triage, flag the issue) or make the /triage dependency explicit.

**5. The `public-content.md` helper explicitly prohibits mentioning `/explore`, `/work-on`, `/plan`.**

This would cause absurd behavior in shirabe if loaded literally: the skills would instruct agents to avoid mentioning themselves in public artifacts. The prohibition is about internal tooling exposure in tsuku's public documentation, not a universal rule. It needs rewriting before shipment.

---

## Summary

All five skills are predominantly generic. The project-specific content falls into two clear categories:

**CLAUDE.md behaviors** (project-wide settings, ~5-10 lines in CLAUDE.md):
- `## Repo Visibility: Public|Private` — canonical visibility key, already defined
- `## Default Scope: Tactical|Strategic` — canonical scope key, already defined (as `## Planning Context:` in shirabe)
- `## Label Vocabulary` — add this section to define `needs-*` and `tracks-*` label names; eliminates label-reference.md as a project-specific file

**Extension file behaviors** (per-skill, in `.claude/skill-extensions/<name>.md`):
- `/design`: tsuku security dimensions block (~20 lines), label lifecycle section (~50 lines), `planning-context`/`implementation-diagram` skill references (~5 lines)
- `/prd`: label lifecycle section (~25 lines), `source_issue` label automation (~5 lines)
- `/plan`: roadmap input type branching (~40 lines, arguably optional extraction), `needs_label` vocabulary (~5 lines), `implement-doc` references (~5 lines)
- `/work-on`: `go-development`/`pr-creation`/`upstream-context` skill invocations (~5 lines), label blocking table (~20 lines), inline /triage invocation (~15 lines)
- `/explore`: org-specific example and "Feature 5" wording (~3-5 lines)

**Helpers portability:**
- Move to shirabe: `writing-style.md`, `decision-presentation.md`, `design-approval-routing.md`, `private-content.md`, `public-content.md` (with one targeted reword)
- Keep in tools (project-specific): `label-reference.md` — becomes a template or is absorbed into CLAUDE.md's `## Label Vocabulary` section

**Total estimated line reduction across all five skills:** ~185-220 lines removed from bases (out of 1668 total, ~11-13%). The skills are already well-structured for extraction; the project-specific content is mostly concentrated in label lifecycle sections and the tsuku security block.
