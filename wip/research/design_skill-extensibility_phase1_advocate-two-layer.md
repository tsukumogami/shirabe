# Advocate: Two-Layer (CLAUDE.md + Extension Files)

## Approach Description

The two-layer model separates extensibility into two distinct mechanisms:

**Layer 1 — CLAUDE.md layering** handles project-wide, cross-skill behavior. Visibility
detection, default scope, writing style, label vocabulary, and public/private content
guidelines all belong here. Claude Code already delivers CLAUDE.md content to every
session without additional skill configuration. This layer is "free" — it requires no
changes to shirabe.

**Layer 2 — skill extension files** at `.claude/skill-extensions/<name>.md` handle
per-skill additions. Shirabe's base SKILL.md files include `@.claude/skill-extensions/<name>.md`
directly. Claude Code resolves `@path` includes client-side before the LLM sees skill
content — zero tool calls, zero LLM roundtrips. If the extension file is absent, the
`@path` text appears in context but the LLM ignores it in practice. If present, its
content is injected into the skill context at load time.

A `.local.md` variant (`.claude/skill-extensions/<name>.local.md`, gitignored) allows
personal machine-level overrides that don't get committed. Missing `.local.md` files are
silently skipped identically to missing repo-level extension files.

This was validated experimentally. Tests T1-T7 in `explore_skill-extensibility_r1_lead-extension-mechanism-test.md`
confirm all critical properties.


## Investigation

### What project-specific behavior exists in the tools repo explore skill?

Reading the tools repo's explore/SKILL.md and its phase-0-setup.md reference reveals the
project-specific coupling concentrated in a handful of places:

**Triage routing (Phase 0):**
- Two-stage triage with specific label vocabulary: `needs-triage`, `needs-design`,
  `needs-prd`, `needs-spike`, `needs-decision`
- `upstream-context` skill invocation on `needs-design` issues — this is a tool-specific
  skill, not part of the generic workflow
- Stage 2 triage synthesizes toward specific artifact type labels and updates GitHub
  labels accordingly

**Cross-repo issue handling:**
- Parsing `org/repo#N` patterns (e.g., `tsukumogami/tsuku#42`)
- Using `gh issue view <N> --repo <owner/repo>` for cross-repo reads
- Visibility resolution from working repo, not the issue's repo

**Private-repo handling in research agents:**
- Phase 2 discover passes `Visibility: [Private|Public]` to each agent
- Agents suppress private references in outputs destined for public repos
- This is mentioned in phase-0 and phase-2 as explicit visibility context injection

**Context detection (CLAUDE.md-driven, already in place):**
- Visibility: read `## Repo Visibility: Private/Public` from CLAUDE.md
- Scope: read `## Default Scope: Strategic/Tactical` from CLAUDE.md
- Both are already CLAUDE.md-driven in the existing tools skill — these migrate naturally
  to Layer 1

**Label vocabulary:**
- The tools repo's `helpers/label-reference.md` carries tsuku-specific label names and
  their lifecycle rules
- This belongs in a downstream extension or CLAUDE.md, not in the base shirabe skill

### Classifying behaviors: CLAUDE.md vs extension files

| Behavior | Layer | Rationale |
|----------|-------|-----------|
| Visibility detection (`Repo Visibility: Public/Private`) | CLAUDE.md | Cross-skill, already CLAUDE.md-driven in tools repo |
| Default scope detection (`Default Scope: Strategic/Tactical`) | CLAUDE.md | Cross-skill, repo-wide property |
| Writing style guidance | CLAUDE.md | Cross-skill; already in org-level CLAUDE.md |
| Public/private content guidelines | CLAUDE.md | Cross-skill; helps/public-content.md and private-content.md are portable as CLAUDE.md content |
| Label vocabulary (`needs-triage`, `needs-design`, etc.) | CLAUDE.md | Project-specific label names; tools repo defines its own |
| Triage routing logic (two-stage triage) | Extension file | Tools-specific; generic explore doesn't need it |
| `upstream-context` skill invocation on `needs-design` | Extension file | Tools-specific skill that doesn't exist in base shirabe |
| Cross-repo issue parsing (`org/repo#N`) | Extension file | Tools-specific workflow pattern |
| Private-repo research agent behavior | Extension file | Tools-specific; base skill assumes visibility context from CLAUDE.md but doesn't specialize agent prompts per-visibility unless extended |

The split is clean. CLAUDE.md handles "what kind of project is this?"; extension files
handle "what does explore do differently in this project?"

### What a tools repo extension file for /explore would look like

The extension file at `.claude/skill-extensions/explore.md` would add:

```markdown
## Project Extensions: explore

### Triage Routing

When starting from an issue with `needs-triage` label, run the two-stage triage
defined below before proceeding to Phase 1.

**Stage 1** (3 parallel agents: needs-investigation, needs-breakdown, ready):
[... triage agent prompts ...]

After Stage 1:
- needs-breakdown or ready: present options (break down / implement directly).
  Route to /work-on and stop.
- needs-investigation: proceed to Stage 2.

**Stage 2** (3 parallel agents: needs-prd, needs-design, needs-spike/decision):
[... Stage 2 agent prompts ...]

After Stage 2: update label (remove `needs-triage`, add confirmed `needs-*` label).
If needs-design: invoke `../upstream-context/SKILL.md` before proceeding to Phase 1.

### Cross-Repo Issue Handling

When `$ARGUMENTS` matches `<org>/<repo>#<N>` or `<org>/<repo>#<N>`:
- Fetch via: `gh issue view <N> --repo <org>/<repo>`
- Visibility resolves from the WORKING repo (where artifacts land), not the issue's repo

### Research Agent Visibility

When launching Phase 2 agents (Discover), include in each agent prompt:
```
## Visibility
[Private|Public] — if Public, do not reference private issues or internal-only
resources in your findings.
```

The base skill passes visibility to agents when this extension is present.
```

This is ~60-80 lines. It references no internal infrastructure not already available in
the workspace. It can be committed to the tools repo's `.claude/skill-extensions/`
directory and will be silently activated whenever /explore is invoked.

### Update resilience assessment

When shirabe ships a new version of /explore's SKILL.md:

**Safe changes (non-breaking for extension consumers):**
- Adding new phases at the end of the workflow
- Modifying phase file content (phase-1-scope.md, etc.) — extensions loaded at skill
  start are in context throughout, so changes to phase file wording don't break the
  extension's effect
- Adding new `@.claude/skill-extensions/explore/<phase>.md` slots — new slots with no
  downstream file are silently skipped
- Renaming internal reference files that are not exposed as extension slots

**Potentially breaking changes:**
- Removing an `@.claude/skill-extensions/explore.md` line from SKILL.md — the extension
  file exists on disk but is no longer loaded. The downstream consumer doesn't know.
  Symptom: triage routing silently stops working.
- Changing the phase structure in ways that conflict with extension content — if the
  base skill says "go to Phase 1 directly" and the extension says "run triage first",
  the result depends on LLM instruction weighting
- Renaming SKILL.md itself or moving it within the plugin structure — breaks `@` path
  resolution for any extension that references the skill by name

**Verdict:** The approach is resilient for the common case (shirabe improves workflow
phases) but fragile when shirabe restructures the extension contract itself. A
CHANGELOG with explicit extension-contract sections mitigates this.

### The raw @path visibility risk

When an extension file is absent, the LLM sees the literal `@.claude/skill-extensions/explore.md`
string in its context. Test T6 confirmed this — the path is not stripped out. Test T7
confirmed the LLM did not attempt to autonomously read the file even with Read available.

**Is this a real problem in practice?**

Not a significant problem for base skill execution. The raw text is one line (~50 tokens)
that the LLM treats as a no-op instruction. In T1 and T7, the skill executed correctly
with no degraded behavior.

The risk is behavioral, not structural. A future model update or an unusual context
(high instruction density, conflicting directives, ambiguous skill content) could cause
the model to treat the raw `@path` as a command to read the file. This would result in
a spurious Read tool call and potential "file not found" error surfaced to the user.

The risk is proportional to the number of `@` lines in SKILL.md. A skill with 2 extension
slots (skill-level + local) has 2 lines of raw path noise. A skill with phase-level
extensions (6 phases × 2 variants = 12 lines) has significantly more noise. Each base
token cost is ~50 tokens × 12 = ~600 tokens for a 6-phase skill with no extensions active.

Mitigations available:
- Comment the `@` lines with explicit labels: `@.claude/skill-extensions/explore.md  <!-- project extension, optional -->`
- Document in SKILL.md that extension slots are optional: "The following lines activate
  project-specific behavior if those files exist. If absent, they are safely ignored."
- Limit phase-level slots to high-customization phases only (Phase 0, Phase 5 for /explore)

The visibility of raw `@path` text is uncomfortable but not a deal-breaker given confirmed
test behavior.


## Strengths

**Deterministic loading with no LLM roundtrip.** The `@` include is resolved by Claude
Code's client before the LLM receives the skill. This makes extension loading predictable
and cheap. A downstream consumer with an extension file active pays the context cost of
that file's content. A consumer with no extension files pays ~50 tokens per `@` line in
the raw path.

**Works across all installation methods.** Because `@` resolves relative to the process
working directory (workspace root), not relative to the plugin directory, it works
identically whether shirabe is installed via plugin registry, submodule, or local path.
The extension file is always at `.claude/skill-extensions/<name>.md` relative to the
workspace, regardless of where shirabe lives.

**Additive composition by default.** Extension content is prepended to the skill context
(loaded before phase-file instructions). LLMs naturally weight later instructions higher,
so the base skill's phase instructions tend to win when silent unless the extension
explicitly overrides. This means "add behavior" is the default; "replace behavior" requires
deliberate extension authoring.

**Clean separation of concerns.** CLAUDE.md handles the 60-70% that's genuinely cross-skill
(visibility, scope, writing style, content guidelines). Extension files handle the remainder
that's per-skill and project-specific. This prevents CLAUDE.md from becoming a skill-specific
configuration dump.

**Local override support.** The `.local.md` variant enables personal machine customization
that doesn't contaminate the shared repo. A developer can add debug instrumentation or
personal phase preferences without committing them.

**No new infrastructure.** The mechanism uses Claude Code's existing `@` include behavior.
Shirabe adds `@` lines to SKILL.md files; downstream consumers create the extension files.
No tooling, scripts, or CI changes needed to enable the core mechanism.

**Visible contract in SKILL.md.** The `@.claude/skill-extensions/explore.md` line in the
base skill is self-documenting. A developer reading SKILL.md knows exactly where to put
customizations. There's no hidden lookup mechanism.


## Weaknesses

**The "not truly silent" problem.** Missing extension files leave raw `@path` text in the
LLM's context. This is a behavioral property (the LLM ignores it) not a platform guarantee.
The risk of spurious Read calls or confused behavior exists and is model-dependent.

**No validation that extension files were loaded.** There's no mechanism for a downstream
consumer to verify that their extension file was picked up. If the extension file is at the
wrong path, the `@` include silently skips it — the skill runs without the customization.
Debugging this requires inspecting stream-json output for the raw @path text.

**Phase-level extension context dilution.** If phase-level extensions are included (up-front
loading in SKILL.md), the extension content is loaded at skill start and remains in context
through all phases. A phase-3 extension loaded in phase 0 sits in context for the entire
skill run. For long workflows (explore's 5 phases), this is a persistent context cost even
when the extension is only relevant to one phase.

**SKILL.md becomes a list of @ includes.** As downstream customization needs grow, pressure
mounts to add more extension slots. A 5-skill × 6-phase × 2-variant matrix is 60 `@` lines
across the plugin. Each is a line of noise when absent. Extension slot proliferation is a
real risk.

**Breaking change semantics are informal.** Extension consumers have no machine-readable
contract with shirabe. If shirabe removes an extension slot, the consumer's file exists on
disk but is never loaded. This is a silent regression — skill behavior changes without error.
A CHANGELOG is a mitigation, but it requires human discipline, not tooling enforcement.

**Extension files require discipline to keep stable.** When the tools repo ships a change
to `explore.md`, it must not conflict with base skill updates in shirabe. With both evolving
independently, extension authors need to track shirabe's changelog and revalidate their
extensions after shirabe updates. This is manageable for one consumer (tools repo) but
doesn't scale to many consumers.


## Deal-Breaker Risks

**None confirmed.** The tested properties hold:
- Zero tool calls for extension loading (T3)
- Missing files don't break execution (T1, T7)
- Path resolution relative to workspace root works for local plugin installations (T4)
- `.local.md` chaining confirmed working

**Residual unconfirmed risks (worth testing before shipping):**

1. **Installed plugin (registry) vs `--plugin-dir`:** All testing used `--plugin-dir`.
   Behavior with a registry-installed plugin (TC-010 in the test plan) is assumed but
   not confirmed. If path resolution differs for installed plugins, the mechanism fails
   for the dominant production install path.

2. **Worktree isolation:** TC-009 is explicitly uncharted. If `--worktree` runs in an
   isolated directory without the workspace's `.claude/skill-extensions/` tree, extension
   files won't be found. This breaks skills for users who use worktrees.

3. **Claude Code version stability:** The `@` include mechanism has no documented semver
   contract. The test suite serves as a regression harness, but a Claude Code update could
   silently change resolution semantics. This is a long-tail risk, not a current blocker.

4. **Model update risk (TC-008 scenario):** If a future model treats raw `@path` text as
   an actionable directive, TC-008 would fail and users would see spurious Read calls and
   "file not found" errors for every skill with inactive extension slots. This is unlikely
   but plausible given how instruction-following models are trained.

None of these are confirmed deal-breakers today. Items 1 and 2 should be tested before
shipping; items 3 and 4 are ongoing regression targets.


## Implementation Complexity

**Files to modify:** 5 base SKILL.md files (explore, design, prd, plan, work-on/implement)
plus any shared phase reference files if phase-level extension slots are included.

**New infrastructure:**
- Yes, but minimal: `.gitignore` entry for `*.local.md` in `.claude/skill-extensions/`
- Documentation: extension API surface in shirabe's README or a dedicated `docs/extending.md`
- Regression test suite: the test scripts in `explore_skill-extensibility_r1_lead-extension-test-plan.md`
  are ready to commit as `tests/run-extension-tests.sh`

The tools repo needs no new infrastructure — it creates extension files in `.claude/skill-extensions/`.

**Estimated scope:** Small. Modifying 5 SKILL.md files to add `@` lines is mechanical.
The test harness is already written. Documentation is the most substantial work item.
Extraction of the skills themselves (separating generic from project-specific behavior) is
the larger scope, but that's prerequisite work regardless of which extensibility approach
is chosen.


## Summary

The two-layer model is well-matched to the constraints. It uses a platform feature that has
been confirmed to work, requires no new infrastructure, and cleanly separates what belongs
in CLAUDE.md (cross-skill project context) from what belongs in extension files (per-skill
project customizations).

For the tools repo's specific needs — triage routing with `upstream-context` invocation,
cross-repo issue handling, and private-repo research agent behavior — a single
`explore.md` extension file of ~80 lines handles all three. The other skills (design, prd,
plan, work-on) have lighter customization needs and smaller or no extension files.

The genuine weaknesses are: the "not truly silent" raw @path text (behavioral risk, not
confirmed failure), absent validation feedback when extension files are misconfigured, and
context accumulation from up-front phase-level extension loading. None are deal-breakers for
the tools repo as first consumer. They matter more if shirabe targets many downstream
consumers with complex customization needs.

Two residual risks need confirmation before shipping: registry-installed plugin path
resolution (vs `--plugin-dir`), and worktree isolation behavior. Both can be tested with
the existing test harness (TC-009 and TC-010). If either fails, the mechanism's "works
regardless of install method" strength is weakened and a fallback (explicit Read instructions
in SKILL.md) would need to be evaluated.

The approach is sound for the known consumer and known constraints. It's the right
starting point.
