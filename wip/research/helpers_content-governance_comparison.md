# Content Governance Helpers: Comparison and Assessment

**Topic:** private-content.md and public-content.md helpers in tsukumogami
**Date:** 2026-03-17
**Purpose:** Determine whether these helpers are still needed in their current form for shirabe

---

## 1. What these helpers are and how they're used

Both helpers are loaded by skills at artifact-writing time based on repo visibility. The
pattern is consistent across five skills (design, prd, issue-drafting, pr-creation, design-doc)
and one agent (techwriter):

```
## Repo Visibility

Before writing content, determine visibility:
- **Private repos:** Read `../../helpers/private-content.md`
- **Public repos:** Read `../../helpers/public-content.md`
```

The LLM reads the repo's CLAUDE.md, detects `## Repo Visibility: Private/Public`, then
fetches the appropriate helper before producing any artifact content.

**private-content.md** covers: competitor mentions, internal rationale, pre-announcement
discussions, cross-repo references, private links. Gives per-artifact guidance (design docs,
issues, PRs, code comments).

**public-content.md** covers: no competitor names (especially negative), no internal
rationale, no internal tooling references, only public repo links, welcoming tone. Gives
per-artifact guidance. Includes one specific restriction: "Never mention internal workflows,
slash commands (`/explore`, `/work-on`, `/plan`), or development processes that external
contributors don't have access to."

---

## 2. obra/superpowers: no comparable mechanism found

No plugin in the installed marketplace or cache exposes visibility-based content governance.
The installed plugins examined:

- **Anthropic official** (frontend-design, rust-analyzer-lsp): Standalone aesthetic/LSP
  skills. No audience-aware content filtering. frontend-design's SKILL.md has no mention
  of visibility, repo context, or output audience.

- **Stripe best practices**: Technical guidance with no visibility branching.

- **plugin-dev (plugin-structure, agent-development, mcp-integration)**: Structural guidance
  for plugin authors. No content governance.

- **code-quality, enterprise-devops** (examples): No per-audience content rules.

The Anthropic CHANGELOG and marketplace README contain no guidance for visibility-conditioned
output or audience-aware content filtering.

**Conclusion:** obra/superpowers has no public/private content governance. The helpers are a
tsukumogami-specific design. Shirabe would be creating something with no industry-installed
prior art in the Claude Code plugin ecosystem.

---

## 3. Does the CLAUDE.md visibility header make these helpers partially redundant?

The CLAUDE.md header (`## Repo Visibility: Public`) provides the detection signal but not
the rules. The header tells skills which mode they're in; the helpers tell them what that
mode means for each artifact type.

**What CLAUDE.md alone provides:**

- Binary signal: Private or Public
- Repo-level context already in context window (general CLAUDE.md instructions)
- The tsukumogami CLAUDE.md exploration skill (explore/SKILL.md) detects visibility and
  logs it: "Exploring with [Private|Public] visibility..."

**What CLAUDE.md alone does NOT provide:**

- Per-artifact rules (issues vs. PRs vs. design docs differ in restrictions)
- Specific word/phrase prohibitions ("no competitor names in negative contexts")
- The distinction between "no internal rationale" vs. "no competitor names at all"
- Tone guidance ("welcoming to first-time contributors")
- Cross-repo reference rules (only public repo links)

**Assessment:** The CLAUDE.md header is necessary but not sufficient. A skill that reads
only the visibility header would need to infer all content rules from LLM defaults. LLM
defaults for "public repo content" are generic and inconsistent. The helpers make the rules
explicit and specific.

However, the helpers are currently loaded lazily (skills read them at artifact-writing time).
If the CLAUDE.md already contains the project's public/shirabe/CLAUDE.md restrictions
verbatim (which it does in the `public/CLAUDE.md` file), there's overlap. The workspace
`public/CLAUDE.md` already specifies:

- No competitor names in negative contexts
- No internal business rationale
- No internal tooling references
- Only public repo links
- Professional and welcoming

But this CLAUDE.md coverage is workspace-specific, not plugin-level. Shirabe consumers who
don't have this workspace CLAUDE.md would get no guidance from project context alone. The
helpers provide portable, self-contained rules that travel with the plugin.

**Assessment:** The CLAUDE.md header makes the helpers partially redundant for consumers
with well-configured project CLAUDE.md files. For standalone plugin consumers (the target
market for shirabe), the helpers remain the primary content governance mechanism.

---

## 4. The "internal tooling reference" restriction problem

**The specific restriction in public-content.md:**

> **No internal tooling references**: Never mention internal workflows, slash commands
> (`/explore`, `/work-on`, `/plan`), or development processes that external contributors
> don't have access to

This restriction was written when `/explore`, `/work-on`, and `/plan` were private internal
commands that external contributors couldn't use. That framing no longer holds when shirabe
ships them as public skills.

**The problem in concrete terms:**

A shirabe consumer running `/shirabe:design` on a public repo would trigger a load of
public-content.md, which would instruct the LLM to never mention `/explore` or `/plan` in
any produced artifact (design doc, issue, PR body). But:

1. For a shirabe consumer, `/shirabe:explore` and `/shirabe:plan` are available tools,
   not hidden internal workflows
2. A design doc produced by `/shirabe:design` might legitimately reference `/shirabe:plan`
   as the next step
3. An issue body that says "after this design is accepted, run `/shirabe:plan` to decompose
   it" is accurate and helpful, not an internal reference leak

The restriction is wrong for shirabe consumers. It would suppress accurate, helpful
references to publicly-available shirabe skills.

**Why this hasn't caused visible problems yet:** The tsukumogami plugin is the only current
consumer. In the tools repo context, `/explore` and `/plan` are tsukumogami skills. From
the perspective of a private repo (where these skills are used in production), they're
effectively internal. The restriction makes sense for tsukumogami's context. It fails for
shirabe's public plugin context.

**Fix needed:** The restriction should be scoped to "internal-only tooling" rather than
banning all slash command references. A shirabe-specific version would say: "Don't reference
internal workflows or tools that external contributors can't access. Public shirabe skills
like `/shirabe:explore` and `/shirabe:plan` may be referenced when they're relevant."

---

## 5. Could these be CLAUDE.md headers instead?

The design introduced `## Label Vocabulary` as a CLAUDE.md header for project-specific
customization. The question is whether content governance rules could follow the same pattern.

**What a CLAUDE.md header approach would look like:**

```markdown
## External Contributors: Yes
```

or more specifically:

```markdown
## Content Audience: Public
## Competitor References: Prohibited
## Internal Tooling References: Prohibited
```

**What would be gained:**

- Inline with other project-level settings
- Consistent with the `## Label Vocabulary` pattern the design already introduced
- Consumers can override per-project (e.g., a company might allow competitor comparisons
  even in public repos)
- No separate file to load; rules are already in context via CLAUDE.md

**What would be lost:**

- Per-artifact breakdown (different rules for issues vs. PRs vs. design docs) can't be
  expressed as a single header value
- Headers are binary or vocabulary-typed; they can't carry prose guidance like "be welcoming
  to first-time contributors" or "explain why for non-obvious decisions"
- Headers work for structured config; content governance involves nuanced tone and prose
  judgment calls that don't reduce to key-value pairs
- The current helpers are ~50 lines each with multiple levels of specificity. A CLAUDE.md
  header equivalent would either be a single oversimplifying flag or a verbose
  multi-section block that duplicates what the helpers already do

**Hybrid view:** Headers are the right mechanism for the binary public/private detection
signal (already implemented). They work for vocabulary customization (`## Label Vocabulary`).
They're the wrong mechanism for multi-clause behavioral rules that require prose explanation
and per-artifact guidance. The helpers serve the latter purpose.

**Assessment:** Headers can replace the *detection* side of content governance. They can't
replace the *rules* side without either oversimplifying or recreating the helpers inline
in CLAUDE.md. The current separation of concerns is sound: header detects, helper elaborates.

---

## 6. Industry patterns for agent content governance by audience

**Searching the broader plugin ecosystem and practices:**

No installed plugin implements visibility-based content governance. The Claude Code
plugin ecosystem as of this analysis treats skills as context providers rather than
audience-aware content filters. All Anthropic-published skills (frontend-design,
stripe-best-practices) assume a single audience and provide a single rule set.

**Comparable patterns in adjacent domains:**

1. **Documentation tools with audience modes (Divio, Diataxis):** Documents are typed
   by audience (tutorials vs. reference vs. explanation) but content filtering by audience
   visibility is not automated.

2. **CMS content staging:** "Draft" vs. "Published" content with different visibility rules
   is standard in CMS systems, but the filtering is done by the platform, not by AI agents
   interpreting context.

3. **Enterprise AI guidelines:** Large organizations using LLMs for content creation
   increasingly implement per-audience instruction sets (internal docs vs. external docs).
   These are typically implemented as system prompt fragments or persona instructions,
   not as runtime-loaded helper files.

4. **Per-artifact breakdown:** The helpers' approach of breaking rules down by artifact
   type (design docs, issues, PRs, code comments) matches how human editorial guidelines
   work. Style guides for organizations typically include per-format sections. This
   per-artifact specificity is appropriate — an issue description has different standards
   than a design doc's Market Context section.

**What's standard vs. novel:**

- Standard: Having different content rules for internal vs. external content
- Standard: Per-audience instruction sets for AI agents
- Novel: Loading these rules at runtime from separate files based on repo metadata
- Novel: Using CLAUDE.md headers as the detection mechanism for which rule set to apply

The helpers' runtime-loading pattern is a tsukumogami-specific innovation without
established precedent in the plugin ecosystem. This doesn't make it wrong, but it means
shirabe can't point to external patterns for validation.

---

## 7. Assessment by research question

### Q1: Does obra/superpowers have public/private content governance?

**No.** No comparable mechanism found in any installed plugin, official or third-party.
The helpers are unique to tsukumogami.

### Q2: Does the CLAUDE.md visibility header make these helpers partially redundant?

**Partially, but not fully.** The header provides the detection signal. The helpers provide
the rules, including per-artifact specificity and tone guidance that can't be expressed in
a header value. For shirabe as a distributed public plugin, the helpers remain necessary
because consumers won't all have well-configured project CLAUDE.md files.

### Q3: Is the content generic enough to ship to all consumers?

- **private-content.md:** Yes. The content is broadly applicable to private repo work
  for any team. No tsukumogami-specific assumptions. Ships as-is.

- **public-content.md:** No, in its current form. The slash command restriction names
  `/explore`, `/work-on`, `/plan` as forbidden internal references. For a shirabe consumer,
  these are public skills, not internal tooling. The restriction actively harms correctness.
  Needs revision before shipping.

### Q4: Could these be CLAUDE.md headers instead?

**The detection side yes; the rules side no.** Headers work for binary signals and
vocabulary. Multi-clause behavioral rules with per-artifact guidance require prose. The
current separation (header detects, helper elaborates) is structurally sound.

### Q5: Industry patterns?

**No established patterns in Claude Code plugins.** Adjacent domains (CMS, enterprise AI
guidelines) validate the concept of per-audience content rules but not this specific
runtime-loading implementation.

---

## 8. Verdict

### Are these helpers still needed in their current form?

**private-content.md:** Needed. Content is broadly applicable. No changes required for
shirabe.

**public-content.md:** Needed but broken. The slash command restriction is wrong for
shirabe consumers. The rest of the content is sound and necessary.

### What changes would make them correct for shirabe as a public plugin?

One targeted change to public-content.md is required. The current line:

> **No internal tooling references**: Never mention internal workflows, slash commands
> (`/explore`, `/work-on`, `/plan`), or development processes that external contributors
> don't have access to

Should become:

> **No internal tooling references**: Don't mention internal-only workflows, tools, or
> development processes that external contributors can't access. Public shirabe skills
> (like `/shirabe:explore` and `/shirabe:plan`) may be referenced when they're the
> appropriate next step.

The per-artifact sections under "Issues" and "Pull Requests" have similar lines:

> Never reference internal workflows or tooling (e.g., don't say "run /explore")

These should be updated to clarify that the prohibition is on *private/inaccessible* tooling,
not on public skills.

No other content changes are needed. The general principles, tone guidance, and other
restrictions in public-content.md are correct for a public plugin.

### Helper vs. CLAUDE.md header vs. inline skill guidance

**Three-part answer:**

1. **CLAUDE.md header for detection:** Keep `## Repo Visibility:` as the detection
   mechanism. It's already implemented. Skills read it to determine which helper to load.
   This is the right level of abstraction for detection.

2. **Helper files for rules:** Keep the helper files as the rules carrier. The per-artifact
   breakdown and prose guidance cannot be reduced to CLAUDE.md headers without losing
   specificity. The helper pattern also makes the rules auditable: a consumer can read
   exactly what content governance their project will enforce.

3. **Inline guidance for skill-specific edge cases:** Some skills have unique content
   requirements (e.g., explore/SKILL.md Phase 5 checking visibility before producing a
   competitive analysis). These inline checks belong in the skill, not in the helpers,
   because they're decision gates rather than prose-quality rules. The competitive analysis
   gate in explore/SKILL.md is the right model: a concrete check with an explicit refusal
   path, not a prose guideline.

The current architecture is correct in structure. The only required fix is the slash command
restriction in public-content.md.

---

## 9. Files and paths referenced

| File | Path |
|------|------|
| private-content.md | `/home/dangazineu/.claude/plugins/cache/tsukumogami/tsukumogami/0.1.0/helpers/private-content.md` |
| public-content.md | `/home/dangazineu/.claude/plugins/cache/tsukumogami/tsukumogami/0.1.0/helpers/public-content.md` |
| explore/SKILL.md (visibility detection) | `/home/dangazineu/.claude/plugins/cache/tsukumogami/tsukumogami/0.1.0/skills/explore/SKILL.md` |
| design/SKILL.md (helper invocation) | `/home/dangazineu/.claude/plugins/cache/tsukumogami/tsukumogami/0.1.0/skills/design/SKILL.md` |
| prd/SKILL.md (helper invocation) | `/home/dangazineu/.claude/plugins/cache/tsukumogami/tsukumogami/0.1.0/skills/prd/SKILL.md` |
| public/CLAUDE.md | `/home/dangazineu/dev/workspace/tsuku/tsuku-5/public/CLAUDE.md` |
| shirabe/CLAUDE.md | `/home/dangazineu/dev/workspace/tsuku/tsuku-5/public/shirabe/CLAUDE.md` |
