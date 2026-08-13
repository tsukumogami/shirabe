# Phase 4 Verdict: Content Quality

VERDICT: FAIL

Two criteria fail: factual grounding (one number the findings do not
carry, one attribution that merges two different measurements) and scope
boundary (an OUT item that contradicts a journey's stated outcome). Both
are narrow, correctable edits. The framing itself is strong — the
Problem Statement holds the line against the solution it came from, the
outcome is genuinely outcome-shaped, and the journeys are distinct.

## Per-criterion

1. **Problem Statement: PASS** — It never names the tool, and it does
   not smuggle it in another shape. The section states four things, all
   of them gaps rather than mechanisms: the rulebook exists in four
   divergent copies with a fifth dangling pointer; three copies are
   applied by judgment and the fourth is deterministic but blind to the
   files where most agent-authored prose lives; widening the word list
   would buy almost nothing (with the measurement to back it); and the
   one defect class nothing covers is document-level frequency.

   I checked the two ways this could have gone wrong. First, describing
   the wanted mechanism: the closest the section comes is "frequency is
   a document-level property and a model composing one sentence at a
   time cannot see it." That is a statement about why the defect
   persists, not about what should count it — it rules in a counter, a
   hook, a widened native check, a human reviewer with a script, or a
   rulebook change that stops caring about em dashes. Second, framing so
   only one answer fits: the framing leaves at least the three
   alternatives the exploration left open, plus the do-less option of
   simply fixing the existing check. "The harder half of the problem is
   that widening the word list would buy almost nothing" is the one
   sentence that reads as solution-space reasoning, but it eliminates an
   answer rather than selecting one, and it is grounded in measurement.
   That belongs in a problem statement.

   The Status section's tool-neutrality note ("Whether the answer is an
   external linter, a widened native check, or a mix is a DESIGN
   decision") is the right place for that disclosure, and it does not
   leak into the problem framing.

2. **User Outcome: PASS** — Three paragraphs, each with a named user and
   a stated difference. A maintainer changes a rule once "without
   hunting for four copies that have drifted apart." An author editing a
   SKILL.md gets feedback "instead of the silence that surface returns
   today." And the third paragraph is the one that earns the section:
   the feedback is worth reading, the signal stays high enough that
   nobody learns to ignore it, and domain vocabulary does not fire
   against the repo's own terms of art. Nothing here enumerates parts
   that got built.

   Against the `outcome` frontmatter, all four of its clauses land in
   the prose: one rule source (para 1), both prose surfaces (paras 1-2),
   reporting what the drafting model cannot catch in itself (para 3),
   staying quiet about what it already avoids (para 3). No drift.

3. **User Journeys: PASS** — Four journeys, four genuinely different
   entry points, which is where this criterion usually fails.

   - *Author edits a skill*: human authoring-time trigger on a surface
     nothing checks today.
   - *Drafting skill checks its own artifact*: machine trigger (artifact
     lands on disk) inside a skill's validate phase, on a surface that
     is already covered. The "user" is `/design` rather than a person,
     which is legitimate here — a skill is a concrete actor in this
     system and the journey names a specific one.
   - *Adopter repo inherits the checking*: distribution entry point,
     triggered by a PR in a repo that is not shirabe.
   - *Maintainer changes a rule once*: rule-author entry point rather
     than prose-author.

   Journeys 1 and 4 both begin with "a maintainer edits a file," but one
   is a consumer of the rules and the other is their author, and the
   outcome shapes are unrelated (findings on my file vs. propagation of
   my edit). Journeys 1 and 2 share an outcome family but split on the
   surface the problem statement establishes as different. That is four
   journeys, not one told four times.

   Each names its trigger explicitly ("the trigger is the edit itself",
   "the artifact landing on disk", "a PR in one of those repos touching
   a doc", "the edit"), and each states an outcome shape rather than a
   mechanism. Journey 1's scoping clause — imperative voice and bold
   labels are load-bearing in a file that instructs a model, so they
   must not register as defects — is the single most useful sentence in
   the section for a downstream PRD author.

4. **Scope Boundary: FAIL** — The lists themselves are strong. There is
   no filler in the OUT list; every one of the seven items is something
   a PRD author could plausibly have assumed was inside, and six of them
   carry a reason.

   On the two questions worth interrogating:

   (a) Excluding "choosing the mechanism" is coherent, and it does not
   gut actionability. Mechanism is DESIGN altitude by the format
   contract, so excluding it is not a scope choice the BRIEF is free to
   make differently. It is also the highest-value OUT item in the list,
   precisely because the exploration behind this BRIEF was tool-specific
   — a PRD author who knows the origin would otherwise assume the tool
   was settled. What remains for the PRD is mechanism-independent and
   substantial: which surfaces get checked, which rule classes exist,
   the single-source requirement, domain-vocabulary suppression, and the
   block-or-report policy. The PRD is writable.

   (b) The list is not too long and does not pre-empt PRD-owned
   decisions. Seven items is on the high side, but corpus cleanup, rule
   rewriting, commit-message prose, and the three incidental defects are
   all boundary lines rather than scope calls the PRD should be making.
   The one item that could read as pre-emption — "whether findings block
   or report, and at which severity" — is correctly placed IN, with the
   specific value deferred to Open Question 3. That pairing is coherent.

   What fails is a collision between the OUT list and Journey 2. The OUT
   list pushes out "FC10's frontmatter line-number offset" and "FC10's
   matches inside code fences and URLs" as independently fileable.
   Journey 2's outcome shape is "the phase gets accurate findings, right
   line and prose only" — which is exactly those two fixes, stated as
   something this feature delivers. A downstream PRD author cannot tell
   from the BRIEF whether correct line numbers and markup awareness are
   requirements of this work or separately filed bugs.

   The ambiguity is not hypothetical, because Open Question 2 leaves
   FC10's fate undecided. If the mechanism replaces FC10, the new
   checking is markup-aware and correctly located by construction and
   the OUT item is about legacy bugs that stop mattering. If FC10 is
   extended, the two defects are this feature's problem and the OUT item
   wrongly excludes them. Markup awareness is not a trivial line to draw
   on the wrong side: the exploration identifies it as the hard part of
   any native implementation.

5. **Open Questions: PASS** — All three defer rather than block. None is
   of the "we do not know if this should exist" shape; the BRIEF has
   already settled that the gap is real and worth closing.

   Question 2 is the best of the three, because it does the thing this
   section is for: it hands the PRD a specific job (state which outcome
   counts as success) and names the failure it prevents (a DESIGN free
   to leave two overlapping checks in place). Question 3 is properly
   paired with the corpus-cleanup exclusion, so the reader can see why
   it cannot be answered yet.

   One soft note, not a failure. Question 1 ("does the single rule
   source live in the repo that owns the rules or in a location the
   adopter repos can also read directly?") is phrased as a hosting
   choice, which leans DESIGN, while the BRIEF assigns it to the PRD.
   The requirement-level version of the same question — must adopters be
   able to read the source without installing shirabe? — is what the PRD
   can actually settle, and the sentence's second half ("against the
   adopter-distribution constraint") already gestures at it. Rephrasing
   is optional.

6. **Factual grounding: FAIL** — One number the findings do not carry,
   one attribution that merges two separate measurements, and one set of
   figures presented at a wider scope than they were measured.

   Checked against the findings, exact match:

   - **Four rulebook copies** — findings table lists exactly four
     (SKILL.md, `checks.rs:2551`, workspace CLAUDE.md, phase-4-validate
     reviewer). The BRIEF's fifth dangling pointer to
     `.claude/helpers/writing-style.md` matches the findings note. Also
     correct: the design required the validator read the list at
     validate time, and the implementation hardcodes it.
   - **211 files / 197,538 words** — verbatim.
   - **554,000 words** — verbatim.
   - **1.7% precision** — verbatim, and correctly labelled as the raw
     word-rule figure.
   - **3,195 em dashes in `docs/`, 1,222 in `skills/`** — verbatim.
   - **112 `journey` hits, and `## User Journeys` being a required
     section heading** — verbatim.
   - **Eight artifact prefixes in `detect_format`** — the findings list
     `COMP-`, `DESIGN-`, `PRD-`, `VISION-`, `ROADMAP-`, `PLAN-`,
     `STRATEGY-`, `BRIEF-`. Eight.
   - **Seven-word FC10 constant at `checks.rs:2551`** — verbatim,
     including the path and line.
   - **Ten alerts on the vacuous document under three style packages,
     none about the vacuity** — verbatim.
   - **~60 words plus phrases, structural patterns, formatting tells,
     substitutions, and four cognitive tells** — matches the findings
     table row.

   Checked outside the findings, verified independently and correct:

   - Journey 3's claim that koto, niwa, and tsuku each call shirabe's
     reusable `validate-docs.yml` pinned at `@main`. The findings only
     say "3 adopter repos"; I confirmed all three workflow files, each
     with `uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@main`.
     Grounded.

   Problems:

   - **147 `tier` hits — not in the findings.** The findings record 128
     (`tier`/`Tier`/`tiered`, out of 156 total alerts, from the
     orchestrator's custom-style run over `docs/`, 145 files, 463k
     words). No run in the findings reports 147. A raw corpus grep gives
     around 150 in `docs/` today, so 147 is plausible as some
     measurement — but it is not a measurement the source records, and a
     BRIEF cannot cite a number its exploration does not carry. Related:
     the BRIEF presents the `tier` and `journey` counts as a matched
     pair from one run; the findings source them from two different runs
     at different scopes.
   - **"Roughly two true positives" is attributed too widely.** The
     findings attribute roughly two true alerts to the class-A *phrase*
     apparatus (15 of 16 rules) across 554,000 words. The word rules are
     measured separately: 1.7% raw precision, about 16% on 31 alerts
     after excluding the two domain terms and the rulebook-quoting PRD —
     roughly five true positives, not zero. The BRIEF's "the phrase and
     word rules ... produce roughly two true positives" merges the two
     and understates the combined figure by a factor of about three. The
     argument survives the correction intact; the number as written does
     not.
   - **`docs/`-only figures presented as spanning both trees.** "Em
     dashes run 3,195 in `docs/` and 1,222 in `skills/`: 7.84 per
     thousand words, with 72% of files above 3 per thousand and the
     worst at 28.5." All three trailing figures are `docs/`-only in the
     findings (`skills/` measures 7.59 per thousand, and no percentage
     or worst-case is recorded for it). The rate difference is
     immaterial, but "72% of files" reads as a claim about both trees
     and is only supported for one.

## Required changes

1. **Fix the `tier` count.** In the Problem Statement, change "`tier` at
   147 hits" to the figure the findings carry — 128 — and scope it to
   the run that produced it. Suggested: "`tier` at 128 of 156 alerts in
   a `docs/` run is the Tier 1-4 decision-complexity vocabulary, and
   `journey` at 112 hits is a required BRIEF section heading." If 147
   came from a measurement the findings omit, the findings need the
   measurement added before the BRIEF can cite it.

2. **Re-scope "roughly two true positives."** Split the merged claim
   back into the two measurements the findings actually made. Suggested:
   "the phrase apparatus that takes up most of the rulebook produces
   roughly two true positives across 554,000 words, and raw word-rule
   precision measures 1.7% — about 16% once the two domain terms are
   excluded."

3. **Scope the em dash figures to `docs/`.** Suggested: "Em dashes run
   3,195 in `docs/` and 1,222 in `skills/`. In `docs/` that is 7.84 per
   thousand words, with 72% of files above 3 per thousand and the worst
   at 28.5."

4. **Resolve the Journey 2 / OUT-list collision.** Pick one:
   - Narrow the OUT item to the legacy check only, making clear that
     correct line numbers and prose-only scoping are properties any new
     checking must have: "...FC10's frontmatter line-number offset and
     its matches inside code fences and URLs, as defects of the existing
     check. Whatever checking this feature settles on must report
     correct lines and skip code fences by construction; that property
     is in scope, repairing today's FC10 is not."
   - Or soften Journey 2's outcome shape so it does not promise the two
     fixes, leaving it at "the phase gets findings that name the
     document-level properties the drafting model could not observe
     about its own output," and move the accurate-line/prose-only detail
     into the current-state sentence where it already appears.

   The first option is better: accurate lines and markup awareness are
   real properties of the outcome, and the exploration flags markup
   scoping as the hard part of a native implementation, so the PRD
   should not be free to read it as out of scope.

## Optional improvements

- FC10 is named as "FC10" in the second paragraph of the Problem
  Statement, but the first paragraph introduces it only as "a
  seven-word constant in the validator." A cold reader has to infer the
  identity. Naming it on first mention would cost four words.
- "A drafting model reliably avoids 'leverage'" is an inference. The
  findings measure that the high-precision phrase rules run green and
  that word-rule precision is 1.7%; they do not isolate "leverage." The
  claim is almost certainly right, but "reliably avoids the words on the
  current seven-word list" is what the data supports.
- Open Question 1 could be rephrased from a hosting question into the
  requirement question underneath it (must adopters read the source
  without installing shirabe?), which is the part a PRD can settle.
- Journey 3's last clause — "the arrival does not require every
  adopter's CI to grow a dependency it cannot satisfy" — is the closest
  the BRIEF comes to constraining the mechanism. It is defensible as an
  outcome property rather than a mechanism choice, but it is worth a
  second look given how carefully the rest of the document stays
  tool-neutral.
