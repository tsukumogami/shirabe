---
name: writing-style
description: Revise prose to remove AI tells and produce natural, direct writing. Use this skill whenever: (1) the user asks to improve, humanize, clean up, or revise a draft; (2) prose output is about to be produced — PR descriptions, issue bodies, README sections, documentation, explanations, or summaries; (3) the user mentions AI-sounding writing, robotic phrasing, or wants writing to sound more human. Apply proactively when writing prose; don't wait for an explicit invocation.
---

When invoked directly with a draft: identify patterns below, revise, return the revised text. When producing prose: apply these patterns from the start rather than producing and then revising.

## The rules live in `rules.yaml`

`skills/writing-style/rules.yaml` is the single authoritative source. Read it
for the banned words, phrases, and frequency thresholds. It carries the terms
and the reason for each, grouped by category.

This file does not restate that list. It used to, and the copy drifted from
the validator's copy, which is the divergence the rule source exists to end.
`shirabe validate` reads the same file at enforcement time, so a rule added
there reaches both you and the validator with no second edit.

A repository can declare terms of art the rules must not fire on, through a
`## Prose Vocabulary:` header in its CLAUDE.md. Honor a repository's
declaration when you draft in it: shirabe declares `tier`, `journey`, and
`underscore` because those are its own vocabulary, not tells.

## What the validator catches, and what it does not

The mechanical rules are enforced before a reviewer sees the draft. Word
matches, phrase matches, and em dash density are handled; you do not need to
scan for them, and re-flagging them wastes the reader's attention.

What no matcher reaches is the `judgment_only` section of the rule source,
and it is where the value is:

- **Low information density.** Well-formed sentences that say nothing. A
  fluent, entirely vacuous document produced ten alerts under three
  off-the-shelf style packages and not one concerned the vacuity.
- **Empty conclusions.** A closing paragraph that adds no content.
- **Demonstratives with no antecedent.** "This" and "that" pointing at
  nothing nameable.
- **Attribution without a citation.** "Studies show" with no study.
- **Synonym cycling.** Repeat the word instead.
- **Forced rule of three.** Use the actual count.
- **`from X to Y` on no real scale.** Measured zero true positives across 46
  corpus hits; every one was a genuine state transition.
- **`landscape` used figuratively.** "Competitive landscape" is a term of
  art; "the landscape of modern tooling" is the tell.

## Structural patterns

| Pattern | Fix |
|---------|-----|
| "serves as", "stands as", "boasts" | Use "is/are/has" |
| "It's not just X, it's Y" | Just say Y |
| Stacked qualifiers ("could potentially possibly") | One qualifier |
| Hollow gerunds: "highlighting/underscoring/emphasizing" | Cut or make main clause |

## Formatting tells

| Tell | Fix |
|------|-----|
| Em dash overuse | Comma, parentheses, or colon. The validator measures the rate per document; a threshold breach means the whole draft, not one sentence. |
| No contractions | Use "don't", "it's", "we've" |
| Title Case Headings | Sentence case |
| Boldface overuse | Bold genuine emphasis only |
| Uniform paragraph length | Vary naturally |

## Over-formality substitutions

| Avoid | Use |
|-------|-----|
| "In order to" | "To" |
| "Due to the fact that" | "Because" |
| "At this point in time" | "Now" |
| "Prior to" / "Subsequent to" | "Before" / "After" |
| "With respect to" | "About" or "For" |
| "Has the ability to" | "Can" |

## What human writing has

- Burstiness: dramatic variation, a 3-word sentence next to a 25-word sentence is the target, not mild variation
- "And", "But", "Or" as sentence starters are fine
- Specifics over abstractions: name the file, cite the number
- Opinions: take a position; acknowledge complexity or mixed feelings
