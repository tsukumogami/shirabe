# Industry Sweep: AI Writing Humanizer Tools and Resources

Research conducted: 2026-03-17

## Scope

This document surveys the landscape of AI writing humanizer tools, word blacklists, and anti-AI writing guidelines, then compares them against shirabe's `writing-style.md` helper. It covers blader/humanizer specifically (per user request), plus additional tools found via web search.

---

## 1. blader/humanizer

**Repo:** https://github.com/blader/humanizer
**Type:** Claude Code skill (SKILL.md)
**Foundation:** Wikipedia's "Signs of AI writing" (WikiProject AI Cleanup), compiled from observations of thousands of AI-generated text instances.

### What it does

blader/humanizer is a two-pass revision skill. Pass one identifies and rewrites 24 specific patterns across four categories. Pass two runs a final audit asking "what makes this still obviously AI-generated?" and revises again.

### 24 patterns by category

**Content patterns (6):**
1. Significance inflation — grandiose framing using "stands as," "serves as," "testament," "pivotal," "reflects broader," "evolving landscape"
2. Notability name-dropping — listing media outlets mechanically without context
3. Superficial -ing analyses — hollow gerund constructions: "highlighting," "underscoring," "emphasizing," "reflecting," "contributing"
4. Promotional language — "boasts," "vibrant," "profound," "breathtaking," "nestled in the heart," "breathtaking"
5. Vague attributions — "industry reports," "observers," "experts argue" without specific sources
6. Formulaic challenges — "Despite its..." / "Despite these challenges..." sections with generic future-prospects framing

**Language/grammar patterns (6):**
7. AI vocabulary — statistically overused terms: additionally, align with, crucial, delve, emphasizing, enduring, enhance, fostering, garner, highlight, interplay, intricate, key, landscape, pivotal, showcase, tapestry, testament, underscore, valuable, vibrant
8. Copula avoidance — replacing "is/are" with "serves as," "stands as," "boasts"
9. Negative parallelisms — "Not only...but," "It's not just about...it's"
10. Rule of three — forced triadic groupings without natural justification
11. Synonym cycling (elegant variation) — excessive synonym substitution to avoid apparent repetition
12. False ranges — "from X to Y" where X and Y are not on a meaningful scale

**Style patterns (6):**
13. Em dash overuse — where commas or periods would be natural
14. Boldface overuse — mechanical emphasis on terms, acronyms, emoji headers
15. Inline-header lists — bolded labels followed by colons in vertical lists (prose should be prose)
16. Title Case headings — capitalizing Every Word in headings
17. Emojis — decorative use in headings and bullet points
18. Curly quotes — smart quotation marks instead of straight quotes

**Communication patterns (6):**
19. Chatbot artifacts — "I hope this helps," "let me know if you have questions," "would you like me to..."
20. Knowledge-cutoff disclaimers — "as of my training," "based on available information," "as of [date]"
21. Sycophantic tone — "Great question!", "Absolutely!", "That's an excellent point!"
22. Filler phrases — "in order to," "due to the fact that," "at this point in time"
23. Excessive hedging — stacked qualifiers ("could potentially possibly be argued")
24. Generic conclusions — vague positive endings ("The future looks bright," "poised for growth")

### Key insight from blader/humanizer

Its framing is notable: LLMs generate statistically probable outputs, so their writing drifts toward broadly applicable phrasing rather than specific, authentic text. The fix is specificity, not just word substitution.

### Comparison to our helper

Our helper covers: overused words (partial list), overused phrases (partial), structural patterns (partial), punctuation tells (em dash, contractions), over-formality phrases.

blader/humanizer covers everything we do and adds:
- Copula avoidance ("serves as," "stands as") — not in our helper
- Negative parallelisms ("It's not just X, it's Y") — not in our helper
- Rule of three as a named pattern — we mention it in structural patterns but not as an AI signal specifically
- Synonym cycling / elegant variation — not in our helper
- False ranges — not in our helper
- Promotional language as a distinct category (boasts, breathtaking, nestled) — partially covered
- Vague attributions / unspecified expert claims — not in our helper
- Formulaic challenge/prospects sections — not in our helper
- Chatbot artifacts (I hope this helps) — not in our helper
- Sycophantic tone (Great question!) — not in our helper
- Knowledge-cutoff disclaimers — not in our helper
- Excessive hedging (stacked qualifiers) — not in our helper
- Inline-header lists as an AI structural tell — not in our helper
- Title Case headings — not in our helper
- Emojis as AI signal — not in our helper
- Curly quotes — not in our helper
- Superficial -ing analysis phrases — not in our helper
- Boldface overuse — not in our helper

---

## 2. Other tools and resources found

### Aboudjem/humanizer-skill

**Repo:** https://github.com/Aboudjem/humanizer-skill
**Description:** "30 AI patterns, 5 voice profiles, zero dependencies"
**Foundation:** NeurIPS 2023, ACL 2024, Washington Post ChatGPT analysis (328K messages), Wikipedia Signs of AI Writing

Extends blader's model with six additional patterns:
- Hallucination markers — fabricated dates, phantom citations
- Perfect/error alternation — inconsistent quality suggesting partial AI editing
- Question-format titles — "What makes X unique?"
- Markdown bleeding — `**bold**` syntax appearing in non-markdown contexts
- "Comprehensive Overview" openers — "This guide delves into...", "Let's dive in"
- Uniform sentence length — every sentence 15-25 words without variation

Five voice profiles (Casual, Professional, Technical, Warm, Blunt) with defined characteristics per profile — a dimension our helper entirely lacks.

Four linguistic dimensions drawn from research:
- Burstiness — varying sentence length dramatically (3-word sentences next to 40-word sentences)
- Perplexity — unexpected word choices humans naturally make
- Type-Token Ratio — vocabulary diversity (measured: human 55.3 vs. AI 45.5)
- Structural variation — eliminating predictable patterns

### lguz/humanize-writing-skill

**Repo:** https://github.com/lguz/humanize-writing-skill
**Description:** "3-pass editing system with 36+ banned words, 10 structural patterns, and a quality checklist"

Word tiers:
- Tier 1 (strongest AI signals, 18 words): delve, tapestry, pivotal, testament, and 14 others
- Tier 2 (moderate signals, 18 words): crucial, leverage, seamless, robust, and 14 others
- Tier 3 transitions: "Furthermore," "Moreover," "Additionally" — fine individually but AI clusters them

Structural patterns targeted (10):
- Parallel negation ("Not X, but Y")
- Tricolons (rule of three)
- Em dash overuse
- Rhetorical question-and-answer sequences
- Mirror structures
- Dramatic reveals
- Four others unspecified in public README

Three-pass process:
1. Vocabulary replacement
2. Structural pattern elimination
3. Human texture addition (contractions, sentence length variation, opinion clarity)

### sabrina.dev humanizer prompt

**URL:** https://www.sabrina.dev/p/best-ai-prompt-to-humanize-ai-writing

Provides a prompt with an extensive banned word list. Complete list from their prompt:

> Can, may, just, that, very, really, literally, actually, certainly, probably, basically, could, maybe, delve, embark, enlightening, esteemed, shed light, craft, crafting, imagine, realm, game-changer, unlock, discover, skyrocket, abyss, not alone, in a world where, revolutionize, disruptive, utilize, utilizing, dive deep, tapestry, illuminate, unveil, pivotal, intricate, elucidate, hence, furthermore, however, harness, exciting, groundbreaking, cutting-edge, remarkable, it, remains to be seen, glimpse into, navigating, landscape, stark, testament, in summary, moreover, boost, skyrocketing, opened up, powerful, inquiries, ever-evolving

Additional rules from the prompt:
- No em dashes (use commas, periods, or semicolons instead)
- No markdown formatting, no asterisks, no hashtags
- No metaphors or clichés
- No generalizations
- No unnecessary adjectives or adverbs
- No "not just this, but also this" constructions
- No "in conclusion" / "in closing"
- No output warnings or disclaimers
- Active voice; avoid passive voice

### TheBigPromptLibrary — Human Writer/Humanizer GPT

**URL:** https://github.com/0xeb/TheBigPromptLibrary
**Key technique:** Highest perplexity and burstiness, with 16 explicit rules:

1. Noticeable sentence length variation
2. Noticeable paragraph length variation
3. Every sentence serves a purpose (no filler)
4. Complex ideas segmented into digestible pieces
5. Sentence fragments intentionally used
6. Implied subjects or verbs (unstated elements)
7. Active voice
8. Colloquialisms and everyday expressions
9. Figurative language — metaphors, irony, hyperbole
10. Contractions
11. Anecdotes and personal perspective
12. No rhetorical questions inside answers
13. No "imagine" or "picture" invitations
14. Simple language
15. Emotional intelligence matching user context
16. Word selection from a vetted vocabulary list

### PromptWarrior — Content Humanizer Prompt

**URL:** https://www.thepromptwarrior.com/p/content-humanizer-prompt

Core rules: conversational tone, 7th-grade readability, short punchy sentences, rhetorical fragments, bullet points contextually, analogies and examples, personal anecdotes, strategic bold/italic. Avoids: "game-changing," "unlock," "master," "skyrocket," "revolutionize."

### Pangram Labs guide (our existing reference)

**URL:** https://www.pangram.com/blog/comprehensive-guide-to-spotting-ai-writing-patterns

This is a thorough resource. The word lists are substantially larger than our helper includes. Key items we reference but don't fully incorporate:

Full Pangram overused word lists (not exhaustive):

Nouns: aim, aspect, challenge, climate, community, complexity, confrontation, depth, development, diverse, dynamics, elegant, endeavor, enlightenment, exploration, facet, foster, grapple, illuminate, imperative, innovation, insight, interplay, intricate, journey, landscape, lens, manifold, meaningful, navigate, nuance, paramount, pivot, profound, quest, realm, resilience, resonance, revelation, roadmap, robust, scheme, seamless, significance, strive, symphony, tailor, tapestry, testament, timeless, toolkit, transcend, transformative, unleash, vast, versatile, vibrant, weave

Verbs: aimed, capturing, confronting, curated, deepened, delving, elevated, elucidated, embarked, embodied, embraced, emulated, endeavored, enhanced, enlightened, entwined, espoused, evoked, exacerbated, exemplified, explored, fostered, grappled, highlighted, illuminated, innovated, inspired, intertwined, navigated, pivoted, reimagined, resonated, revealed, revolutionized, showcased, strived, transcended, undermined, underpinned, underscored, unleashed, unlocked, unraveled, valued, weaving

Adjectives: authentic, commendable, complex, creative, crucial, dynamic, elusive, essential, exemplary, grand, indelible, innovative, inspirational, invaluable, meticulous, notable, nuanced, powerful, professional, significant, sustainable, valuable, whimsical

Adverbs: additionally, aptly, creatively, critically, crucially, dynamically, indelibly, insightfully, intricately, invaluably, meticulously, notably, pivotally, poignantly, powerfully, profoundly, relentlessly, seamlessly, significantly, successfully, timelessly, tirelessly, vibrantly, vividly

Additional structural tells Pangram identifies:
- Absence of specific proper nouns (generic names like "Emily" or "Sarah" appearing 60-70% of the time in AI articles)
- No personal anecdotes or unique voice
- Repetitive content especially in conclusions
- "Perfect" grammar throughout — no fragments, run-ons, or natural errors
- Consistent Oxford comma throughout
- American English spelling applied uniformly

### sh-reya's blog (our existing reference)

**URL:** https://www.sh-reya.com/blog/ai-writing/

sh-reya's piece focuses on cognitive quality rather than surface word swaps. Key signals identified:

- Empty conclusions — sentences that pretend to wrap up without adding substance ("By following these steps, we achieve better performance")
- Flat sentence rhythm — all sentences sharing similar length, creating monotony
- Subject-verb misalignment — wrong grammatical subject obscures main idea ("Readers are better guided" when the writing is the actual subject)
- Low information density — well-formed sentences conveying minimal insight
- Vagueness and lack of specificity — claims without supporting reference points
- Demonstrative pronoun overuse — heavy "this," "that," "these," "those" without clear antecedents
- Fluency masking confusion — sounds correct but explains nothing; may invent non-existent terminology

sh-reya explicitly argues that some things incorrectly flagged as AI-like are actually legitimate: deliberate repetition for clarity, signposting phrases ("essentially," "in short"), parallel grammatical structures, consistent heading patterns, topic sentences opening sections, em dashes for emphasis and flow.

This is the most useful resource for cognitive quality tells — the type our helper does not cover at all.

---

## 3. obra/superpowers — writing-skills directory

The files `skills/writing-skills/anthropic-best-practices.md` and `skills/writing-skills/CLAUDE_MD_TESTING.md` are not present on this machine. A search found only competitive analysis documents that reference superpowers as a product, not the source repository itself. These files cannot be assessed.

---

## 4. What our helper is missing

### Missing word/phrase coverage

Our helper's word list is small (around 35 words and phrases total). The community-maintained lists run to 80-120+ terms. Specific gaps:

From blader's AI vocabulary list not in ours: align with, enduring, enhance, fostering, garner, highlight, interplay, intricate, key, landscape, pivotal, showcase, underscore, valuable

From Pangram not in ours: aim, aspect, endeavor, enlightenment, exploration, facet, grapple, illuminate, manifold, navigate, nuance, paramount, quest, realm, resonance, revelation, roadmap, symphony, tailor, timeless, toolkit, transcend, unleash, vast, versatile, weave — and the full verb and adjective lists above

From sabrina.dev not in ours: embark, craft/crafting, game-changer, unlock, discover, skyrocket, abyss, revolutionize, disruptive, dive deep, unveil, elucidate, hence, harness, exciting, groundbreaking, cutting-edge, remarkable, ever-evolving, glimpse into, navigating, stark, boost, opened up, inquiries

From multiple sources: Furthermore, Moreover, Additionally as clustered transition words (we don't mention this framing)

### Missing pattern categories — entire categories absent from our helper

**Cognitive quality tells** (sh-reya, partially Aboudjem):
- Low information density — well-formed sentences conveying nothing specific
- Subject-verb misalignment — wrong grammatical subject
- Demonstrative pronoun overuse — "this," "that," "these," "those" without clear antecedents
- Empty conclusions — sentences that appear to conclude but add no content
- Fluency masking confusion — sounds right but explains nothing
- Flat sentence rhythm as a distinct, nameable problem

**Content-level patterns** (blader, Aboudjem):
- Copula avoidance ("serves as," "stands as," "boasts" replacing "is")
- Negative parallelisms ("It's not just X, it's Y")
- Synonym cycling / elegant variation (excessive synonym substitution)
- False ranges ("from X to Y" where endpoints aren't on a scale)
- Vague attributions ("experts say," "studies show," "observers note")
- Formulaic challenge/prospects sections
- Superficial -ing analyses (highlighting, underscoring, emphasizing used as gerunds)

**Communication patterns** (blader, Aboudjem, multiple):
- Chatbot artifacts ("I hope this helps," "let me know if you have questions")
- Knowledge-cutoff disclaimers ("as of my training cutoff")
- Sycophantic openers ("Great question!", "Absolutely!")
- Excessive hedging — stacked qualifiers ("could potentially possibly")

**Style/formatting patterns** (blader, multiple):
- Inline-header lists (bolded label: content, bolded label: content format)
- Title Case in headings
- Emojis as decorative AI signal
- Curly quotes
- Boldface overuse — mechanical emphasis on every noun or term
- Uniform sentence length as a named, measurable problem
- Rhetorical question-and-answer sequences in body text

**Voice dimension** (Aboudjem) — completely absent from our helper:
No guidance on choosing or maintaining a voice profile. No distinction between how the same avoidances apply differently in technical vs. casual vs. warm writing.

### Missing positive guidance

Our helper has a "Natural Technical Writing" section but it is thin. The community resources consistently emphasize:
- Burstiness as a measurable target (dramatic sentence length variation — 3-word sentences next to 40-word sentences)
- Perplexity as a target (unexpected word choices that humans naturally make)
- Sentence fragments as a legitimate human-writing tool
- Figurative language as humanizing (metaphors, irony, hyperbole)
- Personal anecdotes and first-person perspective
- Shifting tone across sections (not maintaining single tone throughout)
- Active voice as an explicit rule, not just an implicit preference
- 7th-grade readability as a practical target for accessible writing

---

## 5. Is there a community-maintained blacklist to reference?

blader/humanizer explicitly cites Wikipedia's "Signs of AI Writing" page (WikiProject AI Cleanup) as its foundation. This is the closest thing to a community-maintained canonical list — it is collaboratively updated, cites thousands of observed instances, and is the source blader derives from.

The Wikipedia page was returning 403 during this sweep, but blader's SKILL.md effectively captures it. The Wikipedia page is a better long-term reference than any single repo.

No single canonical GitHub word blacklist exists. The sabrina.dev list is the most complete single prompt-embedded list found (70+ terms). The Pangram Labs guide has the most comprehensive categorized breakdown.

---

## 6. Recommendations

### Adopt vs. reference vs. expand

**Reference blader/humanizer directly** for the 24-pattern taxonomy. It is well-maintained, cites authoritative sources, and covers our use case (Claude Code skill for technical writing). Adding a link in our helper's References section costs nothing and gives users a complete rewrite tool when they need one.

**Reference sh-reya's blog** for cognitive quality — it covers the dimension our helper misses most severely. Our current reference is there but the content isn't incorporated.

**Expand in place** for patterns that are brief enough to add directly. Candidates:
- Copula avoidance (one line)
- Negative parallelisms (one line)
- Synonym cycling (one line)
- Chatbot artifacts (one line)
- Sycophantic openers (one line)
- Knowledge-cutoff disclaimers (one line — directly relevant for Claude Code agents)
- Excessive hedging / stacked qualifiers (one line)
- Inline-header lists (one line)
- Vague attributions (one line)
- Cognitive quality section (new section, several lines)

**Do not** try to replicate the full 80-120 word lists from Pangram or sabrina.dev inside our helper. That's a reference-by-link job, not a prose document. Our helper works best as a concise guide with representative examples, not an exhaustive dictionary.

**Voice profiles** are worth considering as a lightweight addition — even a single paragraph noting that avoidances apply differently in technical vs. conversational writing would be more useful than the full Aboudjem five-profile system.

### Priority order for additions

1. Cognitive quality section (sh-reya patterns: low information density, subject-verb misalignment, demonstrative pronoun overuse, empty conclusions) — this is the dimension most absent and most useful for agents producing technical documentation
2. Chatbot artifacts, sycophantic openers, knowledge-cutoff disclaimers — directly relevant to agent-generated output
3. Copula avoidance, negative parallelisms, synonym cycling — structural language patterns that agents produce frequently
4. Expanded word list — add the highest-signal missing terms (serves as, stands as, interplay, landscape, furthermore/moreover/additionally as a cluster pattern)
5. Burstiness / perplexity as named concepts in the positive guidance section
6. Link to blader/humanizer and Pangram word lists for users who want exhaustive references

---

## Sources consulted

- https://github.com/blader/humanizer (README and SKILL.md)
- https://github.com/Aboudjem/humanizer-skill
- https://github.com/lguz/humanize-writing-skill
- https://github.com/0xeb/TheBigPromptLibrary
- https://github.com/linexjlin/GPTs (Humanizer Pro prompt)
- https://github.com/topics/humanize-text
- https://www.sabrina.dev/p/best-ai-prompt-to-humanize-ai-writing
- https://www.thepromptwarrior.com/p/content-humanizer-prompt
- https://www.pangram.com/blog/comprehensive-guide-to-spotting-ai-writing-patterns
- https://www.sh-reya.com/blog/ai-writing/
- Wikipedia: Signs of AI writing (403 during sweep; content captured via blader/humanizer's derivation)
