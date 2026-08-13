# Phase 4 Verdict: Reframe Review

VERDICT: FAIL

The reframe worked. The subject is now shirabe, adopters are first-class, and
the measurement source is labeled instead of hidden. The three-copies count is
correct and I could not find a fourth inside the repo. Three defects block:
one wrong count, one unsupported majority claim in the frontmatter that the
body does not make, and one unsupported superlative. All three are one-line
edits.

## Per-criterion

### 1. Subject correctness: FAIL

The reframe is substantially right. "shirabe governs prose on two surfaces",
"in shirabe's own repo that leaves...", "the same gate applies in any adopter
repo", "shirabe's `tier` and `journey` are the first consumers of that
capability, not special cases of it" -- all correctly scoped. Adopters appear
as beneficiaries with their own journey, not as an afterthought. The
measurement source is labeled at the point of use ("Measured on shirabe's own
corpus"). No sentence silently assumes the reviewer's deployment.

Two claims exceed what the doc can support.

**(a) An unsupported superlative.** Problem Statement, line 65:

> Measured on shirabe's own corpus, which is the largest body of
> shirabe-authored prose available and so the fairest test case this repo can
> run

"the largest body of shirabe-authored prose available" is a claim about all
shirabe-authored prose anywhere, and neither source measures anything outside
shirabe. Counter-evidence is one command away: `tsuku/docs/` alone is 666,310
words against shirabe's 465,480 in `docs/` and 663,018 across `docs/` +
`skills/`. Whether tsuku's corpus counts as shirabe-authored is genuinely
undetermined (much of `tsuku/docs/designs/` predates the shirabe artifact
formats), but that is the point: the BRIEF asserts a superlative it did not
test and cannot support from either source file. The clause that follows --
"the fairest test case this repo can run" -- is defensible and does the actual
justifying work on its own.

**(b) A majority claim the body does not make.** Frontmatter `problem`, lines
6-7: "cannot see the files where most agent-authored prose lives". FC10 sees
442,043 words of prefix-matched files under `docs/`. It cannot see 197,538
words under `skills/`, roughly 23,400 words of unprefixed `docs/` files, plus
CLAUDE.md / AGENTS.md / README.md. The unchecked surface is about a third of
shirabe's own prose, not most of it. The body states the correct and stronger
argument -- the unchecked prose "is exactly the prose that instructs every
future agent run" -- which is about leverage, not volume. The frontmatter
traded that for a volume claim that is false. See also criterion 5.

### 2. Three-copies claim: PASS

Exactly three restatements inside shirabe. Verified each:

1. `skills/writing-style/SKILL.md` -- the canonical rulebook. Five word tables,
   7 phrase bullets, 7 structural rows, 5 formatting rows, 6 over-formality
   substitutions, 4 cognitive tells.
2. `crates/shirabe-validate/src/checks.rs:2551` -- `const FC10_BANNED_WORDS`,
   exactly seven entries (`tier`, `tiered`, `robust`, `leverage`,
   `comprehensive`, `holistic`, `facilitate`). Line number in the BRIEF is
   exact. The doc comment above it (line 2538) even admits the divergence the
   BRIEF describes: "Reading the canonical list from disk at validate-time was
   considered ... but ... this constant is the authoritative compile-time
   copy."
3. `skills/brief/references/phases/phase-4-validate.md:244-246` -- item 8,
   five entries: "tier/tiered", "robust", "leverage",
   "comprehensive/holistic", "facilitate".

Places I checked and found no fourth:

- `CLAUDE.md` (shirabe repo root) -- confirmed, no writing-style section. Only
  `Conventions` lines 162-163: "No emojis in code or committed documentation"
  and "Never add AI attribution or co-author lines". Those two are org
  conventions, not the writing-style rulebook, and they fall outside the
  rulebook the BRIEF enumerates. The alleged fourth copy and the dangling
  `.claude/helpers/writing-style.md` pointer are indeed outside shirabe; the
  source findings file lists them as "workspace `CLAUDE.md`", confirming the
  reviewer's diagnosis.
- `AGENTS.md` -- no hits for style, prose, word, or emoji.
- `README.md` -- only line 56, a pointer ("`/writing-style` runs
  automatically"), no rule content.
- All other skills' phase files. Grepped every `skills/*/references/phases/`
  for banned-word tokens, "without preamble", "no emojis", "AI attribution",
  "Adverb opener", "Over-formality", "Cognitive tell", "Burstiness", "synonym
  cycling", "rule of three". Only `phase-4-validate.md` in `brief/` restates
  rules. `skills/comp/`, `skills/prd/`, `skills/roadmap/` validate phases and
  `skills/design/phase-6-final-review.md` contain no style rules.
- `references/` (19 files) -- `pr-body-conformance.md:59` mentions the
  AI-attribution convention, not the rulebook.
- `skills/plan/references/plan-format.md:118-119` -- an example issues-table
  row describing FC10; a pointer, not a copy.
- `.github/workflows/`, `scripts/`, `koto-templates/` -- no rule content.
- `crates/shirabe-validate/src/checks.rs` tests (6064-6130) -- iterate
  `FC10_BANNED_WORDS` rather than duplicating it. No independent list.

One borderline case, reported and deliberately not counted:
`skills/writing-style/evals/evals.json` restates rule content inside grading
assertions (line 8 lists thirteen flagged words; line 125 restates all six
over-formality substitutions; lines 74 and 89 restate formatting tells). These
are test fixtures for the canonical rulebook, co-located in its own skill
directory, and they enforce nothing at author time. Calling them a fourth
enforcement copy would be wrong. They would drift if the rulebook changed,
which is a real consequence of the same root cause -- worth a sentence in the
PRD, not a correction to the BRIEF's count.

### 3. Public-repo cleanliness: PASS

No surviving reference to the consumer workspace, its root CLAUDE.md, its
private directories, `.claude/helpers/writing-style.md`, `wip/` paths, or any
internal tooling. Grepped the BRIEF for `workspace`, `tsukumogami`,
`.claude/helpers`, `private`, `overlay`, `wip/`, `dot-niwa`: zero hits. The
only cross-repo names are koto, niwa, and tsuku, all public, and the claim
made about them is exactly true -- each has
`.github/workflows/validate-docs.yml` containing
`uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@main`. An
external reader needs no organizational context to follow the document.

On adopter over-claims: the frequency argument ("This defect class is not
specific to one repo. It follows from how the prose is produced") is presented
as an inference from the production mechanism rather than as a measurement,
which is honest and fair. One universal is weaker: "Any adopter has its own
such collisions, and it has no way to declare them today" (line 76). The second
half is verifiable; the first assumes every adopter has terms of art that
collide with the banned list, which is likely but untested. Non-blocking --
see optional improvements.

Incidentally, the BRIEF contains zero em dashes, which given its subject
matters.

### 4. Regression check: PASS

- **Problem Statement.** States a problem, does not name or presuppose a tool.
  "Vale" appears nowhere in the body (zero case-insensitive hits). The
  candidate mechanisms are named only in the out-of-scope list as alternatives
  the DESIGN must choose between.
- **User Outcome.** Outcome-shaped throughout, no mechanism named. Users named
  in each paragraph: shirabe maintainer, author editing an instruction file
  (both shirabe skill author and adopter editing their own CLAUDE.md), adopting
  repo, and the reader of the feedback.
- **Journeys.** Five, each with a trigger and an outcome shape, none stating a
  mechanism. The new fifth journey (adopter declares vocabulary) is genuinely
  distinct from the fourth (maintainer changes a rule once): different actor
  (adopter maintainer vs shirabe maintainer), different trigger (noise in their
  own PRs vs a rule edit), different capability (repo-local suppression that
  survives a shirabe upgrade vs single-source propagation). Not a restatement.
  One wart in the fourth journey, noted below as optional.
- **Scope Boundary.** Seven IN items, seven OUT items, all substantive. The
  out-of-scope entry on FC10's three defects draws a real and unusually
  careful boundary (the property is in scope, repairing today's check is not).
- **Open Questions.** Four, all deferring to PRD or DESIGN, none blocking the
  BRIEF. The new one (extend vs replace) states both horns and why the answer
  matters, and correctly routes to the PRD. Open Questions with status Draft
  satisfies the Draft-only rule.

Underlying technical claims re-verified: `formats()` returns 8 formats
(`formats.rs:297-299`), so "eight artifact prefixes" is exact;
`check_writing_style` indexes `doc.body` and emits `idx + 1`, so the
frontmatter line offset is real; it scans every body line with no fence, inline
code, or URL exclusion, so those false positives are real;
`check_claude_md_conventions` is wired at `validate.rs:210` but unreachable
because `detect_format` never matches `CLAUDE.md`.

### 5. Frontmatter: FAIL

Mechanics are correct. `problem` (lines 4-8), `outcome` (lines 9-13), and
`motivating_context` (lines 14-18) are each literal block scalars (`|`) of
exactly 4 content lines. FC03 passes: the first non-blank line after `## Status`
is the bare token `Draft`, matching frontmatter `status: Draft` (verified
against `check_fc03` at `checks.rs:121-168`, which takes the first non-blank
non-heading line after the heading).

`outcome` matches the User Outcome section: one rule source, both surfaces,
defects the drafting model cannot catch, quiet on the ones it avoids, reaching
every adopter. All four clauses map to a User Outcome paragraph.

`problem` fails the match on its second clause. "cannot see the files where
most agent-authored prose lives" asserts a majority the Problem Statement never
asserts and the numbers contradict (442,043 words visible to FC10 under
`docs/` against roughly 225,000 unchecked). The body's actual claim is about
leverage rather than volume: the unchecked prose "is exactly the prose that
instructs every future agent run". Paraphrase is fine; this is a stronger claim
than the section supports, which is the failure mode the check exists to catch.

### 6. Numbers traceable: FAIL

All ten enumerated figures trace exactly, and re-scoping did not detach any
from its qualifier. The failure is an eleventh figure the brief adds.

| Figure in BRIEF | Source | Verdict |
|---|---|---|
| 554,000 words (phrase apparatus, ~2 true positives) | findings:32-36 "Across 554,000 words ... produces roughly two true alerts" | Traces. Also reconciles: 397k prose-scoped `docs/` + 157k prose-scoped `skills/`. |
| 211 files / 197,538 words under `skills/` | findings:133 "shirabe's `skills/**` alone is 211 files and 197,538 words, all mechanically unchecked"; measurement-method:158 `wc -w` = 197538 | Traces. Qualifier "in shirabe's own repo" correctly attached. |
| 128 of 156 alerts | measurement-method:113,133 "`Shirabe.AvoidWords` 156"; "128 of 156 (82%) are `tier`" | Traces. BRIEF's "in a `docs/` run" matches the source's `docs/` scope. |
| 112 (`journey`) | findings:43 "The lead agent's wider run adds `journey`/`journeys` at 112 hits" | Traces. Minor elision: the 112 comes from a wider run than the 156-alert `docs/` run, and the BRIEF presents both as "the two highest-volume matches" without flagging the different scope. Not inaccurate, since neither number is used as a fraction of the other. |
| 3,114 and 1,188 em dashes | measurement-method:171-172 prose-scoped table | Traces, and correctly follows the source's explicit instruction at line 187: "Cite 3,114 with 7.84, not 3,195 with 7.84." The BRIEF's lead-in "Counting body prose only" carries the qualifier. |
| 7.84 and 7.59 per thousand | same table | Traces. |
| 72% above 3 per thousand | measurement-method:171 "104 of 145 (72%)", column header "Files over 3/1000" | Traces, including the threshold. |
| 28.5 | measurement-method:174 "`PRD-shirabe-pattern-v1-ergonomics.md` at 28.5 per thousand (118 em dashes in 4,138 words)" | Traces. |
| 1.7% | findings:46 "Raw precision on the word rules measures 1.7%" | Traces. |
| ~16% | findings:46-47 "after excluding the two domain terms and the PRD that quotes the rulebook, about 16% on 31 alerts" | Traces. BRIEF's "domain terms and the one document that quotes the rulebook" is a faithful paraphrase. |

**The failure: "roughly 60 banned words" (line 37).** The actual count in
`skills/writing-style/SKILL.md` is 47 entries: Organizing 7, Verbs 15,
Descriptors 10, Abstract nouns 8, Adverb openers 7. Counting `tier/tiered` as
two gives 48. "Roughly 60" overstates by about 25%, past what "roughly"
covers. It traces to `findings:143`, whose table row reads "~60 words, 7
phrases, 7 structural, 5 formatting, 6 substitutions, 4 cognitive" -- so the
BRIEF inherited an overcount from the exploration rather than inventing one.
The rest of that row is exact against the file (7 phrase bullets, 7 structural
rows, 5 formatting rows, 6 substitutions, 4 cognitive tells), which makes the
one wrong number more conspicuous, not less. A corroborating signal: the
exploration's own faithful translation produced an `AvoidWords.yml` of 34
tokens, not 60.

## Required changes

**R1. Fix the banned-word count.** Line 37: "roughly 60 banned words" ->
"47 banned words" (or "roughly 50"). Verify against the five tables in
`skills/writing-style/SKILL.md`: 7 + 15 + 10 + 8 + 7 = 47. Do not inherit the
`~60` from `findings:143`; that row is wrong.

**R2. Fix the frontmatter `problem` majority claim.** Lines 6-7: replace
"cannot see the files where most agent-authored prose lives" with the claim
the body actually makes, which is stronger anyway. Suggested: "cannot see the
instruction files that shape every future agent run". This restores the
frontmatter/body match and removes an assertion the measurements contradict.

**R3. Drop the superlative.** Line 65: "which is the largest body of
shirabe-authored prose available and so the fairest test case this repo can
run" -> "the largest shirabe-authored corpus this repo can measure directly,
and so the fairest test case available to it" -- or simply cut the first
clause and keep "the fairest test case this repo can run", which already
justifies the choice without asserting anything about corpora the exploration
never measured.

## Optional improvements

**O1. The fourth journey's example collides with the fifth journey's
capability.** Journey 4 opens: "A shirabe maintainer decides `tier` should stop
being flagged, because it is shirabe's own vocabulary." But the Scope Boundary
routes exactly that case elsewhere: "shirabe's `tier` and `journey` are the
first consumers of that capability" -- the per-repo vocabulary declaration of
journey 5. As written, journey 4's trigger is journey 5's use case dressed as a
global rulebook edit, which invites the reader to wonder why it is not simply a
vocabulary declaration. Journey 4's outcome shape (one edit, every surface) is
right; give it a trigger that is genuinely a rule change -- retiring a rule,
adding a word, changing a threshold -- rather than a shirabe-vocabulary
suppression.

**O2. "five-word instruction" is imprecise.** The jury instruction has five
entries covering seven words, since "tier/tiered" and
"comprehensive/holistic" are slash pairs. "Five-entry instruction" would be
exact and would preserve the parallel with "seven-word constant", which is
exact.

**O3. Two `skills/` denominators, two paragraphs apart.** The doc cites
197,538 words under `skills/` (raw `wc -w`) and later a 7.59-per-thousand em
dash rate whose denominator is the prose-scoped ~157,000. Each is correctly
qualified in isolation, but a reader who divides 1,188 by 197,538 gets 6.01 and
concludes the brief is wrong. Naming the prose denominator once ("1,188 in
about 157,000 words of `skills/` prose") would close that trap.

**O4. Soften one adopter universal.** Line 76: "Any adopter has its own such
collisions" asserts something about every adopter that no measurement covers.
"An adopter with its own terms of art hits the same collision" makes the same
point without the universal, and the sentence's real payload -- "it has no way
to declare them today" -- is unaffected.
