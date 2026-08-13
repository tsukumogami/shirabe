# Phase 4 Verdict: Content Quality (recheck)

VERDICT: PASS

All four required changes landed, and three of them landed cleanly rather
than cosmetically. The fourth (the Journey 2 / OUT-list collision) resolves
the ambiguity I named, but its closing clause is looser than it needs to be
and is worth trimming. Nothing that previously passed broke. Every number in
the current text traces to the findings or the measurement-method file.

Two things I found that are not BRIEF defects but should not go unrecorded:
one unsupported qualitative claim carried over from the earlier draft, and an
arithmetic inconsistency inside the sources themselves. Both are written up
below under "Notes for the author."

## Required-change verification

**1. tier count: LANDED.** The BRIEF no longer says 147. Current text: "in a
run over `docs/`, `tier` accounts for 128 of 156 alerts and is the Tier 1-4
decision-complexity vocabulary." The findings carry 156 alerts with 128 of
them `tier`, from the orchestrator's custom-style run over `docs/` (145
files, 463k words), and the measurement-method file's word-frequency table
resolves it precisely: `tier` 82 plus `Tier` 46 equals exactly 128, and the
file states "128 of 156 (82%) are `tier` in its Tier 1-4 sense."

Worth noting because it cuts the author's way: the findings' parenthetical
attributes the 128 to `tier`/`Tier`/`tiered`, but the method file's table
makes that 132 (adding `tiered` 3 and `Tiered` 1). The BRIEF's phrasing,
`tier` alone at 128, is the one the measurement actually supports. It is more
accurate than the source sentence it draws from.

The figure is scoped to its run ("in a run over `docs/`"). The `journey`
figure now carries no run attribution at all, which is the right call given
the findings source it from a separate, wider run. One small residue: the
scope clause is front-loaded on a compound sentence, so "in a run over
`docs/`" can be read as distributing across both conjuncts. That is the
structure I suggested in my own prior verdict, so I am not going to fail it
now; if the author wants it airtight, moving the clause inside the first
conjunct ("`tier` accounts for 128 of 156 alerts in a `docs/` run") removes
the reading entirely.

**2. two-true-positives re-scope: LANDED.** The merged claim is split. Current
text: "The phrase apparatus that takes up most of the rulebook produces
roughly two true positives across 554,000 words of this workspace's prose,
and raw word-rule precision measures 1.7%, rising to about 16% once the
domain terms are excluded."

Both halves check out against the findings: "the entire class-A phrase
apparatus - 15 of 16 rules ... produces roughly two true alerts" across
554,000 words, and "Raw precision on the word rules measures 1.7%; after
excluding the two domain terms and the PRD that quotes the rulebook, about
16% on 31 alerts." Neither is now overstated in the other direction - the
phrase figure is no longer carrying the word rules' true positives, and the
word-rule figure is presented at both its raw and adjusted values rather than
only the flattering one.

One imprecision, again in wording I suggested: the findings reach 16% by
excluding the two domain terms *and* the PRD that quotes the rulebook. The
BRIEF credits the lift to the domain terms alone, which makes
domain-vocabulary suppression look marginally more productive than the
measurement showed. Small enough to leave, and the fix is three words: "once
the domain terms and the rulebook-quoting PRD are excluded."

**3. em dash scoping: LANDED.** Current text: "Em dashes run 3,195 in `docs/`
and 1,222 in `skills/`. In `docs/` that is 7.84 per thousand words, with 72%
of files above 3 per thousand and the worst at 28.5; `skills/` runs a
comparable 7.59." The sentence break does the work - all three trailing
figures now sit inside a sentence that opens "In `docs/`", so none of them
reads as a claim about both trees.

The added 7.59 for `skills/` is supported: the findings state "7.84 and 7.59
per thousand words" against the two trees in that order. I re-measured the
raw counts myself and both reproduce exactly (3,195 in `docs/`, 1,222 in
`skills/`, and `skills/` at 211 files / 197,538 words). See the notes below
for a problem with the *rates* that belongs to the sources, not the BRIEF.

**4. Journey 2 / OUT collision: LANDED WITH ISSUES.** The author took the
first option and the collision is gone. The OUT item now reads: "...whatever
checking this feature settles on must report correct line numbers and skip
code fences, inline code, and URLs by construction, and that property is IN
scope. Fixing today's FC10 so that it has those properties is not, and the
two stop being the same question only if FC10 is replaced rather than
extended, which Open Question 2 leaves open."

The test I set was whether a downstream PRD author can now tell which is
which. They can. The property is declared IN unconditionally and in the
positive voice, so it goes in the PRD as a requirement. The OUT half is
scoped to framing - "as defects of that check", "each is independently
fileable" - so it governs whether a separate bug ticket exists, not whether
the requirement is written. The three defects are all accurately described
against the findings, including the third (`check_claude_md_conventions`
unreachable because `detect_format` never routes CLAUDE.md to it), which the
method file backs with an explicit negative test.

The issue is the closing clause. Taken literally, "the two stop being the
same question only if FC10 is replaced rather than extended" says that in the
extend branch they *are* the same question - and the sentence has just
declared one of them IN and the other OUT. Read strictly, that branch
contains a contradiction. It does not restore the original ambiguity, because
the unconditional IN-scope declaration survives either branch and the PRD
author's job does not change. But the clause spends a sentence re-opening
something the two preceding sentences closed, and it introduces a
demonstrative ("the two") that a cold reader has to reconstruct. Cutting from
"and the two stop being" through the end leaves the boundary intact and
sharper. Recommended, not required.

## Regression check

Nothing previously passing broke.

**Problem Statement** still states a problem and still does not smuggle the
tool. FC10 is now named on first mention - "a seven-word constant behind the
validator's FC10 check (`crates/shirabe-validate/src/checks.rs:2551`)" - and
that is identification, not mechanism-selection. FC10 appears in the section
only as one of the four existing copies and as a description of what today's
coverage misses. The section never proposes extending it, and never proposes
anything else either. The Status section still carries the tool-neutrality
disclosure, and the disclosure did not migrate into the problem framing.

**Open Question 1** is now "Must an adopter repo be able to read the single
rule source without installing shirabe? The answer bounds where that source
can live, and the PRD can settle the requirement even though the location is
a DESIGN choice." That is the requirement-level question, not the hosting
question, so it is PRD-answerable. It still genuinely defers: the BRIEF does
not need the answer to be complete, and the second sentence names why the
question sits at PRD altitude rather than DESIGN. The rephrase also improved
the section's internal consistency, since the BRIEF elsewhere excludes
mechanism choice from its own scope.

**Status section** re-punctuation preserved the meaning. "The answer might be
an external linter, a widened native check, or a mix; that choice is a DESIGN
decision" carries the same three alternatives and the same altitude
assignment as the prior single-sentence form.

**Journey 2** re-punctuation likewise. "The phase gets accurate findings
(right line, prose only)" is the prior "right line and prose only" with the
same two properties, now parenthetical. No meaning changed. The journey still
names its trigger (the artifact landing on disk) and still states an outcome
shape rather than a mechanism.

The four journeys remain distinct on entry point, the outcome section remains
outcome-shaped, and the scope lists are unchanged apart from the OUT item
under item 4.

## Factual grounding (full re-run)

Verbatim in the findings:

- **Four rulebook copies plus a fifth dangling pointer** - findings table
  lists exactly four locations; the dangling
  `.claude/helpers/writing-style.md` pointer is in the paragraph below it.
- **~60 banned words, plus phrases, structural patterns, formatting tells,
  substitutions, four cognitive tells** - findings table row: "~60 words, 7
  phrases, 7 structural, 5 formatting, 6 substitutions, 4 cognitive."
- **Seven-word constant at `crates/shirabe-validate/src/checks.rs:2551`** -
  verbatim, path and line.
- **Five-word CLAUDE.md quick reference; five-word BRIEF jury instruction** -
  findings table, "5 entries" for each.
- **The design required reading the list at validate time; the code
  hardcodes it** - findings, `DESIGN-shirabe-pattern-v1-ergonomics.md:227`.
- **Eight artifact prefixes in `detect_format`** - findings enumerate
  `COMP-`, `DESIGN-`, `PRD-`, `VISION-`, `ROADMAP-`, `PLAN-`, `STRATEGY-`,
  `BRIEF-`. Eight.
- **211 files / 197,538 words under `skills/`** - verbatim, and I
  re-measured both: 211 and 197,538 exactly.
- **554,000 words** - verbatim.
- **Roughly two true positives, phrase apparatus** - verbatim.
- **1.7% raw word-rule precision; about 16% adjusted** - verbatim.
- **128 of 156 alerts, `docs/` run** - verbatim in findings, and resolved to
  82 + 46 in the method file's frequency table.
- **112 `journey` hits; `## User Journeys` a required section heading** -
  verbatim, confirmed in the method file against
  `docs/briefs/BRIEF-execute-skill.md`.
- **3,195 em dashes in `docs/`, 1,222 in `skills/`** - verbatim, and I
  re-ran both greps: 3195 and 1222.
- **7.84 and 7.59 per thousand, 72% of `docs/` files above 3/1000, worst at
  28.5** - all four verbatim in the findings. See the note below.
- **Ten alerts on the vacuous document under three style packages, none
  about the vacuity** - verbatim in both findings and method file; the three
  packages are write-good, proselint, Microsoft.
- **Bold density and sentence-length uniformity as same-shape defects** -
  findings name both (bold density 10.9 runs/1000, burstiness via a `script`
  rule). The BRIEF names them without citing figures.

Derived rather than quoted, and correct:

- **"Three alternatives genuinely open"** - the findings' candidate table
  lists six shapes, three marked reject or rules-itself-out, leaving three
  viable: a prose check in `shirabe validate`, a `PostToolUse` hook, and a
  standalone CI job. Three.
- **"A drafting model reliably avoids the words already on the seven-word
  list"** - the author took my prior note and narrowed this from "leverage"
  to the list. The method file's frequency table supports it: across 463k
  words of `docs/`, the six non-`tier` list words total 22 hits (robust 7,
  leverage 5, comprehensive 4, holistic 3, facilitate 3), about 0.05 per
  thousand words.

Verified independently, outside both sources:

- **koto, niwa, and tsuku each call `validate-docs.yml` pinned at `@main`** -
  re-confirmed all three workflow files carry
  `uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@main`.

No number in the current BRIEF is untraceable, and no number is presented at
a wider scope than the sources measured it.

## Notes for the author

Neither of these blocks the BRIEF. Both are worth fixing.

**The em dash per-thousand rates do not reproduce from the method file's
stated denominator.** The method file says per-thousand rates use `find <dir>
-name "*.md" -exec cat {} + | wc -w` as the denominator, and gives `docs/` =
463,440 words. That arithmetic yields 3,195 / 463,440 = 6.89 per thousand,
not 7.84. I re-ran the denominator myself and got 465,018 words across 146
files, giving 6.87. The `skills/` figure is further off: 1,222 / 197,538 =
6.19, against the 7.59 the findings report.

The likely explanation is benign - `wc -w` counts table pipes, rule
separators, and fence markers as words, inflating the denominator, so a
prose-only or Vale-derived word count would push both rates up, which is the
direction needed. But the method file exists precisely so the DESIGN can
re-run these rather than trust a transcript, and as written it does not
reproduce its own headline numbers. The fix belongs in the method file: name
the counter that actually produced 7.84 and 7.59. The BRIEF cites the
findings faithfully and its argument is unaffected either way, since the
load-bearing claim is the 72%-of-files distribution, not the mean.

**"The phrase apparatus that takes up most of the rulebook" is not
supported.** In `skills/writing-style/SKILL.md` the phrase section is 7
bullets of 7 sections, roughly 9 of 66 content lines, against a word table of
about 47 entries. In the findings' own classification the class-A phrase
rules are 15 of 38, not a majority. The clause is decorative and the argument
does not need it - the sentence already carries the word-rule precision
figure right after, which covers the rest of the rulebook. "The phrase
apparatus" alone would be accurate.
