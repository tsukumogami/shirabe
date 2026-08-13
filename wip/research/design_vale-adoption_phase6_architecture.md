# Phase 6 Verdict: Architecture

VERDICT: FAIL

Six criteria judged. Four fail, two fail partially. The design's *choices* are
sound and I would not reopen any of the four decisions on the merits. What fails
is the design as an instrument: it drops the one question the PRD explicitly
delegated to it (R7's four values), it silently expands scope into something the
PRD lists as out of scope, it leaves the mechanism that makes Decisions 1 and 2
compose entirely unowned, and its phase boundaries are not green because three
frozen golden fixtures move and no phase mentions them.

Everything below was verified against the tree at
`/home/dgazineu/dev/niwaw/tsuku/tsuku+vale_or_not-33480214/public/shirabe/.claude/worktrees/vale-adoption`.

---

## Per-criterion

### 1. Strawman check — FAIL

Vale is *not* motivated reasoning. The design's three rejection findings (R18
outright, R3 aborts on shirabe's own tree, R4/R6 mutually exclusive) are the
source report's three findings in the source report's own order of force, and
the design carries the strongest counter-argument (reimplementing a mature
linter; FC10 as the cautionary tale) in full, with the report's actual rebuttal
(FC10 attempted no scoping at all). Decision 1 is the best-argued section of the
document. Two things are dropped from it and one of them matters:

- **Dropped, matters:** Option C's single honest argument. The report states it
  plainly — Vale ships a first-party Claude Code plugin with an edit-time hook
  and an LSP, "real, already built, and shirabe has no equivalent" — and then
  answers it (an authoring aid is not an enforcement engine; Option B forecloses
  nothing). The design's Option C paragraph reduces to "it doubles the
  rule-source problem," which is the report's *second* reason and omits the
  option's only genuine strength. Rejecting an option without stating the one
  thing it does better is the definition of the flattening this criterion tests
  for.
- **Dropped, minor:** the report gave both sides of the gh/git precedent
  (shirabe already spawns external binaries — for Option A; but those are I/O
  oracles and preinstalled — against). The design keeps neither side.

Decision 3 and Decision 2 each contain a rejection whose stated reason is
**materially weaker than its source**, which is the specific defect this
criterion names:

- **Option D of Decision 2 (rules in SKILL.md frontmatter).** Design: "puts a
  growing data structure in a position readers expect to be short." That is a
  readability preference. The report's reason is a coupling risk with a blast
  radius: SKILL.md frontmatter is a schema **Claude Code owns**, all 20 shirabe
  skills carry exactly two keys with zero precedent for a third, and if the
  unknown-key bet loses the skill stops loading — and 12 skills route through
  the writing-style skill. The report also hands the design a 20-minute
  falsification (add a key, load the plugin) and says explicitly: "the DESIGN
  should say so rather than leave the reader to wonder whether it was
  considered." The design substituted an aesthetic objection for a stated
  failure mode and skipped the cheap test.
- **Option B of Decision 3 (header naming a path).** Design: "one indirection
  more than the problem needs at shirabe's scale of two terms." The report's
  decisive reasons are a **dangling-pointer failure mode** — a header naming a
  missing file gives the repo full R17 day-zero firing while it believes it has
  declared — and the R16 split, where the drafting agent gets the pointer for
  free in context but not the terms, and must issue a Read that a skill author
  can forget. The design recovers half of the first reason 140 lines later in
  Security Considerations, and never recovers the second, which the report calls
  "the sharpest R16 differentiator."
- **Option C of Decision 3 (dotfile).** The design gives only the config-file
  objection. It drops the report's own concession that a structured file is "the
  strongest forward-looking argument any option has" (room for the reject
  direction and per-rule control), and drops the TOML-adds-a-dependency point.

Also missing: Decision 3's **strongest counter to the chosen option** — a
list-valued heading breaks the convention that every CLAUDE.md header is a
single scalar. The report flags this as a real break and instructs the design not
to "pretend the header convention absorbs it." The design pretends. Decisions 1
and 4 both record their strongest counter (the design does this well for those
two); Decision 3 records none, and Decision 2's is recorded only as the last
sentence of a rejection rather than as a counter to the choice.

### 2. Requirements traceability — FAIL

Full map below. Five requirements have no design element (R9, R14, R15, R16,
R19), one has an element that explicitly does not do what the requirement asks
(R7), and four are partial. Taking the four the brief names:

- **R7 (four values).** This is the sharpest failure in the document. The PRD
  deferred this to the design *by name*: "The reporting unit ... varies
  annotation volume on shirabe's corpus by about thirty times ... R7 requires the
  decision be made and documented; this PRD does not make it ... **The DESIGN
  owns it.**" The design's answer is that rules.yaml carries "threshold,
  denominator, reporting unit, and finding-line convention as fields, satisfying
  R7 by construction," and phase 5 adds the rule "with its four recorded values."
  It never states any of the four. A schema slot is not a decision. The threshold
  in particular is load-bearing elsewhere: the PRD's R11 impact range runs from
  92-of-124 failing docs at 3/1000 to 11-of-124 at 15/1000, and Decision 1
  measured that the raw-versus-prose scoping gap flips zero verdicts at 3/1000
  and 6-11 files at 10-15/1000. The design's R4/R6 driver ("a rate computed over
  text that includes code fences is not the rate the author is asked to act on")
  is only true at the thresholds the design declines to pick. The documentation
  surface is also unnamed: the AC requires all four recorded in
  `docs/guides/multi-consumer-cli-contract.md`, which the design never mentions.
- **R13 (no silent registration).** Half covered. Phase 6 corrects the two stale
  `FC01`-`FC13` prose copies, which is R13's unconditional obligation. The
  conditional half is untraceable because the design never says whether a code is
  added (see R14), and the AC's registration-list test is absent.
- **R15 (retirement non-breaking).** The design does not touch this at all. That
  is defensible on the merits — the PRD's decision to extend rather than retire
  makes R15 vacuous for this capability — but it is *not* traceable, and R15
  interacts with a change the design does make. `--check FC-CONVENTIONS` is
  accepted by `is_known_check_code` today and returns zero findings because the
  check is dead; after phase 3 it starts emitting. The design owes one sentence
  recording that nothing is retired, so R15 is discharged as vacuous rather than
  forgotten.
- **R20 (adopters need no workflow edit).** Half covered. Consequences says
  "Adopters get the capability with no workflow edit and no new dependency,"
  which is R20's first clause. R20's second clause — "Coverage of instruction
  files outside those filters SHALL be documented as requiring an adopter-side
  change" — has no design element, and it is exactly the clause a reader of this
  design would get wrong, because Decision 4 and the Consequences both talk about
  instruction-file coverage arriving without qualification.

**Scope creep, one instance, and it is the one that breaks the build.** The
design's Solution Architecture states: "Prose checks run on both arms, **above
the schema gate** so the 33 files currently emitting 'schema field missing,
skipping' are covered." The PRD lists this under **Out of Scope**: "*The
schema-gate coverage gap.* 33 of shirabe's 124 validator-visible files emit
'schema field missing, skipping' and run zero checks. Whatever ships does not see
them. Closing that gate is separate work." Decision 4 recommended it at Medium
confidence and said honestly that "R3 does not compel this ... the call is a
scope choice, not a finding." The design adopted the scope choice without
noticing it contradicts an explicit Out of Scope entry, without argument, and
without the fixture cost Decision 4 attached to it. This is also the single edit
that turns phase 3 red (criterion 4).

Two smaller elements serve no stated requirement and should be checked against
the author's intent rather than assumed: rejecting directories is R12a (fine),
but "the same change makes `check_claude_md_conventions` reachable" is also R12a
(fine) — no other creep found.

### 3. Internal consistency — FAIL

The four decisions mostly compose, and the design's closing paragraph on
mutual reinforcement is accurate as far as it goes. Three interactions are
broken or unaddressed.

**(a) D1 + D2 do not compose without a mechanism no decision owns.** Decision 2
raised this under the heading "The resolution problem, which no format solves"
and explicitly handed it off: "Worth surfacing for whichever Decision owns it,
because it changes the plan regardless of format." Nobody picked it up. The
facts, verified: `validate-docs.yml:74-77` builds from `.shirabe-src/` and then
runs `install -m 0755 ... /usr/local/bin/shirabe`, detaching the binary from its
source tree, so `current_exe()`-relative resolution lands in `/usr/local/bin/`.
The cwd is the *caller's* repo root, so `.shirabe-src/skills/writing-style/
rules.yaml` resolves only by accident of that one workflow, and not at all for a
local run, a pre-commit hook, or the parity harness (which runs the binary with
`current_dir` set to `tests/fixtures/golden/corpus`). Decision 1 named the fix —
"a flag on the reusable workflow's `shirabe validate` invocation plus an
environment variable plus an ancestor-walk fallback for local runs" — and noted
it clears R18 because a flag is not an install step. The design contains no flag,
no env var, no walk, and no mention that the question exists. R1, R2, R19 and
three acceptance criteria all sit on top of it.

**(b) There is no channel from the parsed rules to the check.** Verified:
`check_writing_style(doc: &Doc, _spec: &FormatSpec)` at `checks.rs:2572`, and
`Config` (`doc.rs:11-23`) carries `custom_statuses`, `visibility`,
`allow_untracked_acs` — no rule source, no vocabulary. The design specifies
`validate_file(doc, Option<&FormatSpec>, ...)` and a `run_prose_checks` family
that "read the parsed rule source and the resolved vocabulary" without saying
through what. Where the parse happens (once per run, or once per file), what
carries the result, and whether `Config` grows two fields are all unstated.

**(c) The CLAUDE.md-checking-its-own-vocabulary case is not addressed, though it
works.** The interaction is real and the design is silent on it. Decision 3
answered it empirically: the walk starts at the file's *parent directory* and
never inspects the file argument, so validating `<repo>/CLAUDE.md` reads
`<repo>/CLAUDE.md` (after `CLAUDE.local.md`) and finds its own declaration — "a
CLAUDE.md governs the checking of itself," and the report notes the declaration
line self-suppresses and adds a handful of words to the file's own frequency
denominator. The design's compressed description ("walk up from the file's
directory") happens to preserve the behavior, but a reader cannot tell whether
the design knows the case exists, and an implementer optimizing "start at the
file, not its parent" would break it. One sentence fixes this.

**(d) Rejecting directories interacts with nothing harmful**, confirmed: the
three documented consumers all compute their own file sets, and
`docs/guides/multi-consumer-cli-contract.md` plus `validate-docs.yml:84` both
commit to "the CLI never discovers files itself." Reject is the consistent call.

**(e) A live defect the None arm introduces, which no decision caught.**
`main.rs:604-607` uses `detect_format(basename(path))` as the *only* gate — there
is no `.md` extension test anywhere in the validate path. Removing the `continue`
(which every option requires) sends **every path the caller hands in** to
`parse_doc` and the prose checks. `validate-docs.yml:88-90` computes
`FILES=$(git diff --name-only --diff-filter=ACMR ...)` filtered only for
`evals|tests/fixtures`, so on shirabe's own self-caller — whose `paths:` filter
includes `crates/**` — a PR touching Rust source passes `.rs`, `.yml`, `.toml`
and `Cargo.lock` to the validator. After this change those files get parsed and
prose-checked; `crates/shirabe-validate/src/checks.rs` contains the literal words
`tier`, `robust`, `leverage`, `comprehensive`, `holistic`, `facilitate` and would
report itself. R3 says "any **Markdown** file the validator is handed"; the
design's None arm implements "any file." Decision 4's Option A carried an
explicit `.md` gate; Option B's write-up dropped it and the design inherited the
omission. Notices keep exit 0, so this is a correctness and noise defect rather
than a build break — unless a non-UTF-8 or unreadable path enters the set, where
`parse_doc`'s `Err` arm is a `ToolError` at exit 1.

### 4. Phasing soundness — FAIL

"Phased so each phase is independently reviewable and leaves the tree green" is
not true as written, and the reason is a fixture surface the design never
mentions. `crates/shirabe/tests/parity.rs:1-15` is a byte-match against a Go
baseline captured at a pinned commit, one `#[test]` per corpus file.

- **Phase 1 (rules to YAML, FC10 reads from it).** Green *only if* the
  resolution mechanism from criterion 3(a) lands in this phase, and the design
  does not say it exists. Unit tests are the sharpest case: `cargo test` runs
  with cwd at the crate root, so an FC10 that reads `skills/writing-style/
  rules.yaml` relative to cwd finds nothing and every FC10 test goes red. The
  `FC10_BANNED_WORDS` question the brief raises is the easy half — four
  references (`checks.rs:2551`, `:2563`, `:2576`, `:6086`), of which
  `checks.rs:6086` is the test `check_writing_style_detects_each_banned_word`
  iterating the constant. Deleting the constant is a compile error, the compiler
  enumerates the sites, and the phase can absorb it. The design should still say
  that the loop becomes an iteration over the parsed source, because that test is
  the AC's set-equality test in embryo.
- **Phase 2 (scoper + line numbers).** Green. `Doc { .. }` literals need the new
  field (Decision 4 counted ten: two production, eight test helpers) — compile
  errors, mechanical. No golden expectation contains an FC10 line
  (`grep -rn FC10 tests/fixtures/golden/expected/` returns nothing), and
  `annotation.rs:39-43` drops `err.line` from notices, so the R5 fix is
  baseline-invisible. **But** the design does not carry Decision 4's explicit
  warning: `mermaid.rs:158-215` mixes absolute and body-relative lines in one
  struct and `checks.rs:1044` depends on the body-relative reading, so
  retrofitting `Doc.body_start_line` into that module silently shifts FC08's
  slicing. "Do not touch mermaid.rs" is a design-level instruction that got
  dropped.
- **Phase 3 (optional FormatSpec, gate changes).** **Not green.** This phase
  carries the run-prose-above-the-schema-gate change, and
  `corpus/real/DESIGN-gha-doc-validation.md` is a schema-skipped fixture whose
  expected stdout is exactly one line
  (`::notice file=real/DESIGN-gha-doc-validation.md::schema field missing,
  skipping`, exit 0) and which contains `Tier` at line 161 — verified. It gains an
  FC10 notice and its parity test fails on a byte diff. Separately,
  `corpus/synthetic/README-unrecognized-format.md` is a fixture whose *prose
  documents the current defect as intended behavior* ("detect_format returns None
  and the validator skips it silently") against a 0-byte expected stdout; R3
  makes that fixture's text false even though its bytes survive this phase.
  Decision 4 measured all of this and said it "should be a named work item rather
  than an implementation surprise," and that the design should state that R3 is a
  deliberate post-port divergence so the parity contract is amended rather than
  quietly re-baselined. The design says nothing about fixtures, baselines, or the
  parity contract anywhere.
  On the brief's second question — shirabe's own CI does *not* go red from
  `skills/**` findings, for two reasons worth recording: prose findings land at
  notice level (`is_intrinsic_notice`, `validate.rs:83-98`) so exit stays 0, and
  `validate-shirabe-docs.yml` has no `skills/**` trigger. It goes red on the
  parity fixture instead.
- **Phase 4 (vocabulary).** Green.
- **Phase 5 (frequency rule).** **Not green.**
  `corpus/real/BRIEF-shirabe-strategy-skill.md` has 8 em dashes against a
  **0-byte expected stdout at exit 0**; `PRD-roadmap-skill.md` and
  `ROADMAP-strategic-pipeline.md` carry 3 each — all verified by count. Decision
  1 flagged this precisely ("any em dash rule that fires on it forces a
  recapture"). Whether they fire depends on the threshold and reporting unit the
  design declines to state, which is R7 and this phase colliding.
- **Phase 6 (skill reconciliation).** Green as scoped, but incomplete: it does
  not include the 12 repo-relative pointers (verified: 12 files say
  ``skills/writing-style/SKILL.md`` with no `${CLAUDE_PLUGIN_ROOT}` prefix,
  against 0 that use the prefixed form), which is the drafting-side half of R2
  and which Decision 2 explicitly warned "must not be forgotten in the plan." It
  also does not include the AC's new CI check for word-list-shaped literals under
  `crates/**` and `skills/**`, or the writing-style evals that CLAUDE.md requires
  whenever a skill is updated and that the AC requires as the R2 propagation
  test. Phase 6 rewrites `skills/writing-style/SKILL.md` and edits
  `skills/brief/references/phases/phase-4-validate.md`; Decision 2's own advice
  was to run the existing evals against the rewritten SKILL.md before merging,
  because degrading the drafting consumer is the cheapest risk in this design to
  falsify.

### 5. The 90-line claim — FAIL (overstated in one specific, load-bearing way)

What was actually measured, from Decision 1's empirical section: a standalone
Rust prototype at `.../tmp/d1/proto/src/main.rs`, line-oriented over
`Vec<String>` body lines, `regex` and `std` only, scoper delimited by
`PROSE-SCOPER-BEGIN`/`END` markers, `awk`-counted at **122 lines between markers,
90 non-comment non-blank**. Run over `docs/` (147 files) against Vale 3.17.1 with
a `scope: paragraph` occurrence rule: native `blocks_over_1=483` on 91 files
against Vale's 489 on 92 files. The measurement is real, reproducible, and the
right thing to have measured. Three problems with how the design states it.

- **"483 of 489 paragraph findings agree" is a per-file count comparison, not
  finding-level agreement.** The report's own table lists 12 files disagreeing;
  summed, the *gross* disagreement is 14 findings (net -6), so common findings
  are at most ~475, not 483. Finding-level identity was demonstrated only on the
  three hand-built fixtures, not on the corpus.
- **"the disagreements are cases where the native scoper is right" (Consequences)
  is not supported by the source.** The report attributes exactly *one*
  disagreement to Vale being wrong —
  `DESIGN-shirabe-check-absorption.md:395`, a table row R4 forbids — and
  attributes the other 11 files to "block-segmentation edge cases in nested
  lists," taking no position on which is right. In four of those files the native
  scoper produces *more* findings than Vale, not fewer. The design converted an
  unadjudicated segmentation difference into a claim of correctness. This is the
  one place the design overstates its evidence, and it does so in the sentence
  that is supposed to mitigate the design's own headline risk.
- **The arithmetic is quietly in tension and the design does not reconcile it.**
  Vale's 489 include 13 findings the report audits as R4 violations (11
  frontmatter block scalars, 2 table rows). If the native scoper correctly drops
  all 13, the count should fall by 13; it falls by 6, meaning the scoper adds ~7
  findings of its own from segmentation. Both facts are in the report; only the
  flattering half reaches the design.

On whether 90 lines covers the edge cases the design claims: yes for the ones
named — fenced blocks (both delimiters, indent tracking), indented code, HTML
comments, GFM table rows, inline code, link destinations, autolinks, bare URLs,
headings kept. Frontmatter exclusion is free because the prototype reads
`Doc.body`, which is already stripped. What 90 lines does **not** cover, per the
report's own Confidence section, is setext headings, reference-style links, and
raw HTML blocks — "constructs this corpus barely uses and a future one might."
The report names that as the residual risk of its own recommendation. The design
keeps the "90 lines" number and drops the caveat, then tells the reader in
Consequences that the scoper "is the most likely place for a future correctness
bug" without saying where. Naming the three unhandled constructs costs one
sentence and converts a vague warning into a test list.

### 6. Missing architecture — FAIL

What a competent implementer still does not know:

1. **How the validator finds `rules.yaml`.** Criterion 3(a). This is the largest
   gap in the document and it blocks phase 1.
2. **The `rules.yaml` schema.** Not showing it is a gap here specifically because
   the design leans on the schema to discharge R7 ("satisfying R7 by
   construction") and on per-rule prose to discharge R2's drafting half ("the
   drafting consumer gets better material than the comma-jammed table rows it
   reads today"). Both claims are unverifiable without the shape. Decision 2
   established the four distinct rule shapes the SKILL.md actually contains — a
   comma-list word table, quoted-literal substitution tables, mixed
   literal/prose/parenthetical tables, and em-dash-separated bullet lists — plus
   three encoding problems a flat schema cannot absorb: `landscape (fig.)` needs
   a qualifier field, `align with` is a two-word entry that a token-based
   rewrite would break, and the seven Adverb openers are position-scoped by a
   capitalization convention no parser can read as semantics. A schema sketch of
   ten lines showing one word rule, one qualified rule, one position-scoped rule
   and one frequency rule would close this. Ten to twenty lines is enough; the
   full file is the implementer's.
3. **Which check code(s) the prose family emits.** The design says "prose check
   family ... plus at least one frequency rule," which reads as several checks,
   and never names a code. R14 requires exactly one emittable prose code, and
   this is the design's to settle: is the em dash rule FC10, or a new code, and
   if new, how does R14 survive? Consequences implies FC10 is reused ("the check
   code keeps a name that no longer describes what it does") but that is an
   inference. This also blocks R13's registration obligation.
4. **Behavior when `rules.yaml` is malformed or missing.** Unspecified, and the
   answer is not obvious: fail closed (tool error, exit 1) is defensible for
   shirabe's own committed file, and fail open (skip prose checks) reproduces
   exactly the silent-success failure mode the design's own Decision Drivers name
   as "worse than the gap it closes." The design's driver picks the answer; the
   design should write it down. Note this is a *shirabe-owned* file, so it is not
   an adopter-input question, which makes fail-closed cheap.
5. **Vocabulary/frequency interaction.** The brief is right that a suppressed
   term cannot affect em dash density. The specification that *is* missing is the
   denominator's relationship to suppression: does a suppressed term still count
   toward `prose-words`? (It must, or an adopter's declaration silently inflates
   every rate.) And the general form matters more than this instance — the design
   introduces a rule family where some rules are term-based and suppressible and
   others are rate-based and not, and it never states that vocabulary applies to
   the former only. One sentence.
6. **The `.md` gate on the None arm.** Criterion 3(e).
7. **Fixture and parity-contract handling.** Criterion 4. Three named fixtures
   and a frozen Go baseline whose stated job is byte-matching.
8. **The `mermaid.rs` hazard when `Doc.body_start_line` lands.** Criterion 4.

Two smaller omissions worth folding in: the design's four `wip/...` report
references (lines 79, 126, 148, 176) violate the workspace wip-hygiene rule —
`wip/` paths must not be referenced from a committed final artifact, and public
CI greps for exactly this — and the design never records that `shirabe validate`
is a public-repo artifact whose vocabulary header is adopter-controlled input at
*parse* time as well as match time (Security Considerations covers the match-time
half well; the size cap is mentioned but the parse-time behavior on a malformed
header is not, though the existing `parse_visibility_header` precedent of
skipping unrecognized values answers it).

---

## Requirements traceability map

| requirement | design element | status |
|---|---|---|
| R1 single source, enforcement-time | Solution Architecture "Rule source"; phase 1 | PARTIAL — no resolution mechanism, so the AC's no-rebuild test is unevaluable |
| R2 both consumers, same commit | Decision Outcome ("read at enforcement time ... pointed at by the writing-style skill") | PARTIAL — no skill-side path (`${CLAUDE_PLUGIN_ROOT}`), 12 broken repo-relative pointers unaddressed |
| R3 instruction-file coverage | Decision 4 Option B; Dispatch; phase 3 | PARTIAL — no `.md` gate, so the None arm takes every file the caller passes |
| R4 prose scoping | "Prose scoper" (~90 lines) | PASS |
| R5 accurate locations | `Doc` gains body start line; phase 2 | PASS — but `mermaid.rs` hazard undisclosed |
| R6 frequency rules | "at least one frequency rule evaluating a rate against a threshold"; phase 5 | PASS |
| R7 frequency rule shape stated | rules.yaml carries four fields; phase 5 "with its four recorded values" | **FAIL** — none of the four values is stated; PRD delegated this decision to the DESIGN by name; documentation surface unnamed |
| R8 per-repo vocabulary | Decision 3: case-insensitive whole-term, `tier` not `tiered` | PASS |
| R9 vocabulary extends, never replaces | none | **FAIL** — no element; the report's enabling rule (unknown declared terms are not an error, else a rule *removal* breaks every declaring repo) is absent |
| R10 vocabulary repo-local | per-file ancestor walk; "a global flag or a single config load fails that test" | PASS |
| R11 non-breaking arrival | phase 5 "notice-level" | PASS — weakened by the unstated threshold |
| R12 promotion condition filed | phase 5 "file the promotion issue R12 requires before the check merges" | PASS |
| R12a gate must not report false success | directory rejection; FC-CONVENTIONS reachable; Decision 4 | PASS |
| R13 no silent registration | phase 6 corrects the two stale `FC01`-`FC13` copies | PARTIAL — registration-list test absent; conditional half untraceable while R14 is unanswered |
| R14 exactly one prose check code | none | **FAIL** — the design never names the code(s) the prose family emits |
| R15 retirement non-breaking | none | **FAIL** — vacuous under the extend decision, but must be recorded as vacuous, not omitted |
| R16 resolvable by every consumer | validator path only | **FAIL** — drafting-skill and local/pre-commit resolution unaddressed, and it is Decision 3's stated deciding argument |
| R17 day-zero behavior | "an absent header means the empty set, which is R17 verbatim" | PASS |
| R18 no new adopter dependency | Decision Drivers; Decision 1 rejection of Vale | PASS |
| R19 no version skew on CI path | none | **FAIL** — depends entirely on the unowned resolution mechanism; AC requires a CI log showing rules and binary at the same SHA |
| R20 no adopter workflow edit | Consequences ("no workflow edit and no new dependency") | PARTIAL — second clause (document that instruction-file coverage needs an adopter-side PR) absent |
| — | prose checks run **above the schema gate**, covering the 33 schema-skipped files | **SCOPE CREEP** — PRD lists this under Out of Scope; adopted without argument; it is the edit that breaks the phase-3 fixture |

## Strawman audit

| rejected option | design's reason | source report's reason | flattened? |
|---|---|---|---|
| D1-A Vale | R18 forbids outright; R3 exits 2 with zero findings on shirabe's own tree; R4/R6 mutually exclusive (metric has no punctuation var, script sees whole doc only at `scope: raw`) | Identical three, same order, plus: Vocab is the right shape and B should copy it; the R4-vs-raw gap is threshold-dependent "and should not be overstated"; gh/git precedent argued both ways; Tengo panic on out-of-range span | **No.** Strongest section in the design. Minor drops (gh/git both sides; explicit credit to Vale's Vocab design) do not weaken the rejection |
| D1-C split | "doubles the rule-source problem it is meant to help ... R1 and R2 exist to stop exactly that" | Same, plus **the option's one honest argument**: Vale's first-party Claude Code plugin with edit-time hook and LSP, "real, already built, and shirabe has no equivalent," answered by "an authoring aid is not an enforcement engine; nothing in B forecloses it" | **Yes.** The only genuine strength of the option is absent |
| D2-A parse SKILL.md tables | third column drops four rules and exits 0; prose files are editable by anyone; cannot carry R7's four values | Same, plus: four distinct extractors needed not one; 47-vs-48 term ambiguity the format forces; `landscape (fig.)`, `align with`, and capitalization-as-semantics; and the mitigation advice — run the existing evals against the rewritten SKILL.md before merging, since degrading the drafting consumer is the cheapest risk here to falsify | Partially. Reason survives; the falsification instruction addressed to the design is dropped |
| D2-B data file + prose reference | "splits one concept across two files" | "C plus a derived duplicate": either the prose restatement is a fourth copy R1 forbids, or the generated file drifts and needs a regenerate-and-diff CI job | Mild. Direction right, force lost |
| D2-D rules in SKILL.md frontmatter | "puts a growing data structure in a position readers expect to be short" | Frontmatter schema is **Claude Code's**, not shirabe's; zero precedent across 20 skills; a load failure takes 12 downstream skills; settled by a 20-minute test the report asks the design to run or to argue past | **Yes.** A stylistic objection substituted for a stated failure mode with a blast radius |
| D3-B header naming a path | "one indirection more than the problem needs at shirabe's scale of two terms" | **Dangling pointer**: a header naming a missing file yields full day-zero firing while the repo believes it declared, inheriting an FC-CONVENTIONS-style validation obligation; and the drafting agent gets the pointer free but not the terms, which is the R16 split | **Yes.** Half of reason one resurfaces in Security Considerations; reason two — the report's "sharpest R16 differentiator" — never appears |
| D3-C dotfile | "introduces a config-file concept shirabe has deliberately never had" | Same, plus a new dependency (no `toml`, no `serde` in the workspace), plus the R10 trap (fails immediately if written as load-config-once), **minus** the concession that a structured file is "the strongest forward-looking argument any option has" | **Yes**, on the dropped concession |
| D3-D fixed conventional path | folded into the same sentence as C | Config-file concept *and* an invisible convention; splits "where does a repo declare things to shirabe" into two uncross-referenced places; worst discoverability, which R17's framing cannot tolerate | Mild |
| D4-A prose pseudo-format | leaves the invariant to a sentinel someone must remember; "eighteenth registration touchpoint" on a surface where six of seventeen already fail silently | Same, plus two mechanical failures: the sentinel cannot live in `formats()` without leaking into lifecycle/transition/finalize, and the schema gate misfires on a non-artifact `.md` carrying a `schema:` field | Mild. Design keeps the decisive reason |
| D4-C separate prose pass | "moves check dispatch out of the library, so a library consumer silently loses prose checking" | Same, plus output reordering as a latent parity hazard, plus the fact that C still requires B's edit to `validate.rs:208-210` or prose double-fires | Mild |

## Required changes

Blocking, in the order I would fix them.

1. **State R7's four values.** Threshold, denominator, reporting unit, and the
   line a document-level finding carries — as numbers and names in the design
   body, not as schema slots. The PRD assigned this decision to the design
   explicitly. Name `docs/guides/multi-consumer-cli-contract.md` as the recording
   surface the AC requires. Carry the consequence: the report measured that the
   raw-versus-prose scoping gap flips 0 verdicts at 3/1000 and 6-11 files at
   10-15/1000, so the chosen threshold is what makes the design's own R4/R6
   driver true or vacuous.
2. **Specify how the rule source is resolved**, in all four consumer positions:
   CI (binary at `/usr/local/bin`, source at `.shirabe-src/`), a local run, the
   pre-commit hook, and `cargo test` (cwd at the crate root; the parity harness
   sets cwd to `tests/fixtures/golden/corpus`). Decision 1's answer — a flag on
   the reusable workflow's invocation, an env var, and an ancestor-walk fallback
   — is the material; state that a flag is not an install step so R18's AC is
   safe. Add R19 and its "same commit SHA in the CI log" AC to the same section.
   Nothing in phase 1 can land without this.
3. **Resolve the scope conflict on the schema gate.** The PRD puts the 33
   schema-skipped files out of scope; the design covers them. Either drop the
   above-the-gate placement, or state plainly that the design expands the PRD's
   boundary, why R12a's principle justifies it, and what it costs — which is
   item 4. Do not leave it as an unremarked line in Solution Architecture.
4. **Add fixture and parity handling to the phase plan.** Name the three
   fixtures: `corpus/real/DESIGN-gha-doc-validation.md` (schema-skipped, contains
   `Tier` at line 161, expected stdout is one SCHEMA notice — moves in phase 3),
   `corpus/real/BRIEF-shirabe-strategy-skill.md` (8 em dashes, 0-byte expected
   stdout, exit 0 — moves in phase 5, as do `PRD-roadmap-skill.md` and
   `ROADMAP-strategic-pipeline.md` at 3 each), and
   `corpus/synthetic/README-unrecognized-format.md`, whose prose documents the
   defect as intended behavior. State how the frozen Go parity contract is
   amended — move the affected fixtures to a Rust-owned expectation set, or add a
   documented exemption — rather than re-baselining silently. Without this,
   phases 3 and 5 do not leave the tree green and the design's phasing claim is
   false.
5. **Answer R14: name the check code.** One code or several, which one, and how
   "exactly one prose check code" holds once the frequency rule exists. Then
   discharge R13's conditional half against that answer, including the AC's
   registration-list test.
6. **Add the `.md` gate to the None arm**, and say what happens to a
   non-Markdown path the caller passes. `validate-docs.yml` passes the whole
   changed-file set, so this is live on shirabe's own self-caller today.
7. **Specify malformed/missing `rules.yaml` behavior.** The design's own
   "silent success is the failure mode" driver picks fail-closed; write it down.
8. **Cover R16, R9, R15, R20's second clause, and R2's skill-side path.** For
   R16, state how a drafting skill and a local run resolve the vocabulary — for
   the header this is nearly free (CLAUDE.md is already in the agent's context,
   which is Decision 3's deciding argument and belongs in the design). For R9,
   state that unknown declared terms are not an error, and why: erroring breaks
   R9 the moment shirabe *removes* a word. For R15, one sentence recording that
   nothing is retired. For R20, one sentence that adopter instruction-file
   coverage needs a PR per adopter.
9. **Add the missing phase-6 work items:** the 12 repo-relative
   `skills/writing-style/SKILL.md` pointers (verified: 12 unprefixed, 0
   plugin-rooted), the AC's CI check for word-list-shaped literals under
   `crates/**` and `skills/**`, and the writing-style evals — both because
   CLAUDE.md requires evals whenever a skill is updated and because the AC's
   propagation test is an eval. Decision 2's advice to run the existing evals
   against the rewritten SKILL.md before merging belongs in the phase.
10. **Fix the two overstatements.** In Consequences, "the disagreements are cases
    where the native scoper is right" is not supported — the source attributes
    one disagreement to Vale violating R4 and eleven files to unadjudicated
    nested-list segmentation, four of them with the native scoper finding *more*.
    State the agreement as what was measured (per-file counts, 483 against 489
    over 147 files, 14 findings of gross disagreement across 12 files). And name
    the three constructs 90 lines does not handle — setext headings,
    reference-style links, raw HTML blocks — which the source names as the
    residual risk of its own recommendation and which converts the design's vague
    "most likely place for a future correctness bug" into a test list.
11. **Non-blocking but fix before merge:** the four `wip/...` report references at
    lines 79, 126, 148, 176 violate the workspace wip-hygiene rule and the public
    CI grep. Also add one sentence on the CLAUDE.md-checks-its-own-vocabulary
    case — the walk starts at the file's parent directory, so a CLAUDE.md
    governs the checking of itself and its declaration line self-suppresses —
    and one on `mermaid.rs`: do not retrofit `Doc.body_start_line` into it,
    because `BlockLocation.body_start` mixes conventions and `checks.rs:1044`
    depends on the body-relative reading.
