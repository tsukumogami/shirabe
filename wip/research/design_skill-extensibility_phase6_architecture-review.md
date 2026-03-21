# Architecture Review: DESIGN-skill-extensibility

**Reviewer role:** Architecture — does this change respect the existing structural patterns, or does it introduce parallel/divergent patterns?

**Source:** `docs/designs/DESIGN-skill-extensibility.md` + supporting Phase 1–5 research files

---

## Question 1: Is the architecture clear enough to implement?

**Yes, with one gap.**

The core mechanism — two `@` include lines at the head of each SKILL.md, resolving from workspace root, silently skipping missing files — is well-specified and confirmed by testing (T1-T7). The data flow diagram is accurate and complete for the happy path. Component layout in the tree is clear.

The gap: Phase 2 says "add `@` extension slot lines at the head (after frontmatter)" but doesn't define what "after frontmatter" means precisely for SKILL.md files. SKILL.md frontmatter is a YAML block delimited by `---`. If the `@` lines go immediately after the closing `---` with no blank line, implementors may differ on whether a blank line separator is needed. The `@` mechanism is confirmed to work in both cases, but the instruction leaves room for inconsistency across the five skills. Worth a one-line clarification: "immediately following the closing `---` of the frontmatter block, before any prose."

The implementation phases are otherwise actionable. Each phase has a defined deliverable, and the extraction audit (Phase 3 research) gives concrete per-skill line counts that prevent scope ambiguity during execution.

---

## Question 2: Are there missing components or interfaces?

**Two missing components, one of which is structurally load-bearing.**

### Missing: `docs/extending.md`

The breaking change contract relies on documentation, not tooling. The Phase 3 research explicitly concluded: "Resilience through documentation, not enforcement." Yet the design doesn't include `docs/extending.md` as a deliverable. The contract is described in the design doc itself, but a design doc is an internal artifact — consumers need an external guide that defines:

- What constitutes the stable extension API (the two `@` slot lines, the CLAUDE.md header names in the Key Interfaces table)
- What to reference by behavior description vs. what not to reference by number (phase numbers are fragile)
- The `.local.md` use-case guidance for compliance-oriented teams

Without this file, the extension contract is discoverable only through the design doc, which is not a user-facing surface. This is structurally load-bearing: the breaking change contract is a policy commitment, not an enforcement mechanism. If it isn't documented where consumers can find it, the policy doesn't exist in practice.

**Classification: Missing deliverable. Should be added to Phase 1 (alongside CHANGELOG.md).**

### Missing: Phase 4 test surface for extension loading confirmation

Phase 4 ("Validate with a real extension") verifies that extension content appears in the skill's output. But the Phase 3 research identified a specific structural concern: "The `@` mechanism visibility gap creates an unexpected invariant. The only way to know an extension is active is to inspect the stream-json output for raw `@path` text absence."

The design's existing test cases (TC-001 through TC-008) are referenced as a regression harness for Claude Code version upgrades, but they aren't listed as deliverables and their content isn't specified in the design. Without at least naming what TC-001 through TC-008 test, Phase 4 validation criteria are informal ("confirming extension file loads correctly"). This is acceptable for the current scale (one consumer), but the test harness name implies more structure than exists.

**Classification: Advisory. The informal validation criteria are workable with one consumer. Becomes load-bearing if multiple consumers adopt the plugin.**

### Not missing: Label vocabulary mechanism

The design correctly identifies `## Label Vocabulary` in CLAUDE.md as the right home for label names rather than per-skill extension files. This is a structural simplification that eliminates duplication — one change point instead of five. The mechanism is clear: skills read from context; consumers write one section. No additional component needed.

### Not missing: CHANGELOG.md

The minimal viable breaking change signal (CHANGELOG with `## Breaking: Extension Contract` section + the three-point release policy) is adequate for the stated scale. The Phase 3 research confirmed that platform-level semver pinning isn't viable, and the formal `extension-api: v1` header was evaluated and rejected. The CHANGELOG approach is the right call.

---

## Question 3: Are the implementation phases correctly sequenced?

**Yes, with one observation.**

The dependency order is correct:
- Phase 1 (helpers) has no upstream dependencies and creates shared resources that Phase 2 skills need
- Phase 2 (skills) depends on helpers being present and runs in the right skill order (explore first, work-on last by project-specific content ratio)
- Phase 3 (scripts) is independent of both and could run in parallel with Phase 2, but sequencing it after is fine
- Phase 4 (validate) correctly comes last

One observation: the extraction audit shows /work-on has the highest project-specific content density (~33% removal) and is sequenced last. This is the right call for extraction ordering but means the first four skills extracted give misleading signal about the overall extraction complexity. /explore at ~1% removal is almost a free extraction — it shouldn't be used as a template for what the other extractions look like. Implementors should read the Phase 3 extraction audit before starting Phase 2, not just the Phase 2 summary. This is a planning note, not a sequencing problem.

The design correctly defers the consumption model (how tools repo wires up shirabe) to the consumer repo. That boundary is clean — shirabe's implementation phases stop at "working plugin" and don't attempt to manage the downstream migration. The Phase 3 consumption model research recommends submodule, but that's out of scope for this design, which is correct.

---

## Question 4: Are there simpler alternatives we overlooked?

**No meaningful simpler alternatives, but one underspecified escape hatch.**

The design's considered options section covers the realistic alternatives:
- CLAUDE.md-only: rejected correctly. It can't target per-skill behavior without requiring shirabe changes.
- Wrapper skills: rejected correctly. Cross-plugin path resolution doesn't work; name conflicts have undefined behavior for model-invoked activation.
- Two-layer (chosen): the right call.

The one underspecified escape hatch is the silent-skip behavior when an extension file is absent. The design acknowledges that "raw `@path` text remains visible in skill context when extension file is absent" as a consequence, and mitigates it with regression tests. But it doesn't specify what the LLM actually sees — it says "not a confirmed failure mode, but a behavioral dependency on the LLM ignoring it."

The Phase 1 research confirmed via testing that missing files produce silent skips and the raw `@path` text is "ignored in practice." But "ignored in practice" with the current model is not a guarantee with future models. The regression harness (TC-001 through TC-008) addresses this, but the harness isn't defined as a deliverable.

There is no simpler alternative that avoids this risk. The `@` mechanism is the only client-side, deterministic, zero-LLM-calls include mechanism available. The raw `@path` visibility is a known and accepted tradeoff, and the mitigation (regression tests on model updates) is the right response. Nothing simpler exists.

---

## Architectural Pattern Analysis

### Does this introduce parallel patterns?

No. The design uses exactly one mechanism for extension loading (`@` includes), one mechanism for project-wide settings (CLAUDE.md headers), and one mechanism for change notification (CHANGELOG). It doesn't introduce a second config parser, a second include mechanism, or a second way to load context. The `@` include is existing Claude Code functionality; the design routes extension loading through the existing mechanism rather than creating a new one.

### Does the component structure respect the existing layout?

The proposed `skills/`, `helpers/`, and `scripts/` directories in shirabe match the existing Claude Code plugin conventions visible in the current `.claude-plugin/plugin.json` and the tsukumogami plugin structure. The `koto-templates/` directory is already in the repo layout per CLAUDE.md; the design doesn't touch it.

The extension file location (`.claude/skill-extensions/`) is a net-new directory in consumer repos. It doesn't conflict with any existing convention in CLAUDE.md or the workspace structure. The `.gitignore` convention for `.local.md` files is consistent with the workspace's existing pattern for local developer state.

### Does the breaking change contract respect the existing stability surface?

The contract identifies the right API surface: the two `@` slot lines and the CLAUDE.md header names listed in the Key Interfaces table. These are the only things consumers can reference that survive base SKILL.md updates. The contract correctly excludes internal phase file names, helper file paths, and artifact naming conventions — these are correctly identified as internal implementation details, not public API.

The one structural risk the contract doesn't fully address: the CLAUDE.md headers table in the design lists `## Repo Visibility:`, `## Planning Context:`, and `## Label Vocabulary`. The first two already exist in shirabe's own CLAUDE.md. `## Label Vocabulary` is new — it's a contract addition that requires consumers to populate this header. The design doesn't specify what happens if a consumer omits `## Label Vocabulary` (skills presumably fall back to no label vocabulary, which is safe). This should be explicitly stated in the Key Interfaces table — whether the header is required or optional.

---

## Structural Findings

### Blocking

None. The core architecture is sound. The mechanism is proven. No pattern violations introduced.

### Advisory

**1. `docs/extending.md` is absent from deliverables.**
The breaking change contract is a policy commitment. Without a consumer-facing reference document, the policy isn't discoverable outside the design doc. This should be added as a Phase 1 deliverable alongside CHANGELOG.md. Phase 1 is the right phase because the helpers extraction can proceed without skills existing — and the extension guide describes the API surface that Phase 2 will implement.

**2. `## Label Vocabulary` header optionality is unspecified.**
The Key Interfaces table adds a new CLAUDE.md header without stating whether it's required. Skills reading an absent header need a defined fallback behavior. The table should include a "Required/Optional" column or equivalent note per header. Skills that degrade gracefully when the header is absent are fine; skills that produce undefined behavior are not.

**3. The test harness (TC-001 through TC-008) is named but not defined as a deliverable.**
Phase 4 references these test cases but they aren't produced as part of any phase. If the regression harness is the mitigation for the raw `@path` visibility risk, it needs to be a named deliverable in Phase 4, not an implied artifact from the exploration research.

### Out of Scope for This Review

- Whether the extraction line count estimates per skill are accurate (correctness question, not architecture)
- Whether the CHANGELOG.md convention is sufficient for the eventual number of consumers (scale question, deferred by design)
- Whether the consumption model (submodule vs. two-plugin) is the right choice (out of scope per Decision 5)

---

## Summary

The architecture is implementable as specified. No parallel patterns, no bypassed mechanisms, no dependency direction violations. The two gaps that matter: `docs/extending.md` should be a Phase 1 deliverable (the contract needs a consumer-facing surface), and the `## Label Vocabulary` header needs a stated fallback for the case where a consumer omits it. The test harness should be promoted from implied research artifact to named Phase 4 deliverable. None of these are blocking — the extraction can begin — but they should be resolved before Phase 4 validation begins.
