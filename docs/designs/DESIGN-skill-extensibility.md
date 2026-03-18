---
status: Proposed
problem: |
  shirabe's five workflow skills need to be extracted into the plugin and made
  extensible so downstream consumers can layer project-specific behavior without
  forking. Claude Code has no plugin-to-plugin extensibility, and the skills
  contain 20-30% project-specific behavior (visibility detection, label lifecycle,
  scope routing) that must be customizable per project.
decision: |
  A two-layer extension model: CLAUDE.md handles cross-skill project-wide behavior
  via documented headers (Repo Visibility, Planning Context, Label Vocabulary), and
  per-skill extension files at `.claude/shirabe-extensions/<name>.md` are loaded via
  `@` includes at the head of each SKILL.md. Both layers resolve client-side before
  the LLM processes the skill — zero tool calls, deterministic, installation-agnostic.
  A gitignored `.local.md` variant enables personal machine-level overrides.
rationale: |
  CLAUDE.md-only cannot target per-skill behavior without requiring shirabe changes
  for each unanticipated consumer need, and fails silently on header renames. Wrapper
  skills produce parallel maintenance rather than consumption — drift is the default
  outcome, and cross-plugin path resolution doesn't work when two plugins are installed
  separately. The two-layer model uses existing Claude Code `@` include behavior with
  zero new infrastructure, keeps project-wide and skill-specific customization in
  separate layers, and gives downstream consumers a stable contract (the `@` slot
  lines and CLAUDE.md header names) that survives most shirabe updates without changes.
---

# DESIGN: Skill Extensibility

## Status

Proposed

## Context and Problem Statement

shirabe packages five workflow skills (/explore, /design, /prd, /plan, /work-on)
as a public Claude Code plugin. Extracting these skills into shirabe requires
separating generic workflow logic from project-specific customization so that
downstream consumers can adapt skills to their project's conventions without
forking and maintaining their own copies.

Claude Code's plugin system provides no mechanism for plugin-to-plugin
extensibility — no dependencies, no cross-plugin skill invocation, no composition.
Skills are namespaced per plugin, forming a flat additive pool. Any extensibility
mechanism must work within these constraints.

Skills are LLM-read markdown, not executable code. Extensibility works through
text composition. CLAUDE.md layering already provides project-wide context in
every session and handles 60-70% of customization needs (writing style,
visibility, scope defaults, label vocabulary). The remaining 20-30% is per-skill
behavior that CLAUDE.md cannot target precisely.

### Platform Scope

The extension mechanism described in this design is Claude Code-specific. The
base SKILL.md format follows the Agent Skills open standard and is portable to
other clients (such as Cursor) via a parallel plugin manifest; the CLAUDE.md
headers layer translates to AGENTS.md or equivalent project context files. The
per-skill `@` extension slot mechanism, however, relies on client-side `@`
include injection that Cursor does not implement — raw `@path` text is visible
to the LLM rather than being resolved and injected.

| Mechanism | Claude Code | Cursor |
|-----------|-------------|--------|
| Plugin manifest | `.claude-plugin/plugin.json` | `.cursor-plugin/plugin.json` (separate, same pattern) |
| SKILL.md base format | Agent Skills + CC extensions | Agent Skills standard — mostly compatible; avoid CC-specific frontmatter |
| Skill invocation | Yes | Yes |
| CLAUDE.md / project context | CLAUDE.md chain | AGENTS.md + `.cursor/rules/` — translatable |
| `@` include in SKILL.md (client-side injection) | Yes — 0 tool calls, deterministic | No — raw text visible to LLM, extension not injected |
| Per-skill extension file injection | Works via `@` include | Not supported natively |
| `.local.md` personal overrides | Yes | No equivalent |

Cursor users can consume the base skills and use always-applied `.cursor/rules/`
files for project-wide context (equivalent to the CLAUDE.md headers layer), but
have no per-skill extension point equivalent.

## Decision Drivers

- Skills are LLM-read markdown — extensibility works through text composition,
  not function overrides
- CLAUDE.md layering is free and covers most global customization needs
- LLMs naturally weight later-loaded instructions higher (append-based composition)
- Claude Code's plugin system may add dependency support in the future
  (anthropics/claude-code#27113)
- Extension mechanisms must survive shirabe skill updates without requiring
  downstream rewrites
- Extension loading must be deterministic — no LLM roundtrip to decide whether
  to load a customization file

## Considered Options

### Decision 1: Extension mechanism

**Context:** How should downstream consumers add project-specific behavior to
shirabe's base skills without forking them?

**Chosen: Two-layer (CLAUDE.md + per-skill extension files).**

CLAUDE.md handles cross-skill project-wide behavior (visibility detection, scope
defaults, writing style, label vocabulary). Per-skill extension files at
`.claude/shirabe-extensions/<name>.md` are loaded via `@` includes in the base
SKILL.md. The `@` resolution is handled client-side by Claude Code before the LLM
processes the skill — confirmed by testing: 0 tool calls, deterministic, works
with plugin registry install, `--plugin-dir`, and local paths. Missing files
produce silent skips (raw `@path` text visible to LLM but ignored in practice).
A `.local.md` variant (`.claude/shirabe-extensions/<name>.local.md`, gitignored)
enables personal machine-level overrides that aren't committed to the repo.

This cleanly separates what belongs in CLAUDE.md (applies to every conversation
in the project) from what belongs in extension files (applies only when a specific
skill runs). Typical downstream customizations — project-specific triage routing,
custom label vocabulary, internal tool invocations — fit in a small extension file
per skill. Most skills need little or no extension.

*Alternative rejected: CLAUDE.md-only.* Adequate for a small, stable set of
known customization points, but requires a shirabe update to unblock any downstream
consumer with an unanticipated need. Fails silently on header renames or semantic
changes with no error surface. Cannot redirect skill script invocations. Doesn't
scale beyond a small, stable header contract.

*Alternative rejected: Wrapper skills.* Downstream creates its own plugin with
skills that add project preamble then read the base SKILL.md. This results in
parallel maintenance rather than consumption — drift is the default outcome.
Read delegation (wrapper reads base SKILL.md at runtime) fails when the two
plugins are installed separately because Claude Code provides no cross-plugin
path resolution. Unnamespaced skill name conflicts have undefined behavior when
both plugins are active simultaneously.

### Decision 2: Phase-level extension granularity

**Context:** Should individual phases of multi-file workflow skills be independently
extensible?

**Chosen: Out of scope for this design.**

Phase-level extensions require either `@` includes in phase files (LLM-driven
Read calls, not deterministic) or loading all phase extensions up-front in SKILL.md
(deterministic but loads all phase extensions regardless of execution path). Both
mechanisms work, but the added complexity isn't justified by current known extension
needs. Skill-level extension files can express phase-specific intent ("when
executing Phase 0, also invoke upstream-context skill") without separate per-phase
files. This can be revisited if a downstream consumer demonstrates a clear need.

### Decision 3: Extension slot placement in SKILL.md

**Context:** Where in the SKILL.md file should the `@` extension slot lines appear?

**Chosen: At the head, immediately after frontmatter.**

Extension content is project context that should frame how the skill's instructions
are interpreted. Placing it before the base skill logic makes the extension a
preamble — the LLM encounters it first and retains it as the project-level frame
for everything that follows. This is the same pattern as CLAUDE.md: project context
loads before task instructions.

*Alternative rejected: at the end of SKILL.md.* LLMs weight later context higher,
so tail placement would make extension instructions more authoritative than base
instructions. This seems appealing for overrides but creates unpredictable behavior
when extension and base instructions conflict — the base skill's concluding logic
would always be subordinated to extension content, even for cases where the extension
author didn't intend to override that section.

### Decision 4: Extension files are additive-only

**Context:** Should extension files support override or suppression of base instructions?

**Chosen: Additive-only. No override or suppression syntax.**

Extension files append context that the LLM considers alongside the base skill.
There is no "delete this instruction" operation in LLM-read markdown — any attempt
to suppress base behavior via text ("ignore step X") is unreliable and model-dependent.
Extension files should express intent ("also do Y when doing Z") not negation.

*Alternative rejected: structured override format.* A syntax like `## Override: phase-0`
followed by replacement content could signal to the LLM that it replaces the base
version of that section. This was investigated during exploration and found to have
weak reliability — the LLM may or may not honor the override depending on instruction
clarity and context window position. No test confirmed reliable suppression. Additive
composition is the only behavior that tests confirmed as stable across contexts.

### Decision 5: Consumption model

**Context:** How should downstream consumers install and wire up shirabe as a dependency?

**Chosen: Defer to consumer repositories; the extension mechanism is installation-agnostic.**

The `@.claude/shirabe-extensions/` path resolves from the workspace root regardless of whether shirabe is installed via plugin registry, git submodule, or local path. No installation model is prescribed here — concrete migration patterns for specific consumers belong in their own repositories, not in this design.

*Alternative rejected: prescribe a specific installation model (e.g., submodule).* Research found submodule to be the cleanest concrete path, but encoding it in this design would couple the extensibility mechanism to an installation choice. Consumers with different constraints (monorepo setups, plugin registry pinning, CI environments) would be poorly served by a prescribed model.

### Decision 6: writing-style helper format

**Context:** The writing-style helper ships guidance on avoiding AI writing patterns. Skills currently load it via `Read ../../helpers/writing-style.md`. Should it be a skill, a reference file, or stay as a helper?

**Chosen: Convert to a skill.**

The writing-style helper's use case matches the skill format exactly — it can be invoked by users to revise drafts (same model as blader/humanizer), auto-invoked by the model when writing, and is portable to Cursor as a standard Agent Skills file. The current `Read helpers/writing-style.md` instruction in each skill becomes a skill reference instead.

Industry research (blader/humanizer, Pangram Labs, Wikipedia:Signs_of_AI_writing) also confirms the helper's current word coverage is ~30-40% of available documented patterns, and a skill provides a better surface for iterative improvement.

*Alternative rejected: keep as helper.* The helper format is a custom abstraction with no mechanism advantage — helpers are not @-included passively, they are loaded on demand via LLM Read calls, the same as skills. There is no benefit to the `helpers/` directory over the `skills/` directory for this use case.

### Decision 7: decision-presentation helper format

**Context:** The decision-presentation helper defines how agents structure choices for users (recommend-first, selection vs approval variants, equal-options tiebreaker). Referenced in explore, design, and prd phase files. Should it be a skill, inlined, or kept as a reference file?

**Chosen: Keep as a reference file, move to `references/`.**

The helper is referenced in 5+ places across three skills' phase files. Inlining would require maintaining the same ~55 lines in each callsite. Converting to a user-invocable skill adds no value — no user would invoke `/decision-presentation` directly, and the content is guidance for skill authors, not a workflow step. Moving it to `references/` (dropping the misleading `helpers/` label) is the right change.

*Alternative rejected: convert to skill with `disable-model-invocation: true`.* Adds discoverability in the plugin manifest for no practical benefit. The reference file pattern is already well-established in the codebase (phase files use the same mechanism).

*Alternative rejected: inline into callsite phase files.* The 5+ callsite count makes inline duplication a maintenance liability. The content evolves (industry sweep found three gaps to address); a single source file is better.

### Decision 8: private-content and public-content helper format

**Context:** Two helpers define content governance rules for private vs public repositories. Skills load the appropriate one conditionally based on visibility detection. Should they be skills, CLAUDE.md content, or reference files?

**Chosen: Keep as reference files, move to `references/`.**

These files are loaded conditionally (one or the other, never both) based on `## Repo Visibility:` in CLAUDE.md. Converting to skills adds no mechanism benefit — the conditional load is LLM-driven already. Folding into CLAUDE.md would make them project-wide passive context, which is too broad; consumers would then carry content governance rules in their own CLAUDE.md rather than getting them from the plugin. Reference files in `references/` are the right home.

One fix required before shipping: `public-content.md` contains a restriction prohibiting slash commands (`/explore`, `/work-on`, `/plan`) as "internal tooling." This restriction was written for a project using them as internal tools; shirabe ships those as its public skills, so the restriction incorrectly suppresses accurate artifact content. The fix: narrow to "internal-only tooling that external contributors cannot access."

*Alternative rejected: convert to skills.* No user invocation model applies. Content governance guidance is passive context, not a workflow step.

*Alternative rejected: fold into CLAUDE.md.* The per-artifact breakdown (design docs, issues, PRs, code comments) and conditional loading by visibility require more specificity than CLAUDE.md headers support. It would also require consumers to carry this content in their own CLAUDE.md, defeating the plugin's purpose.

### Decision 9: design-approval-routing helper format

**Context:** The design-approval-routing helper defines post-approval routing logic after a design document is accepted: complexity assessment rubric, routing to /plan or approve-only, PR body convention. Referenced in design phase-6 and explore phase-5. Should it be a skill, inlined, or kept as a reference file?

**Chosen: Inline into the two phase files that use it.**

The helper is referenced in exactly two places. The content is workflow logic specific to those phases — not a reusable pattern across skills, and not something a user would invoke directly. A separate file adds indirection with no reuse benefit at this callsite count.

One fix required at extraction: the "Source issue updates" section defers to "the design skill's label lifecycle section," which becomes extension-layer content in shirabe. The deference should read "if your project defines a label lifecycle, apply it here" so base shirabe consumers don't encounter a broken reference.

*Alternative rejected: keep as reference file.* Two callsites is below the threshold where a shared reference file adds value. The content is stable enough to maintain in two places.

*Alternative rejected: convert to skill.* No user invocation model. Pure internal workflow routing logic.

## Decision Outcome

The two-layer extension model defines how downstream consumers customize shirabe skills:

1. **CLAUDE.md** — project-wide context loaded in every conversation. Skills read
   documented headers (`## Repo Visibility`, `## Planning Context`, etc.) to adapt
   global behavior. No changes to this existing mechanism.

2. **`.claude/shirabe-extensions/<name>.md`** — per-skill extension file. Each base
   SKILL.md includes `@.claude/shirabe-extensions/<name>.md` and
   `@.claude/shirabe-extensions/<name>.local.md` at its head. Both are resolved
   client-side; missing files are silently skipped. Downstream consumers create
   these files to extend specific skills without touching shirabe's source.

Key properties:
- Deterministic: extension loading requires 0 LLM tool calls
- Installation-agnostic: path resolves from workspace root regardless of how shirabe is installed
- Layered: repo-level extension committed to the project; `.local.md` gitignored for personal overrides
- Update-resilient: extension files express intent ("also invoke X"), not structure ("override phase-0-setup.md")
- No new infrastructure: `@` include is an existing Claude Code feature

## Solution Architecture

### Overview

Each base skill declares two extension slots at the head of its SKILL.md. When a
consumer creates `.claude/shirabe-extensions/<name>.md`, that content is injected
into the skill's context deterministically by Claude Code before the LLM processes
any instructions. Missing files are silently skipped. The skill's logic then runs
with both base and extension content in context, LLM weight naturally favoring
the extension (loaded after the base instructions).

CLAUDE.md layering handles project-wide settings that apply across all skills.
Extension files handle per-skill customizations that don't belong in every
conversation.

### Components

```
shirabe plugin
├── skills/
│   ├── explore/
│   │   ├── SKILL.md                    # @ extension slots at head; generic logic
│   │   └── references/phases/*.md      # Phase files, loaded on demand via Read
│   ├── design/
│   ├── prd/
│   ├── plan/
│   └── work-on/
├── helpers/
│   ├── writing-style.md
│   ├── public-content.md
│   ├── private-content.md
│   ├── decision-presentation.md
│   └── design-approval-routing.md
├── scripts/
│   └── transition-status.sh            # Generic design doc status transition
└── CHANGELOG.md                        # Extension contract change history

Consumer project
└── .claude/
    └── shirabe-extensions/
        ├── explore.md                  # Repo-level extension (committed)
        ├── explore.local.md            # Personal overrides (gitignored)
        ├── design.md
        ├── design.local.md
        └── ...
```

### Key Interfaces

**Extension slot declaration** — every base SKILL.md opens with:

```markdown
@.claude/shirabe-extensions/<name>.md
@.claude/shirabe-extensions/<name>.local.md
```

where `<name>` matches the `name:` field in the skill's SKILL.md frontmatter.
These two lines are the stable public API of the extension mechanism.

**CLAUDE.md headers** — skills read the following headers from the project's
CLAUDE.md chain to adapt global behavior:

| Header | Values | Required | Used by |
|--------|--------|----------|---------|
| `## Repo Visibility:` | `Public` / `Private` | Optional (defaults to Private) | All five skills |
| `## Planning Context:` | `Tactical` / `Strategic` | Optional (defaults to Tactical) | /explore, /plan |
| `## Label Vocabulary` | free-form prose or list | Optional (skills use generic fallback) | All five skills |

The `## Label Vocabulary` header is new — it replaces per-skill label-reference
file dependencies. Consumers define their issue label names once in CLAUDE.md;
all five skills read them from context. If absent, skills proceed without a
project-specific label vocabulary.

**Breaking change categories** — changes to shirabe that require downstream
extension file updates:

1. Removing an `@` extension slot line from a SKILL.md
2. Renaming a phase in the skill's workflow overview section
3. Renaming a CLAUDE.md header that the skill reads

All other changes (rewording, phase file refactors, new phases added, helper
updates) are non-breaking. CHANGELOG.md tracks breaking changes in a dedicated
section; consumers review it before upgrading.

### Data Flow

```
Skill invoked
     │
     ▼
Claude Code loads SKILL.md as attachment
  │  Resolves @ includes client-side:
  │    .claude/shirabe-extensions/<name>.md    → injected if present
  │    .claude/shirabe-extensions/<name>.local.md → injected if present
     │
     ▼
LLM context contains:
  - CLAUDE.md chain (workspace → repo → subdirectory)  [loaded before skill]
  - SKILL.md base content
  - Extension file content (if present, appended after base)
  - Local extension content (if present, appended after repo extension)
     │
     ▼
LLM executes skill
  - Reads phase files on demand via Read tool
  - Extension context active for all phase decisions
```

## Implementation Approach

### Phase 1: Helpers

Extract portable helpers to `shirabe/helpers/`. No skill changes yet.

Deliverables:
- `helpers/writing-style.md` — verbatim copy
- `helpers/decision-presentation.md` — verbatim copy
- `helpers/design-approval-routing.md` — verbatim copy, note that label update step is extension-provided
- `helpers/private-content.md` — verbatim copy
- `helpers/public-content.md` — copy with one targeted reword: remove the prohibition on mentioning the five workflow skills (that prohibition was written for a project using them as internal tools, not a plugin shipping them)
- `CHANGELOG.md` — initial file with `## Extension Contract` section
- `docs/extending.md` — consumer-facing extension guide: stable API surface (the two `@` slot lines, CLAUDE.md header names), what to express by behavior description vs. what to avoid, `.local.md` use-case guidance

### Phase 2: Extract skills

Extract each skill in dependency order: /explore first (fewest changes), then
/design, /prd, /plan, /work-on last (most changes). For each skill:

1. Copy SKILL.md and references/ directory to shirabe
2. Add `@` extension slot lines immediately after the closing `---` of the frontmatter
   block, before any prose content
3. Remove project-specific content as audited (see Phase 3 research)
4. Update relative paths to helpers (they remain at `../../helpers/`)
5. Replace internal skill invocations with generic "consult your project's
   equivalent skill" text or remove entirely
6. Replace path-based visibility heuristics with CLAUDE.md header references

Estimated removals per skill:
- /explore: ~5 lines (~1%)
- /design: ~65 lines (~19%)
- /prd: ~40 lines (~12%)
- /plan: ~55 lines (~14%)
- /work-on: ~45 lines (~33%)

### Phase 3: Scripts

Copy generic lifecycle scripts from the source plugin to `shirabe/scripts/`:
- `transition-status.sh` — design doc status transitions (generic)

Scripts that are specific to the source plugin's label vocabulary (e.g.,
`swap-to-tracking.sh`) are not included. Consumers that need label lifecycle
automation provide their own scripts, invoked from their extension files.

### Phase 4: Validate with a real extension

Verify the extraction by authoring a minimal extension file for at least one
skill, installing it in a test project, and confirming:
- Extension file loads correctly (0 tool calls, output reflects extension)
- Missing extension file produces clean fallback behavior
- `.local.md` variant loads on top of the committed extension

Deliverable: test cases TC-001 through TC-008 (extension load, silent skip, layering,
and `@path` visibility across Claude Code installation modes) committed to a
`tests/` directory or equivalent, serving as the regression harness for future
Claude Code version and model updates.

## Security Considerations

shirabe ships markdown files and shell scripts loaded into LLM context and executed
via the Bash tool. It does not download or compile code at install time. Shell
scripts in `scripts/` execute via the Bash tool when invoked by a skill and carry
the same trust as the plugin's markdown content.

**Extension file trust**: extension files at `.claude/shirabe-extensions/` are
privileged configuration equivalent to CLAUDE.md. They are injected directly into
LLM context before the skill executes, with no sanitization layer between file
content and the model. An extension file can inject arbitrary instructions, including
instructions that invoke tools or alter skill behavior. Teams should apply the same
review scrutiny to extension files in PRs as they apply to CLAUDE.md changes.

**`.local.md` files**: gitignored personal extension files receive the same trust
as committed extension files at runtime. The primary concern is intentional policy
bypass by a developer — a `.local.md` file can inject instructions that deviate
from team-agreed conventions without any audit trail. Teams with compliance
requirements should decide whether to permit `.local.md` use and document the
decision as a team convention.

**Supply chain**: shirabe itself is the supply chain dependency. A compromised
plugin release could ship malicious SKILL.md or script content. The blast radius
is bounded by Claude Code's tool approval model — destructive Bash calls still
surface for user confirmation unless explicitly pre-approved. Consumers should pin
to a known-good version and audit the plugin repo before adoption. No external
URLs, downloads, or dynamic content loading occur.

## Consequences

### Positive

- Downstream consumers extend skills without forking or touching shirabe source
- Extension files express intent ("also invoke X when doing Y") rather than structure;
  they survive most shirabe updates without changes
- CLAUDE.md-level behavior (visibility, scope, label vocabulary) is unchanged for
  consumers who already use those headers
- Extension loading is deterministic — 0 LLM tool calls — making skill behavior
  predictable across model versions
- The `.local.md` pattern gives individuals personal workflow customizations that
  don't pollute the shared repo
- The base SKILL.md format follows the Agent Skills open standard; shirabe can
  ship a parallel `.cursor-plugin/plugin.json` manifest to support Cursor users
  without any changes to the `skills/` directory

### Negative

- Raw `@path` text remains visible in skill context when extension file is absent;
  not a confirmed failure mode, but a behavioral dependency on the LLM ignoring it
- No validation feedback when an extension file is misconfigured or misnamed; silent
  failures require manual debugging (check file exists, check @ line matches filename)
- Breaking change detection is informal — a CHANGELOG convention, not enforced by
  tooling; consumers must opt in to monitoring it
- Each skill adds two lines of `@` overhead even when no extension exists (~100 tokens
  per skill, ~500 tokens total across all five)
- Extension context is available in the top-level skill invocation but its propagation
  into any sub-operations dispatched by a skill (e.g., subagent prompts) is not
  guaranteed; consumers relying on extension content for sub-operation behavior should
  verify propagation or explicitly carry the context forward
- The per-skill `@` extension mechanism is Claude Code-specific; Cursor users can
  use the base skills (portable via dual plugin manifests) and CLAUDE.md-equivalent
  project context headers, but have no per-skill extension point equivalent

### Mitigations

- Raw `@path` visibility: the test suite (TC-001 through TC-008) runs as a regression
  harness on Claude Code version upgrades and model updates; any change in LLM behavior
  toward `@path` text is caught before release
- No validation: document the convention clearly; extension file naming errors manifest
  as the skill running in base-only mode, which is safe if unexpected
- Informal contract: treat `@` slot lines and phase names as stable API with a declared
  policy; CHANGELOG.md breaking-change section is the minimum viable signal for the
  current number of consumers
