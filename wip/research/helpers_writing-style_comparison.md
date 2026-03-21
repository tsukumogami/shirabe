# Writing Style Helper: Comparison and Assessment

## What We Have

Our helper at `helpers/writing-style.md` covers:

- **Overused word tables** by category (organizing terms, action verbs, descriptors, abstract nouns) with alternatives for the most common offenders
- **Overused phrases** — preamble hedges ("It's worth noting that"), conclusion filler ("In conclusion"), vague summaries
- **Structural patterns** — default-to-three, numbered lists for everything, "Key takeaways" sections, uniform paragraph length
- **Punctuation tells** — em dash overuse, no contractions, over-polished grammar
- **Over-formality substitutions** — "In order to" → "To", "Prior to" → "Before", etc.
- **Natural writing principles** — directness, specificity, varied sentence length, appropriate informality
- **"Burstiness" concept** — the rhythm test: uniform measured prose signals AI
- **Before/after rewrites** — two concrete examples
- **References** — Wikipedia Signs of AI writing, Pangram Labs, Sh-reya's blog

Length: ~115 lines, fits in one screen.

---

## obra/superpowers: What They Ship

Superpowers ships `skills/writing-skills/` as a **standalone, invocable skill** — not a helper included into context automatically. The directory contains:

- `SKILL.md` — a skill about writing *skills* (meta: TDD-for-process-docs), not about writing prose
- `anthropic-best-practices.md` — Anthropic's official skill-authoring guidance focused on conciseness, token efficiency, and structural conventions for SKILL.md files
- `persuasion-principles.md` — research-backed techniques (Cialdini, Meincke et al. 2025) for making discipline-enforcing instructions stick
- `examples/CLAUDE_MD_TESTING.md` — test scenarios and variants for CLAUDE.md documentation compliance
- `graphviz-conventions.dot`, `render-graphs.js`, `testing-skills-with-subagents.md` — supporting tools

**The key finding**: superpowers has no direct equivalent to our writing-style helper. Their `writing-skills` skill is about *creating skills*, not about writing prose naturally. There is no anti-AI word list, no "burstiness" guidance, no overused phrase blacklist. The superpowers `anthropic-best-practices.md` addresses conciseness and structure for skill documentation specifically, not general prose quality.

The persuasion-principles.md is adjacent — it covers how to write instructions that stick — but it's normative (how to make agents comply) rather than descriptive (how to avoid AI tells in prose output).

---

## Official Anthropic Resources

Anthropic's `anthropics/skills` repo contains 17 skills, none of which address anti-AI writing patterns:

- `internal-comms` — formats for 3P updates, newsletters, FAQs; guidance is "be clear, active voice, put important info first"
- `doc-coauthoring` — workflow for collaborative writing; anti-patterns focus on process (don't reprint whole docs, don't rush) not prose style
- `brand-guidelines` — visual identity and color specs, not prose

The `claude-plugins-official` repo has output-style plugins (`explanatory-output-style`, `learning-output-style`) that are hook-based behavior modifiers, not style guidance documents.

No official Anthropic resource covers overused AI words, phrase avoidance, or burstiness. The closest is their skill-authoring guidance: "be concise, assume Claude is smart, don't explain what's obvious."

---

## What the Referenced Sources Actually Say

### Wikipedia: Signs of AI writing
The page returned 403. However, the Pangram Labs source (which we successfully fetched) and our existing helper both derive from this reference. Based on what Pangram published, the Wikipedia article is likely the primary community-maintained enumeration of AI tells.

### Pangram Labs
Successfully fetched. Their enumeration substantially exceeds ours:

**Nouns we don't cover**: aim, aspect, challenge, community, complexity, component, depth, dynamics, facet, illuminate, interplay, landscape, nuance, paramount, pivot, realm, symphony, weave

**Problematic verbs we don't cover**: elevated, elucidated, embodied, embraced, endeavored, enhanced, enlightened, fostered, grappled, illuminated, inspired, navigated, pivoted, revolutionized, showcased, strived, transcended, unleashed

**Adjectives we don't cover**: authentic, commendable, complex, crucial, dynamic, invaluable, meticulous, nuanced, powerful, significant, sustainable, valuable

**Adverbs we don't cover**: additionally, aptly, crucially, dynamically, insightfully, meticulously, notably, profoundly, seamlessly, significantly, vibrantly

**Structural patterns Pangram identifies that we cover**: em dash overuse, no contractions, uniform paragraph lengths, avoidance of semicolons and parentheses, conclusions beginning "Overall" or "In summary"

**Structural patterns Pangram identifies that we don't cover**:
- Avoidance of sentences starting "And" or "But" (we mention using these, but don't flag their absence as a tell)
- Generic proper nouns (defaulting to "most common" names; "Emily or Sarah" for character names)
- American English spelling throughout
- Consistent Oxford comma usage as a tell
- No personal experience or reflection
- Conclusions that repeat the prompt

### Sh-reya's blog
Successfully fetched. Covers different ground from Pangram — more about cognitive quality than surface tells:

- Empty conclusions that summarize rather than add substance
- Excessive bullet points for connected ideas (we cover this)
- Wrong subject selection (passive/impersonal constructions)
- Low information density — well-formed but vague statements
- Vague demonstrative pronouns without clear antecedents ("this", "that", "these")
- Undefined jargon and fluency without understanding

Also notes patterns that are *fine*: intentional repetition, signposting phrases with substance, em dashes for rhythm, predictable headings.

The sh-reya piece is less of a word list and more of a *cognitive quality* checklist. It's complementary to rather than overlapping with our helper.

---

## Industry Resources

Direct URL access was largely blocked (403s, 404s, Reddit restrictions). The Pangram Labs source, which we fully fetched, represents the most comprehensive publicly-available enumeration. Google's Developer Style Guide provided useful confirmation of the "utilize → use" and "leverage → use" patterns, plus additional vague modifier patterns ("easy/easily", "currently", "a number of", "various") that belong in a complete list.

The academic detection literature (Raidar, etc.) focuses on statistical methods, not actionable word lists for practitioners.

---

## Gap Analysis: What We're Missing

### Words and phrases not in our helper

**Verbs** (high-signal AI tells from Pangram):
- fostered, grappled, navigated, showcased, revolutionized, transcended, unleashed, endeavored, elucidated

**Adjectives**:
- meticulous/meticulously (very common AI pattern), invaluable, crucial, dynamic, nuanced (ironic given its meaning), seamless/seamlessly, significant/significantly

**Adverbs**:
- additionally (extremely common as a paragraph opener), notably, ultimately (not in our list)

**Transition structures**:
- "Furthermore," / "Moreover," as paragraph openers
- "It is important to note that..." (we have "It's worth noting" but not this variant)
- "It should be noted that..."
- "One key aspect is..."
- "As previously mentioned..."
- "At its core, this..."

### Structural gaps

1. **Absence of "And/But" sentence starters** as a positive tell for natural writing — we say to use them, but don't explain their diagnostic value
2. **Generic proper noun defaulting** — when writing fiction or examples, AI picks the most statistically common name/place
3. **Conclusions that restate the prompt** — a failure mode we don't address
4. **Semicolons and parentheses as naturalness markers** — humans use these; AI avoids them
5. **Personal experience and reflection** — no guidance on how to inject specificity that reads as lived rather than synthesized
6. **Vague demonstrative pronouns** — the sh-reya "this/that without clear antecedent" pattern is actionable and absent

### Conceptual gaps

1. **Information density** — the idea that AI produces fluent but low-information sentences is not explicitly covered. We say "be specific" but don't frame low information density as a tell.
2. **Subject selection** — choosing the right grammatical subject (active, specific agent) vs. impersonal constructions ("It is recommended that...")
3. **The difference between surface tells and cognitive tells** — our helper covers mostly surface patterns; sh-reya's cognitive quality checklist (empty conclusions, vague references, fluency without understanding) is a distinct and important dimension

---

## Helper vs. Skill: Structural Question

Our helpers are @-included into skill context automatically. Superpowers ships writing-skills as an invocable skill — loaded only when relevant.

**Arguments for keeping as a helper (auto-included):**
- Writing style guidance is relevant to *every* output, not just specific tasks
- Surface tells (word avoidance) need to be active constraints, not something to look up
- The guidance is short enough (~115 lines) that token cost is low
- Auto-inclusion means it can't be forgotten

**Arguments for making it an invocable skill:**
- A more comprehensive version (covering all the gaps above) would be too long to include in every context
- Some tasks (code edits, config changes) don't produce prose that needs style guidance
- Skill-based delivery enables better "when to use" scoping

**Hybrid approach** (likely right answer):
- Keep the current helper with the core word avoidance and structural patterns — stays auto-included
- Create a supplementary skill for deeper rewriting tasks that covers cognitive quality (sh-reya patterns), the full Pangram word list, and before/after rewrite exercises

This mirrors how superpowers separates the persuasion-principles.md (deep reference) from inline guidance in individual skills.

---

## Verdict

**How does our helper compare?**

For its size and scope, our helper is well-constructed. The categories are right (words, phrases, structure, punctuation, formality), the examples are concrete, and the burstiness concept is the correct framing. It's better than anything in superpowers or official Anthropic resources for anti-AI prose guidance, because those don't address this dimension at all.

However, it covers roughly 30-40% of the word surface area documented by Pangram Labs, and misses the cognitive quality dimension documented by sh-reya.

**Specific improvements needed:**

1. Expand the verb list with high-frequency AI verbs: fostered, navigated, showcased, endeavored, elucidated, unleashed, grappled, transcended
2. Add the adverb problem: "additionally," "notably," "ultimately," "seamlessly," "meticulously" as paragraph-level tells
3. Add the cognitive quality section from sh-reya: information density, vague demonstratives, empty conclusions, subject selection
4. Clarify that sentences starting "And" or "But" are *positive signals* of natural rhythm, not just permitted
5. Add "Furthermore/Moreover/Additionally" as preamble phrases to avoid alongside the existing list
6. Add a note on semicolons and parentheses as naturalness markers

**Should it stay as a helper, become a skill, or be replaced/supplemented?**

Keep it as a helper — auto-inclusion is right for word avoidance guidance. Supplement it with an invocable skill for deeper revision work that carries the full Pangram word inventory and the cognitive quality checklist. Don't replace it with an external resource; the referenced sources (Pangram, sh-reya) are good but not maintained as versioned documents and can go offline.

The helper should be updated in place with the gap items above. The invocable skill is new work.
