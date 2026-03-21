# Maintainability Review: Decision Framework Design

Reviewer focus: can this be built and maintained without becoming a tangled mess?

## 1. Phase File Explosion

### Current state

The plugin today has 38 phase files and 67 total .md files across 5 skills.
The design proposes adding:

- `skills/decision/`: 7 phase files + SKILL.md + agent-prompt template + decision report format spec + decision block format spec = ~11 new files
- `skills/design/`: 3 new phase files (decomposition, execution, cross-validation) + 1 modified (investigation) = net +3
- `skills/explore/`: 1 new phase file (phase-5-produce-decision.md) + updated crystallize-framework.md = net +1
- Cross-cutting reference files: decision block format spec, lightweight protocol spec, assumption tracking format = +3

**Post-implementation total: ~50 phase files and ~80+ total .md files across 6 skills.**

### The 150-line constraint is already violated

Today, 11 of 38 phase files exceed 150 lines. The worst offenders:
- phase-4-agent-generation.md: 437 lines
- phase-3-decomposition.md: 385 lines
- phase-7-creation.md: 359 lines
- phase-5-produce-deferred.md: 318 lines

The design acknowledges this constraint ("Phase files must stay focused and under 150 lines") but its own estimated line counts for the decision skill's Phase 6 (synthesis and report) are 130-160 lines -- already straddling the limit before real-world additions.

### Testing and validation story: absent

The design has no testing or validation mechanism for phase files. There's no CI check that verifies:
- Phase files are referenced by their SKILL.md
- Phase numbering is sequential and complete
- Resume logic matches the actual phase file set
- Cross-references between phase files resolve
- The compiled agent-prompt.md stays consistent with source phase files

This is a structural integrity problem. When you have 50+ files that must form coherent workflows, manual consistency is not sustainable. A renamed phase file silently breaks a workflow because the SKILL.md still references the old name, and nothing catches it until a user hits the failure at runtime.

**Risk level: High.** Without validation, phase file changes are a "hope it works" deployment.

## 2. Three-Way Format Coupling

The design introduces a decision block format that must be understood by:

1. **Decision block format spec** (the HTML comment delimiters + markdown structure)
2. **Decision report format** (the canonical output of the decision skill: Context, Assumptions, Chosen, Rationale, Alternatives, Consequences)
3. **Considered Options sections** in design docs (the existing format from `considered-options-structure.md`: `### Decision N: [Topic]` / `#### Chosen: [Name]` / `#### Alternatives Considered`)
4. **Assumption review surface** (wip/ artifact, terminal summary, PR body section)
5. **Lightweight protocol** (compact variant of the block format)

### How many files change for one format tweak?

Consider: "We want to add a Reversibility field to decisions."

Files that need updating:
1. Decision block format spec (full variant)
2. Decision block format spec (compact variant -- does it get Reversibility?)
3. Decision report format (canonical structure)
4. `considered-options-structure.md` (the design doc template)
5. `agent-prompt.md` (the compiled template)
6. Assumption review surface template (if Reversibility affects review)
7. Every phase file that writes or reads decision blocks (at minimum: decision skill Phase 6, design skill Phase 3 cross-validation, lightweight protocol spec)
8. Potentially the PR body template

That's 7-8+ files for adding a single optional field. And because these files live in different skills (`decision/`, `design/`, possibly `explore/`), there's no single grep that finds "all places that know about decision block fields."

### The adapter pattern is implicit

The design says decision reports "map to Considered Options sections" but doesn't specify who does the mapping, what the mapping rules are, or where they live. Is it a section in a phase file? A reference file? Inline in the design skill's cross-validation phase? This is the kind of implicit coupling that rots first -- the formats drift because nobody owns the translation contract.

**Risk level: High.** Format changes will be incomplete. Someone will update the decision block spec, forget the considered-options adapter, and produce design docs with mismatched structures.

## 3. Compiled Prompt Maintenance Problem

Decision 8 chose a monolithic template at `skills/decision/references/templates/agent-prompt.md` that condenses 7 phase files into ~25-40 lines each. This is the same pattern as plan's `agent-prompt.md` (220 lines).

### The drift mechanism

1. Someone modifies `skills/decision/references/phases/phase-2-alternatives.md` to improve alternative generation
2. The compiled `agent-prompt.md` still contains the old Phase 2 instructions
3. Standalone decision skill invocations (which read phase files) get the fix
4. Agent-spawned decision invocations (which receive the compiled prompt) don't
5. Nobody notices because both paths produce plausible output -- just different quality

This is worse than a breaking change. A breaking change fails visibly. Drift produces subtly different behavior between two invocation paths of the same skill.

### The plan skill's precedent

The plan skill already has this pattern with its `agent-prompt.md`. I checked: it's 220 lines, and it references `{{PLACEHOLDER}}` variables. But plan's agent prompt is simpler -- it sends agents to write issue bodies, a narrow task. The decision skill's agent prompt covers 4-7 phases of adversarial evaluation. The surface area for drift is larger.

### The fast-path stripping compounds it

The parent skill strips phases 3-5 for fast-path (Tier 3) decisions. That means the template must be structured so that phases 3-5 are cleanly removable. Any future edit to the template that creates cross-phase references (Phase 2 mentioning something Phase 4 refines) breaks fast-path stripping silently.

**Risk level: Medium-High.** The compiled prompt will drift from phase files within 3-4 months of active development. The fast-path stripping constraint makes the template fragile in non-obvious ways.

## 4. Cross-Cutting --auto Changes

### Scope of changes

The design says all 5 skills need --auto support. Let's count what changes:

- 5 SKILL.md files: flag parsing, mode resolution (flag > CLAUDE.md > default)
- Every phase file with an AskUserQuestion call: behavior branch (interactive vs auto)
- Assumption tracking: write to `wip/<workflow>_<topic>_assumptions.md`
- Terminal summary: print at workflow end
- PR body section: append assumptions

The design says 39 blocking points across 5 skills. That's 39 locations that need the same pattern:
1. Classify the decision (researchable / judgment / approval / safety)
2. In interactive mode: present via AskUserQuestion with evidence
3. In auto mode: follow recommendation, write decision block

### Copy-paste risk

There's no shared implementation. Each phase file independently implements the decision protocol. The design explicitly says "Changes to each skill's phase files to adopt research-first decision pattern" -- that's per-file changes, not a shared module.

Phase files are markdown instructions, not executable code. There's no way to extract a shared function. If the assumption tracking format changes (say, adding a confidence field), every phase file that writes assumptions needs manual updating.

### The 39 decision points aren't catalogued

The design says "39 blocking points" but doesn't list them. Without a manifest of which phase files contain decision points and what category each one is (researchable / judgment / approval / safety), there's no way to verify completeness during implementation or audit correctness later.

**Risk level: High.** A bug in the assumption tracking pattern (wrong wip/ file name, missing confidence level, malformed decision block) gets replicated 39 times. Fixing it requires finding all 39 instances by reading every phase file.

## 5. Scaling to 20+ Decisions

### The 10-decision design doc problem

This design itself has 10 decisions. The Considered Options section is 580+ lines. The decision manifest for this design would have 10 entries. That's already at the edge of what a human can review.

### Decision manifest scalability

The design specifies `wip/<workflow>_<topic>_decision-manifest.md` to index all decisions. For a 10-decision design, this manifest is a 10-row table. For a 20-decision design (plausible for a complex system redesign), it's 20 rows.

But the real problem isn't the manifest size -- it's the cross-validation phase. Decision 5 says "cross-validation runs once after all decisions complete." With 20 decisions, cross-validation must check each decision's assumptions against 19 other decisions' choices. That's O(N^2) comparison work. The single-pass constraint means conflicts found late in the check can't trigger restarts of decisions checked early (they already had their one restart).

### Parallel agent cost

Decision 4 says the design skill always uses Task agents, one per decision. For a 20-decision design, that's 20 parallel agents. Each gets a compiled prompt of ~4K tokens plus background context. The total context consumed by agent spawning alone is ~80K-120K tokens. That's a meaningful fraction of the context window used just for orchestration overhead.

### The design doc itself becomes unwieldy

A design doc with 20 Considered Options sections, each with a Chosen subsection and an Alternatives Considered subsection, is 2000+ lines in the Considered Options section alone. The document stops being readable. There's no guidance in the design for when to split a design doc into multiple designs vs. using one with many decisions.

**Risk level: Medium.** The framework works at 3-5 decisions. At 10+ it strains. At 20+ it breaks ergonomically. The design doesn't set an upper bound or provide a splitting heuristic.

## Top 3 Maintenance Risks (6-Month Horizon)

### Risk 1: Compiled Agent Prompt Drift (Certainty: Near-certain)

The monolithic agent-prompt.md will diverge from the decision skill's phase files within months. The two invocation paths (standalone via phase files, agent-spawned via compiled prompt) will produce different-quality outputs. This will be hard to diagnose because both paths produce plausible results -- the difference is in rigor, not in crashes.

**Why it's the top risk:** It's an architectural choice that creates a permanent maintenance tax with no automated guard. Every phase file edit requires a corresponding template edit, and there's nothing enforcing that. The plan skill already has this pattern, so there's precedent for it working short-term, but the decision skill has more phases and the fast-path stripping adds a fragility dimension that plan lacks.

**Mitigation the design should add:** Either (a) generate the compiled prompt from phase files at implementation time (a build step, even if manual), or (b) add a CI check that compares phase file modification timestamps against the template's, or (c) abandon the compiled template and have agents read SKILL.md directly (the design rejected this, but the reliability argument deserves re-examination given the maintenance cost).

### Risk 2: Cross-Cutting Protocol Consistency (Certainty: High)

The lightweight decision protocol and --auto behavior are copy-pasted into 39 locations across 38+ phase files. There's no shared implementation, no catalogue of decision points, and no CI validation that all instances follow the same pattern. The first protocol bug will require a 39-file audit.

**Why it's #2:** Unlike the compiled prompt drift (which produces subtly different quality), protocol inconsistency produces user-visible bugs -- missing assumptions in the PR body, wrong wip/ file paths, decisions not recorded. These are harder to dismiss as "working as intended" and will force expensive remediation.

**Mitigation the design should add:** (a) Create a manifest of all 39 decision points with their locations, categories, and expected behavior. (b) Define the protocol as a single reference file that phase files include by reference, not by copy-paste. (c) Add a CI check (even a simple grep) that verifies decision block format consistency across wip/ artifacts.

### Risk 3: Format Coupling Without Ownership (Certainty: High)

The decision block format, decision report format, and considered options format must stay in sync, but no single file or component owns the translation. A format change requires updating 7-8 files across 3 skills, with no automated check for completeness. The adapter from decision reports to considered options is implicit -- it's described in prose in the design but doesn't have a specification or test.

**Why it's #3:** Format coupling is a slow-burn problem. It won't cause immediate failures, but after 3-4 format tweaks where someone forgets one of the 8 files, the formats will be subtly incompatible. Decision reports will have fields that considered options sections don't render. Lightweight blocks will use a structure that the manifest parser doesn't expect. Each individual inconsistency is minor, but they compound.

**Mitigation the design should add:** (a) Create a single canonical format spec that all consumers reference. (b) Define the decision-report-to-considered-options mapping in a dedicated reference file, not inline in a phase file. (c) Add a "format version" to decision blocks so consumers can detect stale formats.

## Additional Observations

### The 150-line constraint needs enforcement or abandonment

11 of 38 current phase files already exceed 150 lines. The design adds more pressure. Either add a CI check that enforces the limit (with an escape hatch for justified exceptions) or drop the constraint from the design documentation. An unenforced constraint is worse than no constraint -- it creates false confidence.

### Resume logic becomes fragile at 8 phases

The design skill's resume logic (in SKILL.md) maps artifact existence to phase numbers. Adding 3 new phases shifts all the mappings. The current resume logic in SKILL.md (lines 162-170) uses a specific ordered check. With 8 phases, the number of resume states doubles. There's no test that the resume logic correctly identifies which phase to resume at for each possible artifact state.

### The decision skill is both a skill and a sub-operation

The decision skill must work standalone (`/decision`) and as an agent sub-operation (compiled prompt). These two modes have different entry points, different context loading, and different output contracts. Any change to the skill must be verified in both modes. This dual-mode nature is a maintenance multiplier that the implementation plan doesn't account for.
