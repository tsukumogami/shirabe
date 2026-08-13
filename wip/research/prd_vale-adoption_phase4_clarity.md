# Phase 4 Verdict: Clarity

VERDICT: FAIL

Reviewed against md5 `052da9d244159eb5314200539c96d07b` (R1-R20, 20 acceptance
criteria). The document was edited twice during review; earlier drafts had a
broken `Recorded as R15 and R16` cross-reference and a `cmd/shirabe` path that
does not exist in this Rust repo. Both are fixed in the reviewed version and are
not counted against it. Every cross-reference in the frozen version resolves
correctly, verified mechanically.

Three criteria fail: ambiguity (1), factual accuracy (2), and decision quality
(5). Four pass, one of them (writing style) emphatically.

## Per-criterion

### 1. Ambiguity — FAIL

Eight requirements admit two competent readings that produce different
implementations. Four of them are load-bearing.

**R1 does not forbid the exact failure it exists to prevent.** "Every enforcing
surface SHALL read from it" does not say *when*. A build script that reads
`skills/writing-style/SKILL.md` at compile time and bakes a constant into the
binary satisfies every word of R1: there is exactly one authoritative
representation, nothing restates it, the three copies collapse to one. It also
reproduces precisely the defect the Problem Statement opens with — the FC10
design "required the validator read the list from the SKILL.md at validate time
so updates would propagate; the shipped code hardcodes it." The acceptance
criterion does not close it either: "A rule added to that source is honored by
`shirabe validate` without a second edit" is true of codegen, because a rebuild
is not an edit. R1 needs the word "at enforcement time" or equivalent.

**R2's "the same resolution" is genuinely two-way.** Read as *the same path*, R2
forbids the natural design, because in CI the validator resolves from
`.shirabe-src/` while a drafting skill resolves from `${CLAUDE_PLUGIN_ROOT}/` —
literally different path strings on the same machine. Read as *the same file at
the same commit*, the split is fine. The Decisions section reveals the author
means the second ("the plugin already resolves references from its own root for
the agent-side consumer"), but R2 does not say it, and a design agent reading
requirements first will build to the first reading. R2's second sentence ("A
source honored by only one consumer does not satisfy R1") is also a testability
note about R1 rather than independent requirement content.

**R3 is satisfiable by a flag nobody passes.** "SHALL be able to run against"
states a capability, and "which SHALL no longer be the case *when prose checking
is requested for them*" explicitly conditions the behavior on a request. An
implementer ships `shirabe validate --prose-check <file>`, leaves the default
path unchanged, and complies fully — while User Story 2 (an author editing
`skills/execute/SKILL.md` wanting findings on the file they are editing) and the
BRIEF journey it carries forward both describe the default invocation. AC4 is
stronger than R3 here, which is backwards: the requirement should carry the
constraint. Separately, "specifically SKILL.md, CLAUDE.md, AGENTS.md, and
README.md" does not say whether the list is exhaustive or illustrative —
`CLAUDE.local.md` is read by the validator's own visibility resolver today, and
`AGENTS.md` has a `.local` sibling convention.

**R4 names the wrong noun and leaves a numeric hole.** "Table delimiters" means
the `|---|---|` separator row. The defect in the sources is matches inside table
*rows and cells* — FC10 "runs over every line of `doc.body`, including fenced
code, table rows". An implementer can skip separator rows, keep reporting on
cell prose, and satisfy R4 literally. This is not pedantic: the measurement the
PRD quotes excluded whole table rows (27 of the docs/ em dashes sit in cells),
so under the permissive reading of R4 the corpus figure in the Problem Statement
does not reproduce from the PRD's own scoping rule. Worse, R4 is silent on
**headings**, and that silence is exactly where the two source measurements
diverge: the BRIEF method counts the 126 heading em dashes (3,114 total, 7.84
per thousand), the check-lifecycle lead excludes them (2,785, 7.29). R4 is the
requirement that should settle which number a future re-run must produce, and it
does not.

**R8's "term-scoped" leaves morphology and case open.** The rulebook's entry is
the single cell `tier/tiered`; the exploration's working vocabulary file needed
five surface forms (`[Tt]ier`, `[Tt]iers`, `[Tt]iered`, `[Jj]ourney`,
`[Jj]ourneys`) to be survivable. A repo declaring `tier` may or may not stop
receiving `tiered`, `Tiers`, `Tier`. The acceptance criterion ("A repository
declaring `tier` receives no `tier` findings") repeats the ambiguity rather than
resolving it. Two competent implementers build different things, and the one who
builds exact-match ships a knob that does not suppress `Tier 1-4` — the
literal case that motivated the requirement, since 46 of the 128 hits are
capitalized `Tier`.

**R11 appears to forbid the posture the PRD later plans to adopt.** "Every rule
SHALL ship at a severity that does not fail an adopter's build" excludes
draft-tolerable, which is error-level once a PR is marked ready. The Decisions
section rejects draft-tolerable for an unrelated reason (`validate-docs.yml`
does not thread `--mode`) and then says it "becomes the natural posture at
promotion time" — but R11, read at promotion time, still forbids it. The
qualifier "on the release that introduces it" gestures at the right scope; the
sentence's subject ("Every rule SHALL ship at a severity that...") reads as a
standing property. State plainly whether draft-tolerable is a permitted
severity.

Weaker, but worth fixing:

- **R13's first sentence has no application to this feature.** R14 settles that
  no new code is added, so "Adding a check code SHALL register it in every list
  that gates it" cannot be exercised by this delivery; only the "stale copies
  SHALL be corrected" clause is testable, and only that clause has an AC.
- **R15 is unfalsifiable here by construction** — it constrains a path the PRD
  states will not be taken, and its AC ("`--check <code>` succeeds for every
  code that `is_known_check_code` accepts, including any retired as a no-op")
  passes vacuously when nothing is retired. That is defensible as a recorded
  forward constraint, but it sits in Functional requirements as though in scope.
- **R17's behavioral half is a tautology** ("a repository that has declared no
  vocabulary SHALL receive the unsuppressed rate"). Its real content is the
  documentation obligation in the last sentence. "The unsuppressed rate" is also
  a vague noun in a document where "rate" otherwise means em dashes per thousand
  words.
- **R20 is near-tautological**: a capability scoped to `docs/**` reaching repos
  that filter `docs/**` is a fact about the existing wiring, not a constraint on
  the build. Its testable content is the documentation clause.

### 2. Factual accuracy — FAIL

Every figure traces to a source. Six are stated at a different scope than
measured, and two of those are regressions against the BRIEF, which had them
correctly scoped. Details in the section below.

Verified correct and correctly scoped: 47 banned words (7+15+10+8+7, confirmed
against `skills/writing-style/SKILL.md`); three in-repo copies (the exploration
counts four, but the fourth is the workspace-root CLAUDE.md outside this
repository, so "two further copies exist inside the repo" is accurate); 197,538
words / 211 files under `skills/`; two true positives from the phrase apparatus;
128 of 156 and 112 as individual figures; 3,114 and 1,188 em dashes,
prose-scoped, which is the pairing the measurement-method file explicitly
directs ("Cite 3,114 with 7.84, not 3,195 with 7.84"); 28.5 as the worst file;
seventeen registration touchpoints; six failing silently; the `FC01`-`FC13` vs
`FC01`-`FC16` staleness (confirmed live at `crates/shirabe/src/main.rs:216` and
`docs/guides/multi-consumer-cli-contract.md:89`); nine notice-level codes; 33 of
124 skipping; five dangling `upstream:` links; "the other 46 terms" (47 minus
`tier`, internally consistent — note the vocabulary-model lead says 45, and the
PRD's arithmetic is the correct one).

I re-ran the Known Limitations claims against the shipped binary. Both
reproduce exactly: `find docs -name '*.md' | xargs shirabe validate
--visibility=public` gives **5 errors, 139 notices**, with the breakdown FC10 97,
FC08 7, R6 5, FC15 1, FC09 1, and 33 "schema field missing" skips. And
`shirabe validate -- docs` returns "All checks passed", exit 0, having read
nothing. The new directory-argument paragraph is sound and is the strongest
new material in the document.

### 3. Problem Statement stands alone — PASS

Both halves hold.

Self-contained: a reader landing cold gets the two governed surfaces, the three
copies with their sizes and locations, and three separately-named defects each
carrying its own measurement. Nothing requires opening the BRIEF. The
"why now" is thinner in the body than in `motivating_context`, but the defect
enumeration carries it.

No wrongful restatement: the five User Stories carry the BRIEF's five journeys
forward into the PRD's own required section in as-a/I-want/so-that form rather
than summarizing them alongside, which is what the format prescribes. There is
no Background or Summary section duplicating upstream framing.

One thing to tighten, not a failure: four Out of Scope entries reproduce the
BRIEF's boundary with the BRIEF's own supporting evidence, and one does it
near-verbatim — "Their content is settled; only where they live and what
enforces them is in question" is the BRIEF's sentence with two words dropped.
Out of Scope is a required contract section, so a self-standing statement is
defensible; a sentence copied verbatim is still a second copy that can drift,
in a document whose thesis is that copies drift.

### 4. Writing style — PASS

Real counts, body prose with table rows excluded, 3,767 words:

| Measure | This PRD | Reference |
|---|---|---|
| Em dashes | **1** (0.27 per thousand) | corpus 7.84; discussed threshold 3 |
| Bold runs | 42 (11.15 per thousand) | corpus 10.9 |
| Title Case headings | 0 authored | — |
| "serves as" / "stands as" / "boasts" | 0 | — |
| Stacked qualifiers | 0 | — |
| Hollow gerunds | 0 | — |
| Adverb openers | 0 | — |
| Filler phrases ("worth noting", "in conclusion", "at its core", "in order to", "delve") | 0 | — |
| Sentence length | mean 20.1, stdev 11.5, range 1-52 | good burstiness |
| Contractions | **0** | 27 uses of "do not / does not / cannot / is not" |

Not self-refuting. At 0.27 em dashes per thousand the document sits eleven times
under the threshold it discusses and roughly thirty times under the corpus it
indicts. That is the strongest available demonstration of its own argument.

Banned words: nine hits total, all `tier` (6), `journey` (2), `Tier` (1), every
one either backticked as the term under discussion or capitalized as the domain
term in "Tier 1-4". Quoted-while-explained, exactly as briefed. Not flagged.

Bold at 11.15 per thousand is nominally above the corpus average, but all 42
runs are structural labels — 5 user-story leads, 20 requirement labels, 10 Out
of Scope bullet labels, 5 decision leads, 2 spillover from `docs/**` in inline
code. There is zero decorative emphasis. The raw number overstates the tell.

Two findings worth fixing:

**Zero contractions in 3,767 words**, against 27 instances of the expanded
forms. "No contractions" is a formatting tell in the very rulebook this PRD
exists to consolidate and enforce, which makes it the one style defect that
costs the document something. It reads stiffest in the User Stories, where a
person writes "I don't have to find and update three copies", "a capability I
didn't ask for", "properties I couldn't observe while composing" — all three
currently expanded. SHALL-language in the requirements is a fair reason to stay
formal there; the stories and the Decisions prose are not.

**Two sentences garden-path.** "The properties in R4 and R5 are required of
whatever ships, and R14 fixes that exactly one prose check code survives" — the
reader parses "fixes that [noun]" and has to back up to reach the intended
"pins/settles". And R11's "Measured: error-level on first release would fail..."
sends the reader looking for a measurement noun after the colon.

### 5. Decisions and Trade-offs quality — FAIL

Three of four decisions and the remaining-unknown entry are complete. One
decision misdescribes the alternatives it rejects.

**Decision 1 (rule source ships in-repo): incomplete and partly wrong.** It
records the outcome and the reasoning, and it names three alternatives — a
release asset, a vendored copy, a published package — then rejects all three
with a single sentence: "All three introduce a fetch that can fail and a skew
between rules and binary." That is false for the vendored option. The source
says the opposite in as many words: vendoring "Works offline, no fetch. But it
drifts silently." Vendoring's real cost is drift with no upstream signal, which
is a *different and stronger* argument against it given this feature's whole
premise. The stated reason rejects the alternative for a property it does not
have.

The same entry omits the alternative an implementer is most likely to reach
for: compiling the rules into the binary via `include_str!`. It is option A in
the adopter-surface research, it is the closest analogue to what FC10 does
today, and its trade-off is genuinely interesting (zero skew, but no adopter or
third-party tool can read the rules without running the binary). A decision
record that omits the nearest neighbour to the status quo leaves the DESIGN free
to re-litigate it.

**Decision 2 (extends, not replaces): complete.** Decision, alternative
(`--custom-statuses`-style replace), and why (a replacing repo becomes a fourth
divergent copy by another route). It also records why the divergence from
precedent is deliberate, which is the part a downstream reader would otherwise
re-open.

**Decision 3 (extend FC10, do not retire): complete and well-formed.** Decision,
alternative, costed reasoning (seventeen touchpoints, no deprecation path, prior
rejection of an FC-code rename on the same grounds), and an explicitly accepted
counter-argument (the code's name stops describing what it does). The follow-on
paragraph correctly notes that the `shirabe-validate/v1` contract question does
not arise and defers it to R15.

**Decision 4 (below error level with a filed promotion condition): complete.**
Decision, alternative (error-level after a cleanup), and evidence-based
rejection (nine codes, zero cleanup issues, zero promotions in 292 commits).
The added draft-tolerable paragraph now records the third option with its own
rejection reason and the condition under which it becomes the right posture.
This was the largest gap in the earlier draft and it is properly closed —
subject to the R11 wording problem noted under criterion 1.

**Remaining unknown: properly formed.** It names what is open (reporting unit),
why it is not decided here (a judgment about what an author should see, not a
success condition), and who owns it (the DESIGN).

### 6. No wip/ references — PASS

Zero occurrences of `wip/` anywhere in the committed body or frontmatter,
verified by grep. `upstream:` points at `docs/briefs/BRIEF-vale-adoption.md`,
which exists.

### 7. Public-repo cleanliness — PASS

No private repo paths, no private repo names, no issue numbers of any kind (the
document cites zero issues), no internal-only tooling or workflow names. All
referenced paths are public in-repo paths (`crates/shirabe-validate/...`,
`skills/writing-style/SKILL.md`, `docs/guides/multi-consumer-cli-contract.md`,
`.shirabe-src`, `validate-docs.yml`) and all named sibling repos are the public
koto, niwa, tsuku. Nothing to redact.

## Untraceable or mis-scoped figures

**1. "7.84 per thousand words with 72% of files above 3 per thousand and the
worst at 28.5"** (Problem Statement). All three figures are `docs/`-only, but
the sentence attaches them to a compound numerator covering both trees: "em
dashes run 3,114 in `docs/` and 1,188 in `skills/`, 7.84 per thousand words
with 72%...". Source: `docs/` = 7.84, 104 of 145 files (72%); `skills/` = 7.59,
76 of 211 (36%). The BRIEF scoped this correctly — "In `docs/` that is 7.84 per
thousand words, with 72% of files above 3 per thousand and the worst at 28.5;
`skills/` runs a comparable 7.59." The PRD dropped the scoping and the 7.59.
This is a regression against the upstream, in the paragraph that carries the
document's central empirical claim.

**2. "92 of shirabe's 124 validator-visible docs"** (R11, and again in Decision
4). Threshold-contingent, stated as unconditional. Source: the file-level
threshold table gives 94 files at >1/1000, **92 at >3/1000**, 77 at >5, 63 at
>8, 49 at >10, 24 at >12, **11 at >15**, 1 at >20, 0 at >25. The PRD never
states the 3-per-thousand basis, and R7 explicitly leaves the threshold to the
DESIGN. So the requirement that decides severity rests on a number that a
different, equally defensible threshold changes by a factor of eight. Same
problem for **"roughly half of koto's and niwa's corpora"** — the adopter table
gives koto 47% and niwa 49% *at >3/1000*; tsuku is 20%. Either name the
threshold in R11 or state the range.

**3. "Across 554,000 words ... raw word-rule precision measures 1.7%"**
(Problem Statement). Two different corpora in one sentence. 554,000 is
`docs/` + `skills/` prose (397k + 157k) and is the denominator for the
phrase-apparatus claim. The 1.7% was measured on `docs/` alone: 290 word-rule
alerts, about 5 true, over 397k prose words in 145 files. The BRIEF made the
same elision; it should be fixed here rather than inherited.

**4. "rising to about 16% once domain terms are excluded"** (Problem Statement,
and repeated in R17). The source requires **two** exclusions to reach 16%:
"After the `accept.txt` vocab (tier, journey) *and excluding the one PRD that
quotes the rulebook*: 31 alerts, ~5 true, precision ≈16%." The BRIEF carried
both ("once domain terms **and the one document that quotes the rulebook** are
excluded"). The PRD dropped the second in both places it states the figure.
Second regression against the upstream, and the dropped qualifier is the one
that makes 16% look more achievable than it is.

**5. "`tier` is 128 of 156 alerts in a `docs/` run ... and `journey` at 112
hits"** presented as "the two highest-volume matches" of one measurement. They
come from two different runs and no single run produces both. The 128-of-156
figure is the orchestrator's custom-style run over a **34-token** `AvoidWords.yml`
that did not include `journey` at all — its word-frequency table runs tier 82,
Tier 46, robust 7, leverage 5, comprehensive 4, tiered 3, holistic 3,
facilitate 3, Tiered 1, resilience 1, nuanced 1. The 112 figure is from the
rule-translation lead's run over **all 47 words**, in which the total is 290 and
`tier/tiers/tiered` is **147**, not 128. Cite one run: either "147 and 112 of
290 alerts" from the 47-word run, or keep 128 of 156 and drop the claim that
these are the top two of the same measurement.

**6. "440,003 words of artifact prose"** (Problem Statement). Two problems.
First, it does not trace to any of the four named research sources; it appears
only in `wip/scope_vale-adoption_decisions.md`, measured at BRIEF acceptance.
Second and more important, it is a raw `wc -w` figure (463,440 total `docs/`
words minus 23,437 non-prefixed), and the measurement-method file is explicit
that `wc -w` "counts table pipes, rule separators, and fence markers as words,
so this denominator is inflated." The prose-scoped `docs/` figure is ~397,000.
Calling a raw count "artifact prose" three paragraphs before carefully labelling
the em dash figures "counting body prose only" reintroduces exactly the
raw-versus-prose-scoped mismatch a prior round caught on the BRIEF. Either
label it raw or use the prose-scoped number.

**7. Secondary: "roughly thirty times between per-occurrence and per-document"**
(R7). The ratio is 2,785 / 92 = 30.3, correct as stated, but the per-document
end of it is the same threshold-contingent 92. At a 15-per-thousand threshold
the per-document count is 11 and the ratio is roughly 250x. The figure supports
R7's point either way, but "roughly thirty times" is presented as a property of
the reporting unit when part of it is a property of an undecided threshold.

## Required changes

**Ambiguity**

1. R1: state that every enforcing surface reads the source **at enforcement
   time**, so build-time embedding does not satisfy it. Then strengthen the
   corresponding AC beyond "without a second edit" (which codegen passes) to
   something a rebuild does not satisfy.
2. R2: replace "through the same resolution" with what is actually meant — the
   same file at the same commit, reached by each consumer through its own root
   (`.shirabe-src` in CI, plugin root for the agent). The Decisions section
   already says this; move it into the requirement.
3. R3: drop "SHALL be able to" and "when prose checking is requested for them".
   Require that `shirabe validate <file>` produces prose findings for these
   filenames by default. State whether the four names are exhaustive or the
   class is "files that are not artifact-prefixed", and say what happens for
   `CLAUDE.local.md` and `AGENTS.local.md`.
4. R4: replace "table delimiters" with "table rows" or "table cells", and add
   an explicit ruling on **headings** — in or out of the prose denominator. This
   is the difference between the 3,114 and 2,785 measurements and it must be
   decided here for the corpus figure to be reproducible.
5. R8: state whether declaring a term suppresses its morphological variants and
   whether matching is case-insensitive. Add an AC covering `Tier` and `tiered`
   under a `tier` declaration.
6. R11: say explicitly whether draft-tolerable is a permitted severity, and if
   so, scope the requirement to the introducing release rather than to "every
   rule".
7. R13: scope the first sentence to "if a check code is added", or note that
   R14 makes it conditional. R15 and R17: separate the testable clauses (the
   deprecation properties; the documentation obligation) from the unfalsifiable
   framing. R17: replace "the unsuppressed rate" with what it means.

**Factual**

8. Restore the `docs/`-only scoping on 7.84, 72%, and 28.5, and either restore
   the `skills/` 7.59 or drop the 1,188 numerator.
9. Name the 3-per-thousand threshold wherever 92-of-124 and "half of koto's and
   niwa's" appear, or give the range (11 files at 15 per thousand, 92 at 3).
10. Detach 554,000 from the 1.7% clause; the precision figure is `docs/`-only
    (290 alerts over 397k prose words).
11. Restore the second exclusion on the 16% figure, in both the Problem
    Statement and R17.
12. Fix the tier/journey pairing to come from one run: 147 and 112 of 290, or
    drop "the two highest-volume matches" framing.
13. Label 440,003 as a raw word count, or replace it with the prose-scoped
    ~397,000. Trace it to a research source or re-measure.
14. Consider stating 1.7% and 16% once rather than twice — R17 currently
    carries a second copy of a Problem Statement figure, with the same dropped
    qualifier, which is a drift surface in a document about drift.

**Decisions**

15. Decision 1: correct the rejection reason. Vendoring introduces no fetch; it
    introduces silent drift with no upstream detector. Add the fourth
    alternative (rules compiled into the binary via `include_str!`) and its
    trade-off, since it is the nearest neighbour to today's FC10 and the DESIGN
    will otherwise re-open it.

**Style**

16. Use contractions where the register allows — the User Stories especially
    ("I don't have to", "I didn't ask for", "I couldn't observe"). Zero
    contractions in 3,767 words is a tell from the rulebook this PRD exists to
    enforce.
17. Rewrite "R14 fixes that exactly one prose check code survives" and R11's
    "Measured:" opener; both garden-path.

**Optional**

18. Cite the BRIEF's Out of Scope boundary for the four entries that reproduce
    it rather than restating it, particularly "Rewriting the rules themselves",
    which is verbatim.
