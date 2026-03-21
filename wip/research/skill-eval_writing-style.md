# Skill Evaluation: writing-style

Evaluated against: skill-creator quality framework
Date: 2026-03-17
Skill path: `skills/writing-style/SKILL.md`

---

## Current State Assessment

The skill is lean — 72 lines of body, 454 words — and structurally sound. The table format is appropriate for word/phrase lists because scanning is the primary use case; prose explanations would cost tokens without adding value. The content covers real patterns from blader/humanizer and the sh-reya cognitive quality research. Progressive disclosure is not a concern at this size.

Two problems are significant enough to affect behavior:

1. The description does not tell Claude when to trigger. It describes what the skill does but gives no "when" clause and no pushiness. A skill that should auto-trigger whenever prose is produced will systematically under-trigger with this description.

2. Content gaps exist. The skill is designed to be "all patterns from blader/humanizer + cognitive quality tells," but several named blader categories are absent or covered only partially.

One structural issue is minor but worth fixing: the body contains no invocation guidance. A user typing `/writing-style` gets no instruction on what to do with a draft or how to pass text in.

---

## 1. Description Quality Analysis

### Current description

```
Apply when writing or editing prose. Catches AI tells and enforces natural, direct writing.
```

### Problems

**Too short and not pushy enough.** The skill-creator framework explicitly warns that Claude has a tendency to undertrigger skills. The fix is to make descriptions "a little bit pushy" — list specific contexts and tell Claude to apply the skill even when the user doesn't name it explicitly.

**No auto-trigger contexts.** The description says "apply when writing or editing prose" but gives Claude no signal for when that applies. This skill should fire when Claude is about to produce any substantive prose output — a PR description, an issue body, a doc comment, a README section, a commit message, an explanation in a response. None of those contexts are mentioned.

**No user-invocation phrasing.** Someone typing "humanize this draft" or "make this sound less AI-generated" or "clean up my writing" should reliably trigger this skill. The description doesn't cover those phrasings.

**Passive framing.** "Catches AI tells" describes what the skill notices, not what it does. Stronger: "Revise prose to remove AI tells and produce natural, direct writing."

### Proposed improved description

```
Revise prose to remove AI tells and produce natural, direct writing. Use this skill whenever: (1) the user asks to improve, humanize, clean up, or revise a draft; (2) the user is about to produce prose output — PR descriptions, issue bodies, README sections, commit messages, documentation, explanations, summaries, or any response longer than a sentence; (3) the user mentions AI-sounding writing, robotic phrasing, or writing that needs to sound more human. Apply proactively when writing prose — don't wait for the user to explicitly invoke it.
```

This version:
- Names the action clearly ("Revise prose")
- Covers user-invocation contexts with concrete phrasings
- Covers auto-trigger contexts with specific output types
- Ends with a pushiness instruction that combats undertriggering
- Is ~85 words, within the ~100-word metadata budget

---

## 2. Body Content Gaps

Cross-referencing against blader/humanizer's 24 patterns and the industry sweep research (`helpers_writing-style_industry-sweep.md`).

### Present and correct

The skill covers these blader/humanizer patterns well:

- AI vocabulary: overused words (partial list — see gaps below)
- Em dash overuse (formatting tells table)
- No contractions (formatting tells table)
- Title Case headings (formatting tells table)
- Boldface overuse (formatting tells table)
- Filler phrases / over-formality (over-formality substitutions table)
- Chatbot artifacts (phrases table — "I hope this helps", "Great question!", "Absolutely!", "Certainly!")
- Knowledge-cutoff disclaimers (phrases table)
- Vague attributions (phrases table)
- Excessive hedging / stacked qualifiers (structural patterns table)
- Hollow gerunds / superficial -ing analyses (structural patterns table)
- Rule of three / forced triads (structural patterns table)
- Cognitive tells section covers: low information density, empty conclusions, vague demonstrative pronouns

### Missing: blader/humanizer patterns not in the skill

**Copula avoidance** — blader calls this one of the most distinctive AI tells. Replacing "is/are" with "serves as," "stands as," "boasts" signals AI strongly. Currently absent.

Fix: add to the structural patterns table:
```
| "serves as", "stands as", "boasts" | Use "is/are/has" |
```
This is already present in the structural patterns table. No action needed here. (Confirmed by re-reading line 31.)

**Negative parallelisms** — "It's not just X, it's Y" construction. Currently absent.

Fix: add to structural patterns table:
```
| "It's not just X, it's Y" | Just say Y |
```

**Synonym cycling / elegant variation** — excessive synonym substitution to avoid apparent word repetition. Currently absent.

Fix: add to structural patterns table:
```
| Synonym cycling | Repeat the word |
```
This is already in the structural patterns table (line 33). No action needed.

**False ranges** — "from X to Y" where X and Y are not on a meaningful scale. Currently absent.

Fix: add to structural patterns table:
```
| "from X to Y" on no real scale | Name items directly |
```
This is already present (line 34). No action needed.

**Significance inflation** — grandiose framing using "stands as," "testament," "pivotal," "reflects broader," "evolving landscape" as a named category. Partially covered by the word table ("pivotal," "paramount") but not as a pattern.

**Chatbot sycophancy** — The phrases table has "Great question!", "Absolutely!", "Certainly!" but missing "Of course!" and "Sure!" which are similarly common Claude artifacts.

Fix: extend the chatbot artifacts line:
```
- "I hope this helps", "Great question!", "Absolutely!", "Certainly!", "Of course!", "Sure!" — chatbot artifacts
```

**Promotional language as a category** — "boasts," "breathtaking," "vibrant" as promotional descriptors. "Vibrant" is in the descriptors table; "boasts" is in structural patterns. "Breathtaking" and promotional hyperbole more broadly are absent.

**Formulaic challenge/prospects sections** — AI frequently adds "Despite these challenges..." / "The future looks bright" sections. Not covered.

### Missing: word list gaps

The current word table is lean compared to blader/humanizer's vocabulary list. Notable absences:

From blader's AI vocabulary (not in skill): `align with`, `enduring`, `enhance`, `fostering`, `garner`, `highlight`, `interplay`, `key` (as filler adjective), `landscape`, `pivotal`, `showcase`, `underscore`, `valuable`

Most of these appear in the verb and descriptor categories but not the specific terms. `landscape`, `interplay`, `highlight`, `underscore`, `showcase`, and `fostering` are particularly high-signal and should be added.

The adverb openers row is strong but missing: `Ultimately` (present — confirmed), `Crucially`, `Importantly`.

### Missing: positive guidance is thin

The "What human writing has" section is good but short. A sentence about sentence fragments and parenthetical asides as naturalness markers would add value. The skill says "Burstiness: short and long sentences mixed" but doesn't make clear that dramatic variation — 3-word sentences adjacent to 25-word sentences — is the target, not mild variation.

### Missing: invocation instructions

The body has no user-facing instructions. When someone types `/writing-style` with a draft, they get a reference document but no instruction on what to do with it. A minimal preamble would fix this:

```
When invoked directly: read the user's draft, identify patterns from the tables below, then revise and return the revised text. If no draft is provided, ask for one.

When producing prose output: apply these patterns as you write — don't produce a draft and then revise; write correctly from the start.
```

---

## 3. Trigger Evaluation Set

### Should trigger (8 prompts)

These prompts represent cases where the skill should fire. They test user-invocation phrasing, auto-trigger contexts, and near-misses where another skill might compete.

1. `can you look at this pr description i wrote? it sounds kind of robotic and i want it to sound more like a real person wrote it` — direct user revision request, casual phrasing, no skill named

2. `write a README section explaining what tsuku's recipe system does, targeting developers who've never seen the project` — prose generation context; auto-trigger applies even though user doesn't mention style

3. `/writing-style` followed by a multi-paragraph issue body draft — explicit invocation with draft

4. `this paragraph i wrote for the issue description feels too AI-generated, can you help me clean it up: [paragraph]` — user names the problem (AI-generated) without naming the skill

5. `i need to write an explanation of why we chose action-based installation over monolithic installers for the architecture doc. can you draft that?` — prose generation; auto-trigger applies

6. `humanize this: [pasted text with AI tells]` — user uses "humanize" keyword

7. `the commit message i wrote sounds weirdly formal. something like: "This commit implements the changes necessary to facilitate the extraction and installation of binary artifacts." help?` — specific over-formality case; user pastes problematic text

8. `can you review this doc comment for naturalness? i want to make sure it doesn't sound like it was written by an AI` — explicit "naturalness" / "AI" framing

### Should NOT trigger (7 prompts)

These are the hard cases — prompts that share keywords or contexts with the skill but should not trigger it.

1. `write a python function that validates whether a given string contains AI-generated watermarks` — "AI" appears but this is code generation, not prose revision; writing-style skill is irrelevant

2. `i'm seeing a grammar error on line 47 of main.go — 'err :=' is throwing a compile error` — bug fix request; no prose output context

3. `how do i configure the recipe cache directory in tsuku?` — factual question; response will be short and informational, not prose requiring style enforcement

4. `rewrite this function so it handles the nil case` — code rewrite, not prose rewrite; "rewrite" keyword might seem like a near-miss

5. `can you summarize the changes in this PR for the merge commit message? here's the diff: [diff]` — short output (commit messages are 1-2 lines); the writing-style skill adds overhead without value for single-sentence outputs; however, this is a genuine edge case — commit messages do appear in the skill's description as a target context

6. `my coworker's code uses leverage() as a function name. is that a bad naming choice?` — "leverage" appears but the question is about code naming, not prose style

7. `lint this markdown file for broken links and heading hierarchy` — formatting/linting task; not prose quality

Note on prompt 5: the proposed improved description includes "commit messages" as a context. That may cause overtriggering for trivially short commits. Consider removing "commit messages" from the description or scoping it to "longer commit message bodies."

---

## 4. Specific Proposed Edits

### Edit 1: Replace description (highest priority)

Current:
```yaml
description: Apply when writing or editing prose. Catches AI tells and enforces natural, direct writing.
```

Proposed:
```yaml
description: Revise prose to remove AI tells and produce natural, direct writing. Use this skill whenever: (1) the user asks to improve, humanize, clean up, or revise a draft; (2) prose output is about to be produced — PR descriptions, issue bodies, README sections, documentation, explanations, or summaries; (3) the user mentions AI-sounding writing, robotic phrasing, or wants writing to sound more human. Apply proactively when writing prose; don't wait for an explicit invocation.
```

### Edit 2: Add invocation instructions before the tables

After the frontmatter closing `---`, add:

```markdown
When invoked directly with a draft: identify patterns below, revise, return the revised text. When producing prose: apply these patterns from the start rather than producing and then revising.
```

One sentence for each use mode. Keeps token cost low.

### Edit 3: Add missing patterns to structural patterns table

Current structural patterns table:

```
| Pattern | Fix |
|---------|-----|
| "serves as", "stands as", "boasts" | Use "is/are/has" |
| "It's not just X, it's Y" | Just say Y |
| Synonym cycling | Repeat the word |
| "from X to Y" on no real scale | Name items directly |
| Stacked qualifiers ("could potentially possibly") | One qualifier |
| Hollow gerunds: "highlighting/underscoring/emphasizing" | Cut or make main clause |
| Forced rule of three | Use the actual count |
```

Wait — re-reading the skill, most of these are already present. The confirmed gap is "It's not just X, it's Y" (negative parallelism). It is NOT in the current table.

Add one row to the structural patterns table:
```
| "It's not just X, it's Y" | Just say Y |
```

### Edit 4: Expand word list

The verbs row currently reads:
```
| Verbs | leverage, utilize, facilitate, delve, foster, navigate, showcase, grapple, transcend, elucidate, underscore, highlight |
```

Add missing high-signal terms: `align with`, `enhance`, `garner`, `underscore` (already present), `interplay` (should move to abstract nouns or add to descriptors).

Proposed updated verbs row:
```
| Verbs | leverage, utilize, facilitate, delve, foster, navigate, showcase, grapple, transcend, elucidate, underscore, highlight, enhance, align with, garner |
```

Proposed addition to abstract nouns row:
```
| Abstract nouns | journey, narrative, tapestry, testament, resilience, landscape (fig.), interplay, realm |
```

### Edit 5: Extend chatbot artifacts line

Current:
```
- "I hope this helps", "Great question!", "Absolutely!", "Certainly!" — chatbot artifacts
```

Proposed:
```
- "I hope this helps", "Great question!", "Absolutely!", "Certainly!", "Of course!", "Sure!" — chatbot artifacts
```

### Edit 6: Clarify burstiness target in positive guidance

Current:
```
- Burstiness: short and long sentences mixed; paragraphs vary in length
```

Proposed:
```
- Burstiness: dramatic variation — a 3-word sentence next to a 25-word sentence is the target, not mild variation
```

---

## 5. Usability as a Reference for Other Skills

The skill's role as passive guidance loaded by other skills is its most distinctive use case. Skills that say "follow the writing-style skill" will load this SKILL.md into context. For that to work, the content must function as a constraint list, not an interactive workflow.

The current table format works well here. Tables are scannable in context and create natural constraint boundaries. The section structure (words → phrases → structural patterns → formatting tells → over-formality → cognitive tells → positive guidance) is logical and easy to reference.

One gap: when loaded as a reference by another skill, the invocation instructions ("when invoked directly with a draft...") would be noise. The skill doesn't need to handle this — instructions at the top of a skill are understood to be for direct invocation. But if it becomes a concern, the invocation instructions could be scoped with a heading like "## Direct invocation" to make them skippable.

The cognitive tells section is the strongest part for reference use. "Low information density," "empty conclusions," and the demonstrative pronoun rule are actionable in a way that pure word lists are not. Other skills that load this will benefit most from those rules.

Overall, the skill works as a reference. The proposed edits don't compromise that usability — they add rows to existing tables and a two-sentence preamble that adds context for both modes of use.

---

## Summary

| Issue | Severity | Action |
|-------|----------|--------|
| Description too short and passive | High | Edit 1: replace with pushy, context-rich description |
| No invocation instructions | Medium | Edit 2: add two-sentence preamble |
| Negative parallelism pattern missing | Medium | Edit 3: add row to structural patterns table |
| Chatbot artifacts incomplete | Low | Edit 5: add "Of course!", "Sure!" |
| Word list missing high-signal terms | Low | Edit 4: add enhance, align with, garner, realm |
| Burstiness guidance too vague | Low | Edit 6: add specific sentence-length target |
