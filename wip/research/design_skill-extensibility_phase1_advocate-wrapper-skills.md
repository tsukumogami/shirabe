# Advocate: Wrapper Skills

## Approach Description

Downstream creates a separate Claude Code plugin with wrapper skills that replace
the base shirabe skills under a different namespace (e.g., `/tsukumogami:explore`
instead of `/shirabe:explore`). Each wrapper SKILL.md includes the project-specific
preamble and then either reads the base shirabe SKILL.md via a Read instruction or
duplicates the base content inline with modifications.

Key constraint: Claude Code has no cross-plugin skill invocation. A wrapper can't
call `/shirabe:explore` as a sub-call. Instead, the wrapper SKILL.md bridges the
gap one of two ways:

- **Read delegation**: The wrapper's SKILL.md says "Read the base shirabe SKILL.md
  at `<path>` and follow those instructions, applying the overrides above." This
  works when shirabe's install path is known and stable.
- **Inline duplication**: The wrapper copies the base SKILL.md content into its own
  file and modifies it. No runtime delegation.

The tools repo currently uses a variant of this pattern: it ships its own plugin
(`tsukumogami`) with its own `/explore`, `/design`, `/prd`, `/plan`, and `/work-on`
skills, all of which contain the full workflow logic including project-specific
behavior. There is no base shirabe plugin to delegate to yet, so the current
implementation is effectively inline duplication.

---

## Investigation

### 1. Current tools plugin structure

The tools repo ships a plugin at:
`/home/dangazineu/dev/workspace/tsuku/tsuku-5/private/tools/plugin/tsukumogami/`

The plugin defines 51 skills, agents, and helpers under the `tsukumogami` namespace.
The five target skills (`explore`, `design`, `prd`, `plan`, `work-on`) each have:

- A `SKILL.md` with the full workflow logic (hundreds of lines)
- A `references/phases/` directory with phase files loaded on demand
- Shared helpers accessed via relative paths (`../../helpers/`)

The `explore/SKILL.md` alone is 454 lines. It contains the complete workflow:
artifact type routing, crystallize framework, convergence patterns, handoff
formats, and all phase execution logic. Project-specific coupling is woven in:
visibility detection from CLAUDE.md, scope detection, label vocabulary references,
cross-repo issue handling rules, and private-content routing.

**Finding**: The current tools plugin is already using the "full ownership" form of
the wrapper pattern — it owns the complete skill logic with project-specific
behavior embedded. There is no delegation to a base skill because no base skill
exists yet.

### 2. Does the tools repo use wrapper delegation for any skills?

No. Every skill in the tools plugin is self-contained. There are no Read
instructions that say "load another plugin's SKILL.md." The pattern that appears
closest to delegation is internal: skills invoke each other's logic via explicit
"Read X SKILL.md and follow it" instructions within the same plugin. For example,
`work-on/SKILL.md` says:

> "Invoke the `go-development` skill for code quality requirements and the
> `pr-creation` skill for PR requirements"

This works because both skills are in the same plugin and the relative paths are
stable. Cross-plugin invocation doesn't exist.

### 3. Can a wrapper in the tools plugin read shirabe's SKILL.md via a Read instruction?

The mechanism exists: the LLM can Read any file it has access to. The question is
whether the path is stable and resolvable.

**When shirabe is installed as a submodule:**
The shirabe files would live at a known path relative to the workspace root, such
as:
```
/home/dangazineu/dev/workspace/tsuku/tsuku-5/private/tools/plugin/shirabe/skills/explore/SKILL.md
```
Or, if installed as a Claude Code plugin (registered separately):
```
~/.claude/plugins/shirabe/skills/explore/SKILL.md
```

The path in the second case is not predictable from the wrapper's perspective
because it depends on how the user installed shirabe (plugin registry, local path,
symlink). `${CLAUDE_PLUGIN_ROOT}` gives the current plugin's root, not any other
plugin's root. There is no equivalent variable for external plugins.

**When shirabe is installed as a second plugin alongside the tools plugin:**
The wrapper SKILL.md would need to hardcode or inject the path to shirabe's
SKILL.md. Claude Code provides no mechanism to resolve another plugin's location
at runtime. The wrapper would have to say something like:

```
Read ~/.claude/plugins/shirabe/skills/explore/SKILL.md and follow its instructions,
but apply the following overrides first: ...
```

This path is user-environment-specific. It breaks when:
- shirabe is installed to a custom location
- The user is on a different OS with a different home directory layout
- shirabe is installed as a submodule rather than a standalone plugin
- Claude Code changes its plugin installation directory

**When shirabe is installed as a submodule inside the tools plugin:**
The path becomes predictable relative to the tools plugin root. But this collapses
the "two separate plugins" model into a single plugin namespace — the tools plugin
would contain shirabe's files at a known path, and wrapper skills could reference
them reliably. This is effectively a consumption model choice, not just a wrapper
strategy choice.

**Conclusion on path resolution**: Read delegation is feasible only when the
consumption model pins the base skill's location. For submodule consumption, paths
are stable. For two-plugin consumption (the target end-state per the exploration
findings), paths are not deterministically knowable from within the wrapper SKILL.md.

### 4. Duplication/drift risk assessment

The wrapper approach via inline duplication creates a fork-in-practice, even if the
intent is to wrap rather than fork.

**What "drift" looks like in practice:**

The `explore/SKILL.md` is 454 lines. When shirabe updates the base skill — adding
a new phase, changing the crystallize framework, adding a new artifact type routing
row — the wrapper maintainer must:

1. Notice the update (no notification mechanism; requires watching shirabe releases)
2. Evaluate which changes are relevant to their customizations
3. Manually merge the changes into the duplicated SKILL.md
4. Repeat for every updated skill

For the five target skills, each SKILL.md runs 200-450 lines. The reference phase
files add hundreds more lines that the wrapper would also need to own (or delegate
to via Read, with the same path-stability problem).

**Concrete example from the current tools plugin:**
`plan/SKILL.md` is 400 lines with 7 phases, each referencing a phase file.
Phase files like `phase-4-agent-generation.md` run hundreds of lines each. A wrapper
that duplicates the SKILL.md still delegates phase-file reading to the base (if using
Read delegation), or must copy all 7 phase files too. Phase files are even more
volatile than SKILL.md because they contain implementation details that change with
every workflow refinement.

**Conclusion on drift**: When shirabe updates, downstream wrappers need manual
review and update for every changed skill. With 5 skills and frequent workflow
refinements (tools PR #601 was a full opinionated refactor), drift is not a
theoretical risk — it's the default outcome if downstream doesn't actively track
upstream.

### 5. Naming conflicts if both shirabe and tools define `/explore`

Claude Code's skill system uses namespaced invocation: `/plugin-name:skill-name`.
When installed, users invoke `/shirabe:explore` and `/tsukumogami:explore` as
distinct skills. There is no conflict between them.

However, Claude Code also supports unnamespaced invocation (`/explore`) when the
skill name is unambiguous across installed plugins. If both plugins define a skill
named `explore`, the behavior on unnamespaced invocation is undefined by the Claude
Code documentation. Likely behavior (based on flat pool semantics): both SKILL.mds
get surfaced, and the LLM sees potentially contradictory instructions.

**Practical impact:**
- Users who type `/explore` get unpredictable behavior if both plugins define it
- The CLAUDE.md auto-load context for skills named `explore` would include both
- Users would need to train themselves to type the full namespaced form

**Mitigation available**: The tools plugin could name its wrapper skills differently
(`/tsukumogami:explore` stays, doesn't register a generic `explore`). But this
changes the invocation surface for existing users of the tools plugin who currently
type `/explore` and get the tsukumogami skill. It also means that unnamespaced
invocation becomes `shirabe` skills by default if shirabe is installed alongside.

**Conclusion on naming conflicts**: Namespaced invocation is safe. Unnamespaced
invocation has undefined behavior on conflict. The tools plugin's current users
invoke `/explore` (unnamespaced) and expect tsukumogami behavior — adding shirabe
as a second plugin creates ambiguity on every unnamespaced invocation.

### 6. Existing research context

The exploration findings (wip/ artifacts in shirabe) already characterized the
wrapper approach:

> "Wrappers / fork: downstream copies skills and modifies them. No coordination
> with upstream. Breaks on shirabe updates."

The design doc draft (`DESIGN-skill-extensibility.md`) lists "Wrapper skills" as
Option 3 with the assessment:
- Pro: Full control without modifying shirabe files
- Con: Claude Code has no cross-plugin skill invocation — wrappers can't call shirabe skills
- Con: Requires maintaining full skill copies for any customization

The exploration team had already identified the core constraint and dismissed
wrappers as the leading candidate before the design doc phase. This investigation
confirms and extends those findings with concrete path analysis and drift mechanics.

---

## Strengths

**Full control.** The wrapper plugin owns the complete skill definition. There are
no contracts to respect, no extension points to design around, no base SKILL.md
format to preserve. Project-specific behavior can go anywhere in the skill.

**No new conventions.** Downstream doesn't need to learn an extension file format,
file naming convention, or loading contract. The wrapper is just a regular skill.
Teams unfamiliar with shirabe's internals can modify the wrapper SKILL.md directly.

**Works today.** The tools repo is already using this model. The `tsukumogami`
plugin already owns full copies of all five skills with project-specific behavior
embedded. No migration is needed to "adopt" the wrapper approach — the tools repo
is already there.

**Install-model agnostic in principle.** If Read delegation is not used (inline
duplication instead), the wrapper has zero runtime dependency on shirabe's file
paths. The wrapper functions identically regardless of how or whether shirabe is
installed.

**Namespace safety for namespaced invocation.** `/tsukumogami:explore` and
`/shirabe:explore` can coexist without conflict as long as users use namespaced
invocation. Two teams can independently maintain skills covering the same workflow
for their own use cases.

**Comprehensible to new contributors.** A developer looking at the tools plugin
sees a complete, self-contained skill. There's no "see also" indirection through
a base plugin. The full behavior is in one file.

---

## Weaknesses

**Drift is the default outcome.** Any shirabe update — new phase, changed artifact
format, new routing rule — requires a manual decision from the wrapper maintainer:
ignore, adopt, or adapt. With 5 skills and active upstream development, maintenance
load accumulates. There's no mechanism to distinguish "shirabe fixed a bug in the
base workflow" from "shirabe changed the workflow in a way I don't want."

**No shared improvements propagate automatically.** When shirabe improves its
crystallize framework or adds a new handoff artifact format, wrapper users don't
benefit. The improvement must be manually backported to each wrapper.

**Phase files create a duplication explosion.** SKILL.md is just the top of the
iceberg. The `plan` skill has 7 phase files, `explore` has 6, `design` has 6,
`work-on` has 7, `prd` has 4. Full ownership means owning all of these too —
or using Read delegation for the phases, which reintroduces the path-stability
problem.

**Read delegation requires stable paths.** The only way to avoid full duplication
is Read delegation to the base SKILL.md. This is feasible only with submodule
consumption (known paths) and fails entirely with two-plugin consumption (paths not
deterministically knowable from the wrapper). Since two-plugin consumption is the
intended end-state (once Claude Code ships dependency support), Read delegation
provides only a temporary partial solution.

**Unnamespaced invocation conflicts.** If both shirabe and the tools plugin are
installed, users who type `/explore` get ambiguous behavior. Fixing this requires
either not installing both simultaneously or training users to use namespaced forms.

**Context overhead for inline duplication.** Duplicate SKILL.mds consume LLM
context twice — once when auto-loaded for routing, once when the specific skill
runs. A session with both shirabe and the tools plugin installed would load both
`explore` skills into the same context.

**Extraction doesn't improve the situation.** Whether shirabe extracts generic
skills or not, the wrapper approach means the tools repo keeps owning its own
copies. Extraction creates a public reference implementation, but the tools repo
doesn't actually consume it — it just runs parallel to it.

---

## Deal-Breaker Risks

**Risk 1: Drift renders the wrapper obsolete.**
The tools repo currently runs the authoritative copy of the workflow skills.
After shirabe ships and iterates, the tools repo wrappers accumulate outdated
logic. Users who invoke `/tsukumogami:explore` get older behavior than users who
invoke `/shirabe:explore`. If the tools repo falls 3-6 months behind upstream, the
"wrapper" is effectively a fork with a different workflow. This risk is realized
passively — it doesn't require any active mistake.

Severity: High. The extraction project's explicit goal is to make the tools repo a
shirabe *consumer*, not a parallel maintainer. Wrappers defeat that goal.

**Risk 2: Phase file ownership makes wrappers impractical at scale.**
The five skills collectively have ~30 phase files. Inline duplication of all of
them creates an enormous maintenance surface. Read delegation of phase files from
within wrappers reintroduces path-stability problems. There is no clean path to
full-wrapper ownership of a skill as complex as `/plan` (7 phases, each with
hundreds of lines of instructions) without owning all the phase files.

Severity: High for `/plan`, `/design`, and `/work-on`. Lower for `/prd` and early
phases of `/explore`.

**Risk 3: Path instability breaks Read delegation across install models.**
If the tools repo uses Read delegation (wrapper SKILL.md points to base shirabe
SKILL.md via path), the path must be known at skill execution time. For the
target end-state (two installed plugins), there is no reliable way to construct
that path. `${CLAUDE_PLUGIN_ROOT}` gives the current plugin root only. The LLM
could attempt to locate shirabe's install path by checking common locations, but
this is fragile behavior-not-contract, and fails in unusual environments (custom
install locations, CI, containerized sessions).

Severity: Medium-to-High. Blocks the two-plugin consumption end-state entirely.
Degrades to inline duplication, which triggers Risk 1 and 2.

**Risk 4: No extensibility mechanism for fine-grained overrides.**
The wrapper approach provides "all or nothing" control. The wrapper either owns
the full SKILL.md (inline duplication) or delegates all of it (Read delegation
with no selective override). There's no mechanism to say "use the base explore
skill but change just the triage routing step in Phase 0." Wrappers that want to
customize a single phase must duplicate all phases to modify one. This is the
opposite of the principle of least surprise for downstream consumers.

Severity: Medium. The tools repo's actual customizations (label lifecycle, triage
routing, upstream-context invocation, private-repo handling) are concentrated in
specific phases. Full skill duplication to change one phase is disproportionate.

---

## Implementation Complexity

**Files to modify:**
If adopting wrappers formally (no change from today): 0 files to modify. The tools
repo already has wrappers. If formalizing "wrappers as the extension model" in
shirabe's design doc: 1 file (DESIGN-skill-extensibility.md).

If the decision is "tools repo adopts wrapper pattern going forward with Read
delegation after shirabe extracts the skills":
- 5 wrapper SKILL.mds to rewrite (one per skill)
- Each wrapper reads base SKILL.md at a path that must be determined by consumption
  model
- ~30 phase files: either duplicated (large scope) or delegated (path stability
  required)

**New infrastructure:**
No new infrastructure if using inline duplication. If using Read delegation: a
path resolution convention must be established and documented. No tooling provides
this — it would be documented convention only (e.g., "install shirabe as a submodule
at `../shirabe/` relative to tools plugin root").

**Estimated scope:**
- Formalizing today's status quo: small (0 code changes)
- Read delegation wrappers for 5 skills: medium (rewriting 5 SKILL.mds, establishing
  path convention, testing across install modes)
- Full inline duplication ownership including all phase files: large (duplicate ~35
  files, establish monitoring/sync process for drift)

---

## Summary

The wrapper approach is the current de facto reality in the tools repo — every
skill in the `tsukumogami` plugin is already a self-contained implementation that
embeds project-specific behavior. This gives it one genuine advantage: no migration
needed to adopt it formally, and no new abstractions for contributors to learn.

Two implementation paths exist within the wrapper approach, and both have hard
limits:

**Inline duplication** (the current state) converts shirabe extraction from a
consumption model into a parallel development track. The tools repo doesn't consume
shirabe; it runs alongside it. Drift is the default outcome, not a failure mode.
As shirabe iterates and improves, the tools repo wrappers fall behind. The stated
goal — make the tools repo a shirabe consumer rather than a parallel maintainer —
cannot be achieved this way.

**Read delegation** (wrapper delegates to base SKILL.md at runtime) partially
addresses drift but requires stable, predictable paths to the base skill. This
works under submodule consumption (where shirabe's files live at a known relative
path), but fails under the intended end-state of two separately-installed plugins,
where no mechanism exists to resolve another plugin's install location. Read
delegation also cannot selectively override individual phases without duplicating
the surrounding structure.

The naming conflict risk is real but manageable: namespaced invocation
(`/tsukumogami:explore`) avoids collisions, but unnamespaced invocation is
ambiguous when both plugins are installed simultaneously. The tools repo's existing
users invoke skills without namespaces today.

The wrapper approach's core problem isn't that it's technically wrong — it's that
it structurally fails the extraction project's stated objective. Extraction's value
is that the tools repo becomes a shirabe consumer. Wrappers make the tools repo a
shirabe parallel, not a consumer. All upstream improvements require manual
backporting. Phase-level customization requires disproportionate duplication.
Path resolution blocks the two-plugin end-state.

Wrapper skills are a reasonable short-term holding pattern if shirabe extraction
is delayed, or for projects that need total control and accept the maintenance cost.
They are not a viable extensibility mechanism for the stated design goals.
