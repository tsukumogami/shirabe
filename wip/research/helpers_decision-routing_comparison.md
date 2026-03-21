# Research: Helper Comparison — decision-presentation and design-approval-routing

**Date:** 2026-03-17
**Scope:** Compare two tsukumogami helpers against obra/superpowers and available Anthropic materials.
**Output feeds:** shirabe skill extraction decisions

---

## What was investigated

1. obra/superpowers skill library — decision presentation patterns, post-completion routing
2. Anthropic official materials — plugin documentation, skills documentation, any guidance on
   agent decision UX
3. The official claude-plugins-official marketplace — helper or decision patterns in published skills
4. Which tsukumogami skills currently reference each helper, and how
5. Whether either helper could work as a standalone skill

---

## Sources examined

**Local:**
- `/home/dangazineu/.claude/plugins/cache/tsukumogami/tsukumogami/0.1.0/helpers/decision-presentation.md`
- `/home/dangazineu/.claude/plugins/cache/tsukumogami/tsukumogami/0.1.0/helpers/design-approval-routing.md`
- All tsukumogami SKILL.md files and relevant phase files that reference either helper
- `/home/dangazineu/.claude/plugins/cache/claude-plugins-official/frontend-design/6b70f99f769f/skills/frontend-design/SKILL.md`
- Existing shirabe wip research (extraction-audit, consumption-model)

**Remote:**
- `https://github.com/obra/superpowers` — skill library
- `https://raw.githubusercontent.com/obra/superpowers/refs/heads/main/skills/brainstorming/SKILL.md`
- `https://raw.githubusercontent.com/obra/superpowers/refs/heads/main/skills/finishing-a-development-branch/SKILL.md`
- `https://raw.githubusercontent.com/obra/superpowers/refs/heads/main/skills/writing-plans/SKILL.md`
- `https://code.claude.com/docs/en/plugins`
- `https://code.claude.com/docs/en/skills`

---

## Question 1: Does obra/superpowers have decision presentation patterns?

obra/superpowers is a 14-skill framework for agentic software development workflows. It covers
test-driven development, brainstorming, planning, code review, branch finishing, and subagent
orchestration. It does not define a standalone decision-presentation helper or any shared
cross-skill pattern for how agents present choices.

**What the individual skills do:**

The `brainstorming` skill tells the agent to "Lead with your recommended option and explain why."
It also says to "Propose 2-3 different approaches with trade-offs" and to "Present options
conversationally with your recommendation and reasoning." This is recommendation-first behavior,
but it's embedded inline in a single skill's instructions — not extracted into a shared helper.

The `finishing-a-development-branch` skill takes the opposite stance: present exactly four options
(merge, PR, keep, discard) without explanation or recommendation. The user decides. The only
exception is a safety confirmation for the destructive option (discard). This skill explicitly says
"Don't add explanation" — it treats branch disposition as a neutral choice, not an agent judgment.

The `writing-plans` skill picks a winner at the execution handoff: it marks subagent-driven
execution as "(recommended)" versus inline execution. This is the same recommend-first pattern
as tsukumogami's decision-presentation helper — but again, implemented inline.

**Summary:** obra/superpowers uses recommendation-first ordering in individual skills when the
agent has an opinion worth stating (brainstorming, writing-plans), and neutral presentation when
the choice is user-domain (branch disposition). There is no shared helper, no AskUserQuestion
pattern, and no post-approval routing primitive. Each skill handles this locally.

---

## Question 2: Does Anthropic address agent decision UX in official materials?

**Official plugin documentation** (`code.claude.com/docs/en/plugins`): No guidance on decision
presentation patterns. Covers plugin structure, manifest schema, skill authoring basics, and
distribution mechanics. Mentions AskUserQuestion in skill context examples but gives no guidance
on how to use it to present decisions.

**Official skills documentation** (`code.claude.com/docs/en/skills`): No guidance on
recommendation-first ordering or approval workflows. Lists frontmatter fields, tool restrictions,
invocation control, and argument passing. The bundled `/batch` skill description mentions
"presents a plan. Once approved, spawns one background agent per unit" — this implies an
approval gate, but the skill content is not public and the documentation doesn't describe the
presentation format.

**Official marketplace skills** (`claude-plugins-official`): The only non-LSP skill in the
official marketplace is `frontend-design`. It contains no decision-presentation pattern — it's
a single-phase content generation skill with no branching or user approval steps.

**Summary:** Anthropic publishes no official guidance on how agents should present decisions,
structure approval workflows, or order options. The AskUserQuestion tool exists but is
undocumented as a decision-presentation pattern in any official material examined. The
recommendation-first convention in decision-presentation.md is tsukumogami-specific, not
an industry standard.

---

## Question 3: Is decision-presentation a helper or a skill?

**Current architecture:** decision-presentation.md is @-included into the context of any skill
that references it (via the helpers/ directory pattern). It's not invokable by users or by
Claude as an independent skill. It's passive guidance that shapes how a skill reasons.

**Could it become a standalone skill?** In principle, a skill with `user-invocable: false` and
`disable-model-invocation: true` could capture this pattern as injectable context. But there's
no benefit: its content is short (55 lines), it contains no workflow logic, and it has no
artifacts or steps to execute. It's a convention document, not a workflow.

The architectural question is whether a decision-presentation skill could be *invoked* by other
skills mid-workflow — e.g., a skill calls `/shirabe:decision-presentation` to render a
recommendation. Claude Code's Skill tool allows one skill to invoke another. But this pattern
would add invocation overhead for content that's simpler to include as context. The helper
pattern (include-once, reason across the whole workflow) is more appropriate than a skill
invocation.

**The deeper question:** Could this helper be dropped and rely on Claude's default behavior?

obra/superpowers implements recommendation-first without a helper — individual skills just state
it inline. Anthropic doesn't prescribe a pattern at all. The risk of dropping the helper is
inconsistent behavior across skills: some skills might present options side-by-side, others might
pick a winner without explanation, others might use approval-versus-selection for the wrong case.

The helper's value is consistency: when five skills all reference the same 55-line document,
they produce the same UX for users across the whole workflow. Without it, each skill author
decides independently. For a plugin shipped to external consumers, that inconsistency is a
quality problem.

**Verdict:** Keep as a helper. The helper pattern is correct for this content. It's not a skill
candidate (no workflow logic) and not worth dropping (consistency is its entire value).

---

## Question 4: Is design-approval-routing still needed as a helper?

**What it does:**
Post-approval routing after a design doc is accepted. Runs a complexity assessment (4 criteria:
files to modify, new tests, API changes, cross-package scope), produces a "Simple" or "Complex"
recommendation, presents AskUserQuestion with routing options (Plan / Approve only), and handles
label updates and PR body conventions if the design was spawned from an issue.

**Which skills reference it:**
Two skills reference this helper:
1. `/design` SKILL.md — "See `../../helpers/design-approval-routing.md` for shared routing logic."
   Called in Phase 6 (step 6.8, after approval).
2. `/explore` Phase 5 (produce) references it for post-crystallize routing.

No other skills reference it.

**Sub-question (a): Generic enough to ship as-is?**

The complexity assessment rubric (1-3 files = simple, 4+ = complex, new tests, API changes,
cross-package) is generic. Any team designing software would recognize these criteria. The
routing options (run /plan vs. handle manually) are also generic — they apply to any workflow
where design docs gate implementation planning.

The PR convention (Ref vs. Fixes) and the spawned_from frontmatter handling reference GitHub
conventions and the tsukumogami-specific workflow, but they're already delegated to the
`design` skill's lifecycle section ("handle label and parent doc updates as described in the
`design` skill's lifecycle section"). The helper doesn't duplicate that logic — it defers to it.
For shirabe consumers who don't use the label lifecycle, that deference becomes a no-op.

The extraction-audit research (design_skill-extensibility_phase3_extraction-audit.md) already
classified this helper as portable: "Post-approval routing logic for design documents... generic.
The `Ref #<N>` vs. `Fixes #<N>` PR convention and `spawned_from` frontmatter handling are
generic GitHub conventions... Moves to shirabe with minor note that the label update step is
optional/extension-provided."

**Sub-question (b): Project-specific enough that consumers would override it?**

The complexity criteria are generic but the thresholds are opaque guesses, not empirically
calibrated. A team working on microservices might set the "simple" threshold at 1 file (any
multi-file change is complex). A team with no test infrastructure might weight "new tests"
differently. The criteria aren't wrong — they're reasonable defaults — but consumers might want
to replace them.

However, the override mechanism for helpers in the shirabe extensibility model is the
skill-extensions file. A consumer who wants different complexity criteria would write an
extension for `/design` or `/explore` that redefines the thresholds. That's already the right
architecture. The helper itself doesn't need to become an extension point.

**Sub-question (c): Should it be embedded in the design skill rather than a separate helper?**

This is the most interesting question. The routing logic is only used by two skills. If it were
embedded in the `/design` skill's Phase 6 phase file, it would be in one place and only loaded
when needed. The current separation into a helper means it's included in the context of both
`/design` and `/explore` even when not needed (e.g., during early phases).

But the separation has two real benefits:
1. It prevents duplication: `/explore` and `/design` both need the same routing logic post-
   approval. If both skills embed it, a change to the routing logic requires updating two files.
2. It signals to readers that this logic is shared. Someone reading the `/design` SKILL.md sees
   the reference and understands that routing behavior is centralized.

As shirabe ships to external consumers, that discoverability matters: contributors can modify
routing behavior in one place.

**Verdict:** Keep as a helper. It's generic enough to ship as-is (with the minor note from the
extraction audit that label lifecycle steps are extension-layer behavior). Embedding it in the
design skill would create duplication when explore also needs it. Converting it to a skill would
add no value — it has no workflow logic worth executing independently.

---

## Question 5: Industry patterns for agent decision-making UX

No authoritative published guidance exists for "agent decision presentation" as a named pattern.
The closest available evidence:

**Recommendation-first is implicit in modern LLM usage patterns.** The premise — that asking
an agent for options and getting "here are 3 options, you choose" is less useful than "here's
what I recommend and why" — is widely accepted in product design circles (the "don't make me
think" principle applied to agent output) but not formally documented in agent tooling.

**obra/superpowers confirms recommendation-first contextually.** Two of three examined skills
(brainstorming, writing-plans) use recommendation-first when the agent has a genuine opinion.
One skill (finishing-a-development-branch) uses neutral presentation when the choice is outside
the agent's domain. This matches the distinction decision-presentation.md draws between
Selection Decision (agent has evidence) and Approval Decision (agent has arrived at a single
course of action).

**AskUserQuestion is not documented as a decision-presentation tool by Anthropic.** The Anthropic
skills and plugins documentation mentions AskUserQuestion exists but provides no guidance on
its structure. The tsukumogami helper's convention — option ordering, description field grounding,
None-of-these escape hatch — is original convention, not an Anthropic prescription.

**Equal-options tiebreaker transparency** ("I picked A because it sorts alphabetically") has no
published precedent in the examined sources. It's a sensible practice (users handle explicit
tiebreakers better than manufactured preferences) but not a documented pattern elsewhere.

---

## Summary findings

### decision-presentation.md

**Alternatives exist?** No equivalent helper or shared pattern in obra/superpowers or Anthropic
official materials. Individual obra skills implement recommendation-first inline; Anthropic
prescribes nothing. The pattern itself (recommendation-first, evidence-grounded descriptions,
binary vs. selection variants, equal-options tiebreaker) is entirely tsukumogami-specific
convention.

**Current consumers:** `/explore` SKILL.md (Phase 3 loop decision), `/explore` phase-3-converge,
`/explore` phase-5-produce, `/design` phase-2-present-approaches, `/design` phase-3-deep-
investigation, `/design` phase-4-architecture, `/design` phase-6-final-review, `/prd`
phase-2-discover, `/prd` phase-3-draft. Nine reference sites across three skills.

**Verdict: Keep as helper.** Its value is consistency across nine reference sites in three
skills. Dropping it would leave each skill to implement the pattern independently, which has
happened elsewhere in the industry (obra implements it three different ways across three skills).
Converting it to an invocable skill adds overhead with no benefit — the content is passive
context, not executable logic. It ships to shirabe consumers verbatim.

---

### design-approval-routing.md

**Alternatives exist?** No equivalent in obra/superpowers. obra's `finishing-a-development-branch`
is the closest analog (post-work routing) but takes a neutral-presentation approach (four equal
options, no recommendation). Anthropic has no equivalent. This helper is tsukumogami-original.

**Current consumers:** `/design` SKILL.md (referenced from Phase 6 step 6.8) and `/explore`
Phase 5 (produce). Two reference sites across two skills. The reference from `/explore` phase-5
implies the routing logic fires after the explore workflow determines a design doc is the right
artifact.

**Verdict: Keep as helper.** Not because no alternative exists, but because the two-skill shared
reference prevents duplication and signals to contributors that routing is centralized. Folding
it into the `/design` skill would require either duplicating it in `/explore` or removing it
from explore's post-crystallize flow — both worse outcomes. It ships to shirabe consumers with
a note (already in the extraction audit) that the label-lifecycle deference in step "Source issue
updates" is extension-layer behavior and becomes a no-op for consumers who don't use the label
workflow.

---

## Implications for shirabe skill extraction

Neither helper needs redesign before shipping. Both are classified "portable" in the extraction
audit and that assessment holds after external comparison.

The one note for design-approval-routing.md: the phrase "as described in the `design` skill's
lifecycle section" in the Source Issue Updates section will need to be verified at extraction
time. If the label lifecycle section is an extension-only block in shirabe's base design skill,
this deference must still point to a real location or be worded as "if your project defines a
label lifecycle, follow it here."

No changes needed to decision-presentation.md before shipping.
