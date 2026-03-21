# Industry Sweep: Agent Decision Presentation Patterns

Research date: 2026-03-17
Scope: How AI agents should present choices to users — industry guidance, HCI research, community patterns, and comparison to shirabe's `decision-presentation.md` helper.

---

## 1. What the helper currently does

File: `~/.claude/plugins/cache/tsukumogami/tsukumogami/0.1.0/helpers/decision-presentation.md`

Key positions:
- Agents form a **recommendation**, not a neutral list.
- **Selection decision**: recommended option first (marked "(Recommended)"), alternatives ranked lower with explicit reason for ranking, description grounded in evidence from investigation.
- **Approval decision**: propose + Approve / Reject options. State what alternatives were ruled out and why.
- **Equal options**: still pick one; explain the tiebreaker explicitly. Don't manufacture a false preference.
- **Escape hatch**: "None of these" as a final option when appropriate.

---

## 2. Industry sources surveyed

### 2.1 Anthropic official docs

**Skill authoring best practices** (platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices):

Contains one directly relevant passage under "Anti-patterns to avoid":

> **Avoid offering too many options**
> Don't present multiple approaches unless necessary:
> "You can use pypdf, or pdfplumber, or PyMuPDF, or pdf2image, or..."
> **Good example: Provide a default** (with escape hatch):
> "Use pdfplumber for text extraction. For scanned PDFs requiring OCR, use pdf2image with pytesseract instead."

This matches the helper's recommendation-first stance. Anthropic's official stance: agents should provide a default and only surface alternatives when genuinely needed.

**AskUserQuestion tool docs** (platform.claude.com/docs/en/agent-sdk/user-input):

Describes the mechanical format: 1–4 questions, 2–4 options per question, single-select or multi-select, optional HTML/markdown previews. Does **not** specify how to order options or whether to pre-mark a recommendation. The tool structure is neutral on this question.

The docs note Claude generates options based on investigation; the spec says nothing about ordering or recommendation-first. This is a genuine gap in official guidance.

**Claude system prompt (extracted from 404 page)**: "avoid offering more than one question per response" and use AskUserQuestion for structured choices. Consistent with the helper.

### 2.2 Smashing Magazine: Designing for Agentic AI (Feb 2026)

Source: smashingmagazine.com/2026/02/designing-agentic-ai-practical-ux-patterns/

Six patterns described. Two are most relevant:

**Confidence Signal**: agents should communicate certainty levels ("Confidence: 95%") so users know when to scrutinize rather than accept. The helper has no equivalent — it treats all recommendations as equally confident.

**Escalation Pathway**: when agents are uncertain, they should acknowledge it and request clarification rather than guess. The helper's "equal options" section approximates this but doesn't frame it as a named posture.

**Intent Preview**: present a plan and get consent before acting. Closest analog in shirabe is the approval decision variant, but the framing differs — Intent Preview is about action plans, not option selection.

The article does not name a "recommendation-first" pattern explicitly. It assumes recommendation-with-rationale as the default and focuses on surrounding machinery: confidence signals, audit trails, undo.

### 2.3 obra/superpowers brainstorming skill

Source: github.com/obra/superpowers/blob/main/skills/brainstorming/SKILL.md

The skill explicitly prescribes recommendation-led presentation:

> "Lead with your recommended option and explain why."
> Propose "2–3 different approaches with trade-offs" before settling on a design direction.
> Present options "conversationally with your recommendation and reasoning."

This matches shirabe's helper almost exactly. First position = recommended approach with rationale. Following positions = alternatives with trade-offs explained.

The skill adds one element shirabe's helper lacks: multiple-choice questions are explicitly preferred over open-ended questions because they're "easier to answer." This is consistent with Hick's Law (see section 2.5) and with the AskUserQuestion tool's structured format.

### 2.4 obra/superpowers writing-skills skill

Uses a **negative-first framing** rather than recommendation-first: state what not to do, explain consequences, then present the correct alternative. This is a different pattern, suited to enforcing discipline ("Iron Law," "NEVER," "NO EXCEPTIONS") rather than guiding user choice. Not directly applicable to decision presentation in workflows.

### 2.5 HCI and cognitive psychology research

**Choice overload (Schwartz, "The Paradox of Choice")**: Presenting too many options causes decision paralysis. Fix is not fewer options but better choice architecture — visual cues, grouping, "Top Picks" framing. The helper's limit of a small number of options and an escape hatch aligns with this.

**Hick's Law**: Decision time increases with number and complexity of choices. Progressive disclosure and clear visual hierarchy help. The helper does not address the quantity limit, but the AskUserQuestion tool caps options at 2–4 per question mechanically.

**Anchoring bias**: First option presented is treated as the default or recommended choice. Users anchor on it. This is precisely why recommendation-first works — it aligns the anchoring effect with the agent's best judgment rather than leaving the anchor arbitrary.

**Automation bias** (Springer AI & SOCIETY systematic review, 2025; CSET Nov 2024):
- Defined as the tendency to over-rely on AI recommendations beyond what their reliability warrants.
- Amplified by: miscalibrated confidence (AI expresses certainty it doesn't have), anchoring effect, confirmatory bias (users seek corroborating evidence for the AI's recommendation).
- Risk is higher when AI states recommendations without uncertainty signals.
- Mitigation: explainable AI (grounding recommendations in evidence), confidence signals, transparency about alternatives and why they were rejected.

The helper's grounding requirement ("cite what you found: file names, API responses, compatibility constraints") directly addresses the automation bias risk by making the recommendation falsifiable. The "equal options" section also mitigates it: explicitly saying options are equal prevents false confidence.

**What's missing from the helper** given this research: there is no guidance for cases where the agent has low confidence. The helper distinguishes equal vs. unequal options but not uncertain vs. confident. A truly uncertain agent — where the right choice depends on information the agent doesn't have access to — is not covered. The escalation pathway (ask for more information rather than recommend) belongs here.

**ACM CHI 2022 literature review on conversational agent UX**:
- Choice architecture in HCI (Thaler and Sunstein's nudge theory): "any aspect of the choice architecture that alters people's behavior in a predictable way without forbidding any options."
- Recommender systems can personalize nudges but most HCI work hasn't studied how personalized advice should be presented for habit change.
- Conversation as an interface is often a poor fit — constrained, structured options outperform open-ended text for many decision types. Consistent with the AskUserQuestion tool design.

**IBM Natural Conversation Framework**: 100 generic UX patterns for conversational interfaces. Not publicly available at sufficient detail to extract specific decision-presentation patterns.

### 2.6 AskUserQuestion community guidance

Source: claudelog.com; neonwatty.com

Community usage confirms:
- Agents present multiple-choice options; users pick.
- No community consensus on option ordering or recommendation-first.
- The most documented pattern is **mandatory approval gates**: don't proceed without explicit user confirmation.
- The interview skill pattern (5–10 rounds of AskUserQuestion before implementation) is about information gathering, not recommendation-making.

Neither community source prescribes recommendation ordering. The helper fills a real gap.

---

## 3. Is "recommendation-first" a named, established pattern?

No. The search found no published pattern with this name. The closest named concept is **default option** or **smart default** in choice architecture literature, and **anchoring** in behavioral psychology. The pattern is implied by:

- Anthropic's "provide a default" anti-pattern guidance.
- obra/superpowers brainstorming skill ("lead with your recommended option").
- Choice overload / Hick's Law research (fewer, better-framed options improve decisions).
- Anchoring bias research (first position anchors perception — so it should be the recommendation).

The concept is real and well-supported. It just doesn't have a single canonical name. "Recommendation-first" is a clear and accurate description.

---

## 4. Failure modes the helper doesn't cover

### 4.1 Automation bias / over-recommendation

The helper says "agents aren't neutral facilitators — they form a recommendation." This is correct. But it creates a risk: agents may recommend confidently even when evidence is thin. The helper has no guidance for this case.

The automation bias literature is clear that confident-sounding recommendations without calibration signals (confidence level, evidence strength) increase the chance users accept wrong answers. The helper's grounding requirement (cite evidence) helps but is not sufficient when the agent has genuinely weak evidence.

**Gap**: the helper needs a posture for when investigation yields weak or ambiguous evidence. Candidates:
- Escalation: "I don't have enough information to recommend. Here is what I'd need to know."
- Calibrated recommendation: "I lean toward X, but this is based on limited evidence. Verify Y before proceeding."

### 4.2 Framing effects

The helper does not address how the description field is worded. Framing the same option positively vs. negatively produces different user behavior. Since the description is evidence-grounded, this risk is reduced — but agents can still systematically frame descriptions in ways that nudge users toward the recommendation beyond what the evidence supports.

**Gap**: no guidance on neutral description language for alternatives. Alternatives should be described accurately, not in ways that make them look worse than the recommendation deserves.

### 4.3 Confidence signals

The Smashing Magazine article identifies Confidence Signal as a distinct pattern. The helper has no analog. When an agent recommends SQLite over PostgreSQL with high confidence because the codebase has zero cloud infrastructure, that confidence is appropriate. When it recommends a dependency based on a single search result, it isn't.

**Gap**: no mechanism to signal recommendation confidence or evidence strength. Adding a qualifier in the description ("Based on three consistent signals in the codebase..." vs. "Based on limited investigation...") would address this.

### 4.4 Escape hatch semantics

The helper says include "None of these" as the final option "when appropriate for the workflow." It doesn't define when it's appropriate. In practice, omitting the escape hatch forces users to accept a recommendation or reject the whole workflow, which is a poor UX cliff.

**Gap**: guidance on when to include vs. omit the escape hatch. Default should probably be "include it always unless the workflow has a natural abort path."

### 4.5 Multi-select decisions

The AskUserQuestion tool supports multi-select. The helper covers only single-select (pick one option) and binary approval/reject. It has no pattern for multi-select decisions (e.g., "which of these features should we include?").

**Gap**: multi-select decisions need a different structure since there's no single "recommended" answer.

---

## 5. Is anything in the wild better than our helper?

Nothing surveyed is more complete. Comparisons:

| Source | Recommendation-first | Evidence grounding | Tiebreaker transparency | Uncertainty handling | Confidence signals |
|---|---|---|---|---|---|
| shirabe helper | Yes | Yes | Yes | Partial (equal options) | No |
| Anthropic skill docs | Implicit ("provide a default") | No | No | No | No |
| obra/superpowers brainstorming | Yes | Partial (trade-off articulation) | No | No | No |
| Smashing Magazine patterns | Implicit | Yes (Explainable Rationale) | No | Yes (Escalation Pathway) | Yes (Confidence Signal) |
| HCI/behavioral research | Anchoring implies it | No (academic) | No | Automation bias warns against gaps | Calibration research |

The helper is ahead of every comparable source on: recommendation-first stance, equal-options transparency, and evidence grounding. It is behind the Smashing Magazine model on: confidence signals and uncertainty handling.

No external resource is worth adopting wholesale. The Smashing Magazine article's Confidence Signal and Escalation Pathway patterns are worth adding to the helper.

---

## 6. Verdict

**The helper is adequate for the common case.** Recommendation-first is correct, well-supported, and not matched by any published guide. The equal-options tiebreaker transparency is a meaningful differentiator with no industry equivalent found.

**Three gaps worth addressing:**

1. **Uncertainty posture** (high priority): when investigation yields thin evidence, agents need an alternative to a confident recommendation. An escalation path — state what's unknown, ask what's needed — belongs in the helper as a third decision variant alongside selection and approval.

2. **Confidence calibration in descriptions** (medium priority): add guidance that descriptions should signal evidence strength. A one-liner: "If your evidence is thin or inconclusive, say so in the description. Don't write recommendations that sound more certain than the evidence supports."

3. **Escape hatch default** (low priority): clarify that "None of these" should be the default unless the workflow has an explicit abort path, not an exception that requires justification.

**One gap to monitor but not act on now:**

4. **Framing neutrality for alternatives**: real risk but hard to specify without examples. Watch for complaints that agents describe non-recommended options dismissively.

**Multi-select** is a structural gap (the helper doesn't cover it) but may be out of scope — it's a different decision type that may belong in a separate helper or AskUserQuestion-specific guide.

---

## 7. External references worth citing in the helper

If the helper is updated, the following are worth noting or citing:

- Anthropic skill docs anti-pattern: "avoid offering too many options" — aligns with recommendation-first.
- Anchoring bias (Tversky and Kahneman, 1974): first-position anchors perception. Recommendation-first aligns the anchor with best judgment.
- Automation bias (systematic review, AI & SOCIETY 2025): confident AI recommendations without evidence grounding increase over-reliance risk. The helper's grounding requirement is a direct mitigation.
- Hick's Law: more choices = slower decisions. Structural justification for limiting options and leading with a default.

None of these need inline citations in the helper — they're academic backing for design decisions already made. Mentioning them in internal commentary or this research doc is sufficient.

---

## Sources consulted

- Smashing Magazine: https://www.smashingmagazine.com/2026/02/designing-agentic-ai-practical-ux-patterns/
- Anthropic skill authoring best practices: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
- Anthropic AskUserQuestion / user input docs: https://platform.claude.com/docs/en/agent-sdk/user-input
- obra/superpowers brainstorming skill: https://github.com/obra/superpowers/blob/main/skills/brainstorming/SKILL.md
- obra/superpowers writing-skills: https://github.com/obra/superpowers/blob/main/skills/writing-skills/SKILL.md
- obra/superpowers repo: https://github.com/obra/superpowers
- Claude Code AskUserQuestion community: https://claudelog.com/faqs/what-is-ask-user-question-tool-in-claude-code/
- Multi-round interview skills: https://neonwatty.com/posts/interview-skills-claude-code/
- Eugene Yan LLM patterns: https://eugeneyan.com/writing/llm-patterns/
- Agentic design patterns (AufaitUX): https://www.aufaitux.com/blog/agentic-ai-design-patterns-enterprise-guide/
- AI UX Patterns: https://www.aiuxpatterns.com/
- Agentic design patterns (agentic-design.ai): https://agentic-design.ai/patterns/ui-ux-patterns
- Automation bias systematic review (AI & SOCIETY 2025): https://link.springer.com/article/10.1007/s00146-025-02422-7
- CSET AI Safety and Automation Bias (Nov 2024): https://cset.georgetown.edu/wp-content/uploads/CSET-AI-Safety-and-Automation-Bias.pdf
- Bias in the Loop (arXiv 2025): https://arxiv.org/html/2509.08514v1
- Choice overload (Renascence): https://www.renascence.io/journal/choice-overload-difficulty-in-making-decisions-with-too-many-options
- Cognitive biases in UX (AufaitUX): https://www.aufaitux.com/blog/cognitive-bias-ux-design/
- Anchoring bias and Hick's Law: https://www.guvi.in/blog/cognitive-bias-in-ui-ux-understanding-anchoring-bias-and-hicks-law/
- CHI 2022 conversational AI UX literature review: https://dl.acm.org/doi/fullHtml/10.1145/3491102.3501855
- Choice Architecture for HCI: https://www.researchgate.net/publication/267927305_Choice_Architecture_for_Human-Computer_Interaction
