# Advocate: CLAUDE.md-Only

## Approach Description

All downstream customization happens through project CLAUDE.md files. Base skills
are extracted into shirabe with only generic logic. Skills read well-documented
CLAUDE.md headers at runtime to adapt their behavior. No new file conventions, no
`@-include` mechanism in SKILL.md files, no secondary extension files. The API
surface is a published set of header names and their semantics -- a contract between
shirabe skills and any CLAUDE.md that wants to configure them.

The tools repo layers customization by adding headers to the CLAUDE.md files it
manages (workspace-level, private-level, public-level). Since CLAUDE.md layering
already cascades from workspace root down to repo, all sessions in all repos
automatically see the configured headers without any per-skill setup.

---

## Investigation

### What CLAUDE.md Headers the Skills Already Read

The current tools-repo skills already read four documented CLAUDE.md headers:

**`## Repo Visibility: [Private|Public]`** -- Read by explore, plan, prd, and design
SKILL.md files during context resolution. Every skill that produces content checks
this before writing. Path-based fallback exists (`private/` or `public/` in path).

**`## Default Scope: [Strategic|Tactical]`** -- Read by explore and plan to determine
scope when no `--strategic`/`--tactical` flag is passed. Default is Tactical if
absent.

**`## Repo Visibility`** and **`## Default Scope`** are the only two headers the
current skills consume. Both are already in place in tools' installed CLAUDE.md
files (`private/CLAUDE_.md` -> `private/CLAUDE.md`, etc.).

### What the Tools Repo Actually Customizes

Per the problem statement, the tools repo needs to customize four things:

1. **Triage routing (label lifecycle)** -- The label vocabulary (`needs-triage`,
   `needs-design`, `needs-prd`, `needs-spike`, `needs-decision`, `tracks-plan`) and
   their transition rules. Currently in `helpers/label-reference.md`, referenced
   directly by skills via relative path. After extraction, this helper won't exist
   in shirabe -- or will ship a minimal generic version.

2. **Upstream-context invocation on needs-design issues** -- Explore's Phase 0
   Setup explicitly invokes `../../../upstream-context/SKILL.md` when an issue has
   the `needs-design` label. This is a project-specific skill that finds strategic
   issues and design docs by searching GitHub. It's wired into phase-0-setup.md as
   a hardcoded step, not a configurable behavior.

3. **Private-repo handling in research agents** -- The Phase 2 discover agent
   prompt template already passes a `[Private|Public]` visibility string to each
   agent. Agents self-censor based on this. However, the _enforcement_ of what
   "private" means (can reference private issues, competitors by name, internal
   rationale) lives in `helpers/private-content.md` and `helpers/public-content.md`,
   which skills reference with relative paths.

4. **Visibility/scope detection** -- Already works via the two documented headers.
   This customization is fully covered by the current approach.

### Can CLAUDE.md-Only Cover These Needs?

**Visibility/scope detection: fully covered.** Already works. No change needed.

**Label vocabulary (triage routing): partially coverable.** A shirabe skill can
ship with a generic label vocabulary (or no default vocabulary) and read a
CLAUDE.md header like `## Label Vocabulary` or `## Triage Labels` to learn which
labels exist and what they mean. The tools repo would add:

```
## Label Vocabulary
needs-triage: unclassified, needs assessment
needs-design: architectural design required
needs-prd: requirements definition required
needs-spike: feasibility investigation required
needs-decision: single architectural choice needed
tracks-plan: PLAN created, implementation underway
```

This is text the LLM reads and applies during triage routing. It's plausible.
However, label lifecycle rules -- transition scripts, Mermaid class names, color
codes, the `swap-to-tracking.sh` invocation -- are procedural. A CLAUDE.md header
can describe them but cannot point to scripts that don't exist in the base skill.
Script paths would need to either ship with shirabe (making them generic placeholders
that tools overlays with real scripts) or be named in CLAUDE.md for the LLM to
look up at runtime.

**Upstream-context invocation on needs-design: not cleanly coverable.** Phase 0
of the explore skill currently has a hardcoded step: "If starting from an issue
with `needs-design` label, invoke the upstream-context skill." The upstream-context
skill is project-specific (it knows to search GitHub using `gh search issues` with
org/repo patterns, knows what a "strategic issue" is, knows where design docs live).
To make this configurable via CLAUDE.md, the base skill would need an explicit hook
point:

```
## Upstream Context Skill
path: .claude/skills/upstream-context/SKILL.md
trigger: needs-design label on entry issue
```

The LLM would read this header and, if present, invoke the referenced skill. This
is genuinely a CLAUDE.md-only mechanism -- no new file convention beyond the header
itself. But it requires the base skill to be written to look for and honor this
header at the right moment. The skill must say "before proceeding to Phase 1 for
needs-design issues, check CLAUDE.md for ## Upstream Context Skill." If that header
is absent, skip. If present, invoke.

This works but introduces an important question: how does the LLM reliably execute
a skill-invocation step that didn't exist when it read the base SKILL.md? The
instruction to check for the header must already be in the base SKILL.md text. So
the hook point must be pre-declared in the generic skill -- which means shirabe
ships with the hook even though no consumer uses it by default.

**Private-repo handling in research agents: coverable with shipping helper stubs.**
The base skill can ship `helpers/private-content.md` and `helpers/public-content.md`
as generic stubs (basic guidance appropriate for any project). The tools repo's
installed content replaces these with project-specific content (competitors by name,
internal shorthand, etc.). Since these are relative-path includes, not CLAUDE.md
headers, strictly speaking this isn't "CLAUDE.md-only" -- but if we allow the
installed CLAUDE.md to point to overlay files, or if we ship the helpers as part
of shirabe and accept they'll be project-generic, this need is met.

Alternatively, the CLAUDE.md could define:

```
## Private Content Guidelines
path: .claude/helpers/private-content.md
```

And the base skill would read this path instead of a hardcoded relative path.
Again, the skill must be written to look for this header, which must be pre-declared
in the generic SKILL.md.

### What New CLAUDE.md Headers Would Be Needed

To cover all four customization areas with CLAUDE.md-only, the "extension API"
would need at minimum:

| Header | Purpose | Format |
|--------|---------|--------|
| `## Repo Visibility` | Already exists | `Private` or `Public` |
| `## Default Scope` | Already exists | `Strategic` or `Tactical` |
| `## Label Vocabulary` | Teach skills which labels exist and what they mean | Block of `label: description` lines |
| `## Upstream Context Skill` | Path to skill invoked for needs-design issues | `path: <relative-path>` |
| `## Private Content Guidelines` | Path to private-content helper | `path: <relative-path>` |
| `## Public Content Guidelines` | Path to public-content helper | `path: <relative-path>` |

Six headers total. Two exist. Four new ones required.

### Update Resilience: What Breaks When Shirabe Updates

When shirabe ships a new version with changes to a skill, downstream CLAUDE.md
consumers face these scenarios:

**Additive skill changes (new phases, new capabilities):** CLAUDE.md headers from
before the update remain valid and are still honored. No downstream breakage. The
new behavior the consumer didn't configure simply uses the default (absent header
= fallback behavior). This is the ideal case and covers most updates.

**Changed header semantics:** If shirabe renames `## Repo Visibility` to
`## Repository Visibility`, or changes the accepted values, every downstream
CLAUDE.md breaks silently. The LLM reads the old header value and the skill uses
its fallback (which may be wrong). No error is surfaced -- the skill just runs with
the wrong context. This is a silent regression.

**Changed hook point locations:** If Phase 0 restructures and the "check for ##
Upstream Context Skill" instruction moves to a different phase or is removed,
the tools repo's CLAUDE.md header stops having any effect. Again, silent regression.

**Changed helper relative paths:** If `helpers/private-content.md` moves to
`references/private-content.md`, and the tools repo's CLAUDE.md had `path:
.claude/helpers/private-content.md`, the path is stale. The skill either fails
to read it (file not found) or falls back to a default the consumer didn't intend.

**Assessment:** CLAUDE.md-only is highly resilient to additive changes and
completely brittle to semantic changes. The "API" is implicit -- header names and
their interpretation live in the skill markdown. There's no type system, no
versioning on header semantics, and no validation that a consumer's headers are
still meaningful. Breaking changes are silent by default.

---

## Strengths

**Zero new infrastructure.** No new files, no new conventions, no new discovery
mechanism. Skills already read CLAUDE.md headers. Extending this pattern requires
only documentation of new headers in the skill text.

**Survives any installation method.** CLAUDE.md layering works regardless of how
shirabe is installed -- plugin registry, submodule, local path. The headers live
in the consumer's CLAUDE.md, which is always present in their session.

**LLM-native composition.** Skills are LLM-read markdown. Telling the LLM to
"check CLAUDE.md for ## Upstream Context Skill before Phase 1" is exactly the
same mechanism the LLM already uses for visibility and scope. The model is proven;
extending it adds no new cognitive load for skill authors.

**Minimal consumer burden.** A downstream consumer adds headers to their existing
CLAUDE.md. No new files to create, no new conventions to learn, no plugin manifest
to maintain. The configuration is colocated with all other per-project context.

**Graceful degradation.** If a header is absent, the skill uses its default
behavior. Consumers that don't care about triage routing don't add the label
vocabulary header and get a reasonable generic behavior. They opt in by adding
headers, not by forking.

**Visible configuration.** Every project-specific behavior is documented in
CLAUDE.md. A developer reading the CLAUDE.md sees everything that affects skill
behavior, in one place, in plain text.

**No plugin dependency system needed.** The problem statement notes that Claude
Code's plugin system has no cross-plugin dependency mechanism. CLAUDE.md-only
sidesteps this entirely -- upstream-context is invoked because CLAUDE.md says to
invoke it, not because shirabe declares a dependency on it.

---

## Weaknesses

**Silent failures on semantic changes.** When shirabe changes a header's name or
semantics, downstream consumers break without any error. The LLM reads the old
header, finds no match in the updated skill, uses the fallback. The consumer
doesn't know anything changed.

**Pre-declared hook points required.** The base skill must be written to look for
each configurable header at the right moment. You can't add a new customization
point to a live skill without updating the skill. This means the "extension API"
is not truly open -- it's whatever shirabe chose to expose when writing the skill.
Consumers can't add new hook points without modifying the base skill.

**Hook point ordering is implicit.** When multiple headers configure behavior at
different phases, the skill must read each at the right moment. If the order of
operations changes (e.g., upstream-context invocation moves from Phase 0 Step 0.3
to a new Phase 0.5), the header may be read too late or not at all. The consumer's
CLAUDE.md doesn't express intent -- it expresses configuration -- so there's no
way for the consumer to say "I need this to happen before Phase 1."

**Header sprawl risk.** As more customization points are added, the number of
documented headers grows. Consumers face a growing list of headers to understand,
some of which interact with each other. Without tooling (no validation, no
autocomplete), this becomes increasingly hard to manage correctly.

**Prose parsing unreliability.** Headers are read by an LLM, not a parser. Complex
label vocabulary definitions (especially with associated scripts, Mermaid classes,
and color codes) expressed as prose in a CLAUDE.md block may be parsed inconsistently
across sessions or after model updates. Structured data (like scripts to invoke)
is harder to reliably extract from prose than simple string values.

**No versioning or compatibility signaling.** There's no mechanism for a consumer
to declare "I was written against shirabe 1.2's headers" or for shirabe to warn
"this header was renamed in 2.0." Breaking changes are entirely silent.

**Script references can't be fully described in prose.** The tools repo uses
several shell scripts invoked at specific lifecycle points (`swap-to-tracking.sh`,
`transition-status.sh`, `create-issues-batch.sh`). CLAUDE.md can describe where
these scripts are, but the LLM must decide when and how to invoke them based on
prose instructions in the skill. Any mismatch between what the header says and
what the skill expects is undetectable until it fails at runtime.

**Upstream-context invocation requires cooperative skill design.** For the tools
repo to configure upstream-context invocation via CLAUDE.md, the base explore
skill must already contain language like "check CLAUDE.md for ## Upstream Context
Skill; if present, invoke it." If shirabe didn't pre-declare this hook, no amount
of CLAUDE.md configuration makes it happen. The consumer's extensibility is
bounded by what shirabe anticipated and baked in.

---

## Deal-Breaker Risks

**The upstream-context invocation risk is real but not a deal-breaker.** It
requires shirabe to ship with the hook pre-declared. This is a design-time
constraint, not a runtime failure mode. As long as shirabe's initial extraction
includes these hook points (which are knowable upfront, since the tools repo is
the first consumer), this isn't a blocker.

**Silent semantic regression is the most serious risk.** Any non-additive change to
a header -- a rename, a value format change, a removed hook -- causes downstream
consumers to silently operate with wrong context. In a workflow system where
"wrong context" means filing issues with the wrong labels or failing to gather
upstream design context, this can produce low-quality outputs that are hard to
diagnose. Users will observe strange behavior and have no obvious path to debugging
it, since the configuration looks correct (the header is still there) and the skill
doesn't surface an error.

This risk is highest for:
- The `## Label Vocabulary` header (complex structured data, parsed as prose)
- The `## Upstream Context Skill` hook (path must still be valid after updates)
- Any future headers added after the initial design

If shirabe commits to a header stability policy (documented headers are versioned
and backward-compatible), this risk is manageable. Without such a policy, it's
a latent regression source.

**The script invocation problem is a genuine structural weakness.** Skills like
plan and design invoke shell scripts (`swap-to-tracking.sh`, `transition-status.sh`,
`create-issues-batch.sh`, `create-issue.sh`). These scripts are referenced in skill
markdown as `${CLAUDE_SKILL_DIR}/scripts/...` paths. After extraction, the base
skill can't know where these scripts live for a downstream consumer. CLAUDE.md-only
has no mechanism to declare "override script path X with Y." A consumer that needs
different scripts (or additional scripts) can't configure this via headers alone.

This limits CLAUDE.md-only to behavioral customization (what to do) rather than
operational customization (how to do it via scripts). For the tools repo's current
needs, this is partially acceptable -- most of the four customization areas are
behavioral. But `swap-to-tracking.sh` is invoked in plan Phase 7, and if the tools
repo needs a different implementation of that script, CLAUDE.md can't help.

---

## Implementation Complexity

**Files to modify:**
- `explore/SKILL.md` -- add header documentation and hook points for upstream-context
  invocation, add ## Label Vocabulary reading instructions in triage steps
- `explore/references/phases/phase-0-setup.md` -- add conditional for ## Upstream
  Context Skill header
- `plan/SKILL.md` -- add header documentation for ## Label Vocabulary, adapt
  script path references if configurable paths are added
- `design/SKILL.md` -- add header documentation for visibility content guidelines
- `prd/SKILL.md` -- same as design
- `work-on/SKILL.md` -- add header reading for ## Label Vocabulary
- Approximately 6-8 SKILL.md or phase files modified in shirabe

New files: minimal. The helper stubs (`private-content.md`, `public-content.md`,
`label-reference.md`) should ship with shirabe as generic defaults. These are new
files for shirabe, not new infrastructure.

**New infrastructure:** No. No new file conventions, no manifest format, no
discovery mechanism. The extension points are prose instructions within existing
skill text.

**Estimated scope:** Medium. Modifying 6-8 files to add hook points and document
headers is not large. But ensuring the hook points are in the right places, with
correct fallback behavior, and that the header contract is complete enough to cover
all known tools-repo customization needs -- that's genuinely careful design work.
The risk of under-specifying hook points (leaving gaps that require a second pass)
is higher than with approaches that formalize the extension contract.

---

## Summary

CLAUDE.md-only is the lowest-friction extensibility approach for the tools repo's
current customization needs, and it works for most of them. Visibility/scope
detection already works. Label vocabulary is expressible as a documented header
(though prose parsing of complex label rules is imprecise). Private-repo content
guidelines are coverable with helper stubs that consumers can overlay. The only
genuinely hard case is upstream-context invocation, which requires a pre-declared
hook in the base explore skill -- but since the tools repo is the first consumer
and its needs are known, this hook can be designed in from the start.

The approach's real vulnerability is update resilience. It's highly resilient to
additive changes (new phases, new capabilities) but completely brittle to semantic
changes (renamed headers, changed value formats, moved hook points). There's no
error surface -- a stale header silently does nothing. For a system where "silently
does nothing" means triage runs without a label vocabulary or design issues are
explored without upstream context, this is a meaningful operational risk.

The absence of formal versioning on the header contract means that as shirabe
evolves, the tools repo must track each release for header-semantic changes. This
is a sustainable burden with one consumer and a small, disciplined team; it becomes
progressively harder with more consumers.

CLAUDE.md-only is the right choice if: the header contract can be kept small and
stable, shirabe commits to additive-only changes on existing headers, and the tools
repo is comfortable accepting silent-failure risk in exchange for zero new
infrastructure. It's the wrong choice if any downstream consumer needs to add
entirely new customization points that shirabe didn't anticipate -- those consumers
will hit a wall that only a shirabe update can open.
