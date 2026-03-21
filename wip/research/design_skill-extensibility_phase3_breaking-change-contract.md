# Phase 3 Research: Breaking Change Contract

## Questions Investigated

1. What can change in a base SKILL.md without breaking extension files?
2. What extension file content is fragile vs resilient?
3. How do comparable markdown-based systems handle versioning?
4. What is the minimal viable breaking change signal?
5. How do other Claude Code plugins handle this?

---

## Findings

### 1. What can change in a base SKILL.md without breaking extension files?

The two-layer design (confirmed in DESIGN-skill-extensibility.md and Phase 1 research)
creates an asymmetric relationship: extension files express intent in prose, while base
SKILL.md files control structure. Changes to base SKILL.md fall into two categories.

**Non-breaking changes:**

- **Rewording phase descriptions.** Extension files reference behaviors by intent ("when
  triaging issues"), not by quoting prose from the base skill. LLMs interpret intent
  against the current skill content regardless of wording changes.

- **Adding new phases at the end.** New phases don't remove or reorder existing context.
  Extension content loaded at skill start remains in context throughout.

- **Adding new CLAUDE.md headers.** CLAUDE.md headers are read by skills using header
  names. A new header not referenced in extension files has no effect on existing
  extension behavior.

- **Changing helper file paths.** Extension files loaded via `@` includes in SKILL.md
  don't reference helper file paths. The base skill reads its own helpers internally.
  Extension files that reference helpers by path (e.g., `../../helpers/label-reference.md`)
  would break, but that pattern is project-specific (tools repo) rather than extension
  file content.

- **Changing phase file content.** Phase reference files (like `phase-1-setup.md`) are
  read by the LLM during execution, not by the `@` include mechanism. Extension content
  loaded at skill start remains in the LLM's context when the phase file is later read.
  Phase file rewrites don't break extension behavior — they may conflict with it if
  the base skill's instructions directly contradict an extension's instructions, which
  is a semantic conflict, not a loading failure.

- **Adding new `@` extension slots.** New `@.claude/skill-extensions/<name>/phase-N.md`
  lines added to SKILL.md silently skip when the file is absent. Downstream consumers
  who don't create these files are unaffected.

**Breaking changes:**

- **Removing the `@.claude/skill-extensions/<name>.md` line from SKILL.md.** The
  extension file exists on disk but is never loaded. Symptom: all extension behavior
  silently stops. This is the highest-severity breaking change — no error, no warning,
  and the regression is invisible to the consumer.

- **Renaming phases that extension files reference by name.** If an extension file says
  "when executing Phase 0: Setup" and the base skill renames the phase to "Phase 0:
  Context Injection," the LLM may fail to map the extension's reference to the current
  phase. This is a semantic breakage, not a loading failure — it depends on how precisely
  the extension wording matched the old name.

- **Reordering phases in ways that conflict with extension instructions.** An extension
  that says "before Phase 1, also invoke X" depends on Phase 1's meaning. If phases
  are reordered, the extension now injects behavior into a different workflow position.

- **Renaming CLAUDE.md headers that skills read.** If the base skill reads
  `## Repo Visibility` and shirabe renames the expected header to `## Visibility`, the
  skill stops detecting visibility. Extension files that don't reference CLAUDE.md headers
  are unaffected, but CLAUDE.md-dependent behavior silently degrades.

- **Changing the semantics of existing CLAUDE.md headers.** If `## Planning Context:
  Tactical` previously meant "create implementation issues" and gets redefined to mean
  something different, all downstream configurations using that header are silently
  misinterpreted.

**Borderline changes (context-dependent):**

- **Adding new phases in the middle of a workflow.** Inserts a new phase between existing
  ones. Extension files that reference phases by number ("Phase 2: Introspection") may
  apply their content to the wrong phase. Extension files that reference phases by function
  name ("when introspecting the issue") are more resilient.

- **Splitting a phase into two phases.** Similar to insertion — prose-based extensions
  that reference the original phase name may bind to the first half, the second half,
  or both, depending on LLM interpretation.

---

### 2. What extension file content is fragile vs resilient?

The extension mechanism produces an LLM-read document, so "breaking" is probabilistic,
not binary. The following analysis reflects failure modes in practice.

**Fragile (high breakage risk):**

- **References to phase numbers:** "when executing Phase 0" — phase numbers are renumbered
  when phases are inserted or reordered. The work-on skill, for example, has 7 phases
  (0-6); inserting a phase shifts all subsequent numbers.

- **References to specific file paths:** "read references/phases/phase-0-context-injection.md"
  — internal reference file renames are explicitly non-breaking for the `@` mechanism
  but break any extension prose that quotes the path.

- **Direct quoted strings from base skill:** "after the step where you create
  `wip/issue_<N>_baseline.md`" — ties the extension to specific artifact naming. If the
  base skill changes artifact names, the extension's instruction becomes dangling.

- **Conditional logic on exact header values:** "if `## Planning Context` is `Strategic`"
  — fragile if the header is renamed or its vocabulary changes (e.g., from `Strategic`
  to `Vision`).

**Resilient (low breakage risk):**

- **References to skill behaviors by description:** "when triaging issues" — behavioral
  descriptions survive phase renaming and reordering because the LLM matches the
  description to current skill content semantically.

- **Additive instructions without phase anchoring:** "also invoke the upstream-context
  skill when starting from an issue with needs-triage label" — doesn't bind to a specific
  phase; the LLM applies it to the appropriate point in execution.

- **References to CLAUDE.md headers by stable names:** "when `## Repo Visibility` is
  `Public`" — resilient as long as the header name and vocabulary are stable. Matches
  the design intent of CLAUDE.md as a stable interface layer.

- **Tool/skill invocation instructions:** "invoke the `upstream-context` skill" — the
  invocation instruction is pure addition. It doesn't depend on base skill structure
  unless the base skill explicitly conflicts with it.

The design doc's principle that extension files express intent rather than mechanism is
validated here. Intent-expressing extensions are the resilient ones. Mechanism-expressing
extensions (referencing specific file paths, quoted artifact names, phase numbers) are fragile.

---

### 3. How do comparable markdown-based systems handle versioning?

**Claude Code plugin.json `version` field:**

The `version` field appears in some plugin manifests (shirabe has `0.1.0`; stripe has
`0.1.0`; code-simplifier, claude-md-management, and claude-code-setup have `1.0.0`).
The example-skill frontmatter also supports a `version` field. However, there is no
evidence of Claude Code consuming this version field for compatibility checks, dependency
resolution, or change notification. It's metadata for humans, not enforced by the platform.

The cache directory structure at `~/.claude/plugins/cache/tsukumogami/tsukumogami/0.1.0/`
shows version-tagged caching — Claude Code caches by version number. This means a version
bump causes re-download, but there is no mechanism to notify downstream consumers that
their extension files need updating.

**SKILL.md frontmatter `version` field:**

The example-skill SKILL.md uses `version: 1.0.0` in its frontmatter. This is recognized
by `claude plugin validate` but appears to be informational — it's not used for
compatibility enforcement or extension contract signaling.

**Claude Code's own CHANGELOG:**

Claude Code (`~/.claude/plugins/marketplaces/claude-code-plugins/CHANGELOG.md`) has a
detailed per-version changelog focused on platform behavior, not plugin API contracts.
The CHANGELOG documents platform-level changes (new hook events, tool behaviors,
frontmatter fields) rather than how individual plugins should version their extension APIs.

**Comparable markdown-based systems in the wild:**

No installed plugins expose a formal extension contract or breaking change signal. The
Anthropic-published plugins (feature-dev, skill-creator, frontend-design) have no version
fields in their plugin manifests and no extension points. They're standalone skills, not
extensible bases. Neither the marketplace nor the cache directories contain any files that
look like "extension API" declarations.

**Relevant observation from the CHANGELOG:**

Claude Code 2.1.78 added `${CLAUDE_PLUGIN_DATA}` for plugin persistent state. This is
the kind of platform addition that could enable future extension versioning (an extension
could write its expected shirabe version to plugin data and shirabe could check it) but
that mechanism doesn't exist today.

---

### 4. What is the minimal viable breaking change signal?

Four options were evaluated:

**Option A: Semver on the plugin (consumer checks version)**

Shirabe bumps its semver on breaking extension changes. The tools repo pins to a semver
range (`"shirabe": "^1.0.0"`). When shirabe ships a breaking change, the major version
increments and the tools repo's pin holds at the prior major.

*Problem:* Claude Code has no semver pinning mechanism for plugins. The cache stores
versions but install/update commands don't appear to support version constraints. This
option requires a Claude Code platform feature that doesn't exist.

**Option B: CHANGELOG.md convention for breaking changes**

Shirabe maintains a CHANGELOG.md with a dedicated "Breaking: Extension Contract" section
for breaking changes. Consumers check the changelog before updating. The tools repo's
update workflow includes "review shirabe CHANGELOG for extension contract changes."

*Assessment:* Works with zero new infrastructure. Requires human discipline but is
realistic for one consumer (tools repo). The CHANGELOG section header can be machine-grep-able
(`## Breaking: Extension Contract`) enabling a simple CI check that blocks auto-update
if a breaking section exists since the last reviewed version.

*Weakness:* Silent if the consumer auto-updates without reading the changelog. No
enforcement mechanism.

**Option C: Extension compatibility header in SKILL.md**

SKILL.md includes a metadata line like:

```
extension-api: v1
```

Or within a comment block visible to the LLM but not executable. The tools repo's
extension files begin with:

```
# Extension for shirabe/explore (extension-api: v1)
```

The LLM can surface a mismatch warning if the header version in SKILL.md doesn't
match what the extension file declares.

*Assessment:* Clever but unreliable. The match check is LLM-interpreted, so it's a
probabilistic signal, not a guarantee. A mismatch won't produce a hard error — at best
it produces a warning that the LLM might or might not surface. The version string must
be maintained in two places (SKILL.md and every extension file).

*Strength:* Self-documenting. A developer reading the extension file knows what
version of the shirabe API it targets.

**Option D: No formal signal — rely on intent-expressing extensions**

The design already advocates for extension files that express intent rather than
mechanism. If consumers follow this pattern, most shirabe updates are automatically
non-breaking. The breaking change surface shrinks to:

1. Removing `@` extension slot lines (catastrophic, detectable by grep)
2. Renaming CLAUDE.md headers (affects CLAUDE.md consumers, not just extension files)
3. Major phase restructuring (inserts/removals, not rewording)

For these three cases, a CHANGELOG with explicit notation and a shirabe release policy
("extension slots are never removed without a major version bump") is sufficient.

*Assessment:* Viable for one consumer. Scales poorly to many consumers with complex
extension files that drift toward mechanism-expressing patterns over time.

**Recommended minimum viable signal:**

CHANGELOG.md with a distinct section header for extension contract changes, combined
with a shirabe release policy declaring that:

1. Extension slot lines (`@.claude/skill-extensions/<name>.md`) are never removed
   without a major version bump
2. Phase names used in the workflow overview table are stable; internal reference file
   names are not part of the contract
3. CLAUDE.md headers that skills read are listed in the README as stable API

This is Option B with explicit policy commitments that make the breaking change surface
small and predictable. Option C's compatibility header can be added later as a
self-documentation aid without being a hard contract.

---

### 5. How do other Claude Code plugins handle this?

No installed plugin exposes an extension mechanism comparable to shirabe's two-layer model.

All Anthropic-published marketplace plugins (feature-dev, skill-creator, frontend-design,
code-simplifier, claude-md-management, claude-code-setup, example-plugin) are standalone
skills intended to be used as-is, not extended. They have no `@` include lines for
downstream consumers.

The tsukumogami plugin (the tools repo's current plugin) has no version in its plugin.json
and no extension mechanism — it's the monolithic approach that shirabe is replacing.

The frontend-design plugin uses commit-hash versioning in the cache (`205b6e0b3036`,
`6b70f99f769f`, etc.) rather than semver, indicating it's installed from a git source
without formal release tags.

No plugin in the marketplace or cache shows a `breaking-changes:` section, `extension-api:`
field, or any cross-plugin compatibility mechanism. This is a greenfield design space —
shirabe would be the first plugin to define an extension contract.

The closest analogues to versioned extension APIs in the broader ecosystem are:

- **OpenAPI specification files:** Machine-readable contracts with explicit `version`
  fields. Not applicable here — skills are prose, not structured schemas.

- **Gatsby theme shadowing:** Files in a specific directory shadow files in the base
  theme. Renaming a file in the base theme breaks shadows silently. Gatsby handles this
  by treating file paths as the stable API and keeping them stable across minor releases.
  The parallel to shirabe: the `@` include paths are the API surface; keeping them stable
  is the contract.

- **WordPress hooks system:** Plugins register against named hooks (`add_action('init', ...)`).
  Hook names are stable across WordPress versions; they're never removed without a
  deprecation cycle. The parallel: shirabe's phase names in the workflow overview table
  could be treated as named hooks — stable identifiers that extension files reference.

---

## Implications for Design

**The extension API surface is smaller than it appears.** Breaking changes cluster around
three things: (1) `@` slot removal, (2) phase name changes in the workflow overview, and
(3) CLAUDE.md header renames. Everything else — phase file rewording, helper file renames,
new phases added, new CLAUDE.md headers — is safely non-breaking.

**Phase numbers are a trap.** Extensions that reference phases by number ("Phase 2:
Introspection") will break on any insertion or deletion. The workflow overview table in
SKILL.md should be treated as a public API: phase names (functional, not ordinal) belong
there; phase numbers are implementation detail. The work-on skill uses both ("0. Context
Injection", "1. Setup"). Extension files should be guided to use the functional name, not
the ordinal.

**The CHANGELOG is the right minimal investment.** A formal `extension-api: v1` header
in SKILL.md adds friction without adding enforcement. A CHANGELOG with a clearly marked
section for extension contract changes, combined with a release policy that treats `@`
slot lines and phase names as stable API, provides the same signal with less overhead.

**Resilience through documentation, not enforcement.** Because the mechanism is LLM-read
markdown, no tooling can enforce that extension files stay intent-expressing rather than
mechanism-expressing. Documentation of the contract (what to reference, what to avoid)
is the only lever available. A `docs/extending.md` in shirabe should specify the stable
vs unstable API surface and recommend intent-expressing patterns.

**One consumer simplifies the calculus.** For the tools repo as the sole consumer,
informal release coordination (check the changelog, revalidate extensions on shirabe
updates) is realistic. Formal versioning becomes more important if shirabe has 3+ consumers
with independent extension files that may drift toward mechanism-expressing patterns.

---

## Surprises

**The LLM is the runtime, so "breaking" is probabilistic.** In a compiled system, a renamed
function is a hard error. In this system, a renamed phase is a soft error — the LLM may
still map the old name to the current behavior, or it may not. This makes the breaking
change contract fuzzy at the edges. The category of "breaking" that matters most is
structural (slot removal, header rename) rather than semantic (phase rewording), because
structural breaks are binary failures while semantic breaks are degradations.

**No other plugin has solved this.** The marketplace survey found zero plugins with
extension mechanisms. Shirabe is designing in an empty space — there are no prior art
patterns to adopt or avoid. The Gatsby/WordPress analogues are useful frames but don't
map cleanly to LLM-read prose.

**The `@` mechanism visibility gap creates an unexpected invariant.** Because missing
extension files are silent, the only way to know an extension is active is to inspect
the stream-json output for raw `@path` text absence. This gap inverts the normal
expectation: in a code system, you'd test that behavior is correct; here, you must also
test that the extension was loaded at all. This has an implication for breaking change
detection: if shirabe removes a slot, the tools repo has no automated way to detect it
unless CI tests the extension's effects, not just the slot's existence.

**Version fields in plugin.json and SKILL.md frontmatter are decorative.** They're not
consumed by Claude Code for any compatibility or dependency logic. The cache structure
uses version strings for keying, not for constraint satisfaction. Semver pinning of
downstream consumers is not a viable mechanism given the platform.

---

## Summary

The breaking change contract for shirabe extension files has a small, well-defined core:
removing `@` extension slot lines, renaming phases referenced in the workflow overview,
and renaming CLAUDE.md headers that skills read are the three categories of change that
break downstream extension files. Everything else — rewording, phase file refactors,
new phases added, new helpers — is non-breaking.

Extension file resilience correlates directly with how intent-expressing vs
mechanism-expressing the content is. References to behaviors by description ("when
triaging issues") survive nearly all skill updates. References to phase numbers, internal
file paths, or quoted artifact names are fragile and should be discouraged in documentation.

No other Claude Code plugin exposes an extension mechanism, so shirabe is designing without
prior art. The minimal viable breaking change signal is a CHANGELOG.md with a dedicated
section for extension contract changes, combined with a declared release policy that treats
`@` slot lines and phase names in the workflow overview as stable API. Formal version
headers in SKILL.md are optional self-documentation aids, not enforcement mechanisms.

For the tools repo as the sole initial consumer, this lightweight convention is sufficient.
If shirabe acquires multiple consumers with complex extension files, the calculus shifts
toward stronger signals — but that problem can be deferred until it materializes.
