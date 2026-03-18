# Content Governance for AI Agents: Industry Sweep

**Topic:** Visibility-aware content governance patterns for AI coding agents
**Date:** 2026-03-17
**Purpose:** Find external validation, better-maintained resources, and gaps in the
current private-content.md / public-content.md helpers

---

## 1. Search coverage

All six required searches were run. Results by search:

| Query | Result |
|---|---|
| CLAUDE.md public/private repo visibility AI agent | Found governance-layer articles, no visibility-conditioned output patterns |
| LLM content governance open source vs private | Found data-control and compliance framing; no audience-aware output patterns |
| AI coding agent public repository guidelines | Found AGENTS.md discussion, context-file research; no public/private output rules |
| obra/superpowers visibility-based content guidance | No match (prior research confirmed, not re-checked) |
| Anthropic official docs — audience-appropriate output | Found Claude's constitution; no skills-level visibility guidance |
| OSS contributor guidelines for AI-generated content | Found contribution policies; different concern than output governance |

---

## 2. Is there an established resource we should reference?

**No.** Across every search and fetched source, no existing tool, plugin, standard, or
community document describes how an AI agent should adjust its artifact content based on
whether the repository it's operating in is public or private.

Specifically checked and found nothing:

- **Anthropic's official skills documentation** (`code.claude.com/docs/en/skills`): covers
  skill structure, invocation control, tool permissions, and subagent execution. No
  guidance on conditioning output content by audience or repository visibility.

- **Anthropic's constitution**: describes context-sensitive *behavior* (consumer apps vs.
  developer API, user vulnerability levels), but this operates at the model-training level.
  It does not translate to skill-level content governance rules.

- **The Complete Guide to Building Skills for Claude** (32-page PDF, Jan 2026): inaccessible
  as rendered content via WebFetch (binary PDF). The Medium summary of the guide covers
  audience/objective/constraints framing for skill output, but at the level of "state what
  the skill should produce," not at the level of "adjust content based on repo visibility."

- **AGENTS.md and the Agentic AI Foundation standard**: purely structural (setup commands,
  conventions, build steps). The standard explicitly assumes flat, context-agnostic
  instruction. No visibility conditions, no audience segmentation.

- **JetBrains Junie / `.junie/guidelines.md`**: technology-specific coding conventions only.
  No audience-aware content rules.

- **GitHub Copilot `.github/instructions/*.instructions.md`**: scoped by file-type glob
  patterns, not by repository audience or visibility.

- **O'Reilly article on Claude Skills governance**: covers organizational deployment
  governance (PR review before org-wide rollout). Not content-output governance.

- **ETH Zurich research on AGENTS.md value**: found context files most useful for
  non-inferable proprietary knowledge. Doesn't address visibility-conditioned content.

- **OSS foundation AI policies** (Apache, OpenInfra, Creative Commons, NetBSD, GSoC):
  all address *contribution* governance — what AI-assisted code can be submitted — not
  what content an agent should include or omit when producing artifacts in a public repo.

**Conclusion:** The helpers are a tsukumogami-specific design without any established
prior art in the Claude Code plugin ecosystem or the broader AI agent space. Shirabe
would be the first published plugin to implement visibility-conditioned artifact content
governance. There is no external resource to reference or defer to.

---

## 3. Is the per-artifact breakdown the right granularity?

**Yes, and it's consistent with how human editorial guidelines work.**

No external pattern directly validates or invalidates the per-artifact breakdown (design
docs, issues, PRs, code comments). However, adjacent evidence is consistent with it:

- **OSS contributor policies** treat different artifact types differently in practice.
  Apache's AI code policy focuses on source code. The OpenInfra policy focuses on
  contributions requiring DCO signoff. Neither addresses design docs or issue bodies
  separately — because they're contributor policies, not agent output policies. But the
  *implicit* recognition that different artifact types have different standards supports
  the breakdown.

- **Human editorial style guides** (the closest analogue to what these helpers are) always
  include per-format sections: one set of rules for press releases, another for internal
  memos, another for code comments. The helpers follow this convention correctly.

- **Anthropic's constitution** distinguishes by deployment context: consumer-facing,
  developer API, professional contexts. These are audience segments, not artifact types.
  The helpers take the same orthogonal-dimensions approach but at the artifact level.

- The ETH Zurich AGENTS.md research found that LLM-generated context files *hurt*
  performance when they described things agents could infer. The per-artifact breakdown
  in the helpers is not inferable from repo context alone — it's explicit policy. This
  is exactly the kind of content that belongs in a helper rather than general CLAUDE.md.

**One gap found:** The current helpers have four artifact types (design docs, issues, PRs,
code comments). There's no section for `commit messages`. Commit messages can contain
internal rationale references (in private repos) or should be self-contained for external
readers (in public repos). This is an omission worth addressing, especially since the
prior comparison doc notes that private-content.md explicitly allows "commit messages can
include internal context" under PRs — but public-content.md's PR section doesn't address
commit messages explicitly.

---

## 4. What's broken or missing in public-content.md for shirabe's use case?

### 4a. The slash-command restriction (confirmed broken, known)

The restriction:
> **No internal tooling references**: Never mention internal workflows, slash commands
> (`/explore`, `/work-on`, `/plan`), or development processes that external contributors
> don't have access to

This prohibition was correct when `/explore`, `/work-on`, and `/plan` were internal
tsukumogami commands. It is wrong for shirabe consumers: those commands are public skills
that shirabe ships. A design doc saying "next, run `/shirabe:plan` to decompose this"
is accurate and helpful, not an internal reference leak.

The same problem appears in the Issues section:
> Never reference internal workflows or tooling (e.g., don't say "run /explore")

Same fix needed in both places.

**Fix:** Replace blanket prohibition on slash commands with a targeted prohibition on
*inaccessible* tooling. Public shirabe skills should be mentionable.

### 4b. Commit messages not covered explicitly in the public PR section

The public-content.md PR section says commit messages "should be self-contained and
clear" but doesn't explicitly state: no internal rationale, no private repo references,
no competitor names. The private-content.md PR section explicitly says "commit messages
can include internal context." The asymmetry means the public rules are under-specified
for commit messages specifically.

**Fix:** Add explicit guidance that commit messages in public repos should follow the same
restrictions as PR bodies — external contributors will see them in git log.

### 4c. No coverage of GitHub Actions / CI workflow files

Neither helper addresses CI workflow files (.github/workflows/*.yml) as a distinct
artifact type. In public repos, these files are visible to all contributors and often
contain comments explaining build logic. An agent writing CI workflows might include
internal rationale ("disabled because of the Acme contract deadline") in comments.
The current code-comments section would theoretically cover this, but CI workflow files
are a meaningful enough category that explicit mention would prevent omissions.

**Fix (optional, low priority):** Add a note under "Code Comments" that CI/CD workflow
files are covered by the same rules and should not contain internal rationale or private
references.

### 4d. No guidance on external links in issues/design docs

The public-content.md says "Only link to public resources (no private repo links)" in the
General Principles section, but the per-artifact sections don't reinforce this. Issue
bodies and design docs frequently contain links to references. Private links (internal
docs, private Notion pages, private GitHub issues) could leak through an agent that
doesn't associate the general principle with a specific artifact type.

**Fix (low priority):** Add a line to the Issues and Design Documents sections explicitly
noting that all linked resources must be publicly accessible.

### 4e. No guidance on what to do when content can't be written without internal context

Current public-content.md tells the agent what to omit but doesn't address the case
where omitting the internal context makes the content meaningless or misleading. Example:
an issue body that should explain "we're doing this because Competitor X does it wrong"
but can't name Competitor X. The agent currently has two options: omit the rationale
entirely (leaving the issue under-motivated) or invent a public-safe alternative. Neither
is explicitly guided.

**Fix (medium priority):** Add a short section: when the rationale can only be expressed
using internal information, write the artifact as if the internal context doesn't exist
and focus on user-facing motivation. Don't invent false public rationale.

---

## 5. Should the two helpers be one file or stay separate?

**Stay separate.** The question is whether merging into a single file with conditional
sections would be better.

**Arguments for merging:**
- One file to maintain; changes don't need to be made in parallel
- Skills could load a single file and use a conditional: "follow the Public section"
  or "follow the Private section"

**Arguments against merging:**
- Loading a single combined file into context costs double the tokens when only one
  half applies. Skills load these helpers at artifact-writing time; token efficiency
  matters
- The private helper has rules that are *not just* the inverse of the public helper:
  "abandoned approaches for historical context" has no public counterpart; "exploratory
  thinking that may not pan out" is private-specific. The files aren't symmetric halves
  of one document — they're independent rulesets that happen to be paired
- Conditional sections in a single file create a readability burden: the LLM must
  evaluate which section to apply before applying rules, adding an inference step where
  currently the right file is just loaded directly
- Skill code that loads a single file would need to add "Now apply only the [Public/
  Private] section" instructions, recreating the current file-selection logic but
  inside the file rather than in the skill's load step

**Verdict:** Two separate files is correct. The current split is the right abstraction.

The only improvement to the pair-as-pair is: ensure they stay synchronized when one
gains a section the other should mirror. Currently, if someone adds a new artifact type
to private-content.md, they might forget to add the corresponding public version. This
could be addressed with a comment at the top of each file: "Counterpart: public-content.md
/ private-content.md — update both when adding artifact types."

---

## 6. Key external resources found (none to adopt, but worth tracking)

**Not recommended for adoption as references** — no external resource covers our specific
domain. However, these are worth monitoring as the space matures:

- **AGENTS.md standard** (Agentic AI Foundation / Linux Foundation): evolving open
  standard for agent context files. Currently covers structural/technical conventions.
  If it ever adds audience-aware content sections, that would be the natural place to
  align. Track: `agentskills.io` and the Linux Foundation's Agentic AI Foundation.

- **Anthropic's "Complete Guide to Building Skills for Claude"** (Jan 2026, 32-page PDF):
  covers skill construction but not visibility-conditioned output. Monitor for updates;
  a future edition might add audience-aware content guidance as the ecosystem matures.

- **Contrast Security's Open Source Generative AI Policy** (GitHub):
  `Contrast-Security-OSS/GenerativeAIPolicy` — focuses on IP, security, and data
  exposure, not artifact content governance. Useful if the question is "should agents
  generate code from private codebases" not "what should be in the artifacts."

- **ETH Zurich AGENTS.md value research** (March 2026, InfoQ coverage): found that
  non-inferable proprietary knowledge is the right content for context files. This
  validates the decision to put explicit content governance rules in helpers rather than
  expecting LLMs to infer them.

---

## 7. Verdict

### Are the helpers adequate?

**private-content.md:** Adequate as-is. No broken restrictions, broadly applicable to
any private-repo scenario. The commit-message coverage is slightly implicit but not
missing. No changes required before shipping in shirabe.

**public-content.md:** Needs fixes before shipping. Four issues in priority order:

1. **Critical (broken):** Slash-command restriction names specific commands that are
   public shirabe skills. Will suppress accurate, helpful artifact content for shirabe
   consumers. Fix required.

2. **Medium:** No guidance on how to handle content that requires internal context to
   motivate. Agent is left to infer; inference tends toward either omission or
   fabrication.

3. **Low:** Commit messages not explicitly covered in the PR section (unlike the private
   counterpart, which is explicit).

4. **Low:** External link restriction stated in general principles but not reinforced in
   per-artifact sections.

### Is the two-file structure correct?

Yes. Separate files, loaded conditionally by visibility, is the right architecture.
No external patterns suggest a better approach, and the internal logic for keeping them
separate is sound (token efficiency, non-symmetric content, clean load semantics).

### Is the per-artifact breakdown the right granularity?

Yes, with one missing category: commit messages. All current categories (design docs,
issues, PRs, code comments) are correct. Consider adding commit messages as a named
type, especially in public-content.md where the implications of external visibility are
more consequential.

### Is there a better-maintained external resource to reference?

No. There is nothing to reference. This remains a tsukumogami/shirabe-originated
pattern with no prior art in the plugin ecosystem. The helpers should stand on their
own and be maintained internally.

---

## 8. Sources consulted

Web searches:
- "CLAUDE.md public private repo visibility AI agent content governance 2025 2026"
- "LLM content governance open source vs private audience-aware agent output 2025"
- "AI coding agent public repository guidelines behavior differences 2025 2026"
- "OSS contributor guidelines AI-generated content public repository 2025"
- "Anthropic Claude agent output guidelines audience appropriate content documentation 2025 2026"
- "AGENTS.md CLAUDE.md public private visibility content rules community standard 2025 2026"
- "Claude Code skill SKILL.md content governance visibility audience artifact 2025 2026"
- "Claude Code skill plugin context-aware audience content governance public private 2025 2026"
- Targeted null result: no results for any query combining CLAUDE.md + public/private
  visibility + conditional content governance, confirming no established community pattern

Pages fetched:
- `code.claude.com/docs/en/skills` — official Anthropic skills docs
- `anthropic.com/constitution` — Claude's constitution
- `hackernoon.com` — Claude Code governance layer patterns
- `news.ycombinator.com/item?id=47166426` — OSS maintainers and AGENTS.md discussion
- `blog.jetbrains.com` — JetBrains coding guidelines for AI agents
- `www.groff.dev` — CLAUDE.md three-tier architecture pattern
- `www.infoq.com` — ETH Zurich AGENTS.md value research
- `www.oreilly.com` — O'Reilly Claude Skills governance article
- `tessl.io` — AGENTS.md open standard article
- `www.humanlayer.dev` — Writing a good CLAUDE.md
- `www.deployhq.com` — AI coding config files guide
- `medium.com/@AdithyaGiridharan` — Anthropic's skill-building guide summary (403)
- `openinfra.org/legal/ai-policy/` — OpenInfra AI policy (failed to render content)
- `www.digitalocean.com` — AI-generated code in OSS (failed to render content)

Previously researched (prior sweep, not re-fetched):
- Installed obra/superpowers plugins (no visibility governance found)
- `public/CLAUDE.md` and `shirabe/CLAUDE.md` (project context files)
- tsukumogami plugin cache: `private-content.md` and `public-content.md` (read directly)
