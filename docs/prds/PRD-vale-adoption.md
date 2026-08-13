---
schema: prd/v1
status: Draft
problem: |
  shirabe's writing-style rulebook exists in three divergent copies, only one
  of which is mechanical. That copy checks seven words, never sees the
  instruction files that shape every agent run, reports line numbers offset by
  the frontmatter length, and matches inside code fences and URLs. The rules it
  does enforce are the ones a drafting model already obeys, while the defect
  that recurs measurably in the corpus, document-level frequency, is one no
  copy of the rulebook can express.
goals: |
  One rule source that every enforcing surface reads, checking both prose
  surfaces shirabe governs, expressing the frequency properties a drafting
  model cannot observe in itself, letting any adopting repo declare its own
  terms of art without detaching from shirabe's rules, and arriving in adopter
  repos without breaking their builds on the day it lands.
upstream: docs/briefs/BRIEF-vale-adoption.md
motivating_context: |
  An exploration measured shirabe's corpus rather than reasoning about it and
  inverted its own premise: mechanical prose checking already ships, and
  widening its word list would buy almost nothing. What no surface covers is
  frequency, and what nothing reaches is the instruction files.
---

## Status

Draft

Requirements only. The mechanism stays open for the DESIGN, which inherits
three architectural alternatives the exploration left live.

## Problem Statement

shirabe governs prose on two surfaces and governs neither consistently. It
ships a writing-style rulebook that its skills apply while drafting, and a
validator that checks the artifacts those skills produce. The two disagree
about what the rules are.

The rules live in `skills/writing-style/SKILL.md`: 47 banned words across five
categories, plus phrase patterns, structural patterns, formatting tells,
over-formality substitutions, and four cognitive tells. Two further copies
exist inside the repo, a seven-word constant behind the validator's FC10 check
and a five-word instruction inside the BRIEF jury's structural reviewer. The
design that specified FC10 required the validator read the list from the
SKILL.md at validate time so updates would propagate; the shipped code
hardcodes it.

Three things follow, and each is a separate defect.

The mechanical copy sees the wrong files. `detect_format` prefix-matches eight
artifact types, so `shirabe validate` returns "All checks passed" on every
SKILL.md, CLAUDE.md, AGENTS.md, and README.md handed to it. Counted raw, it
reads 440,003 words under `docs/` and skips about 225,000, of which 197,538 are
the 211 files under `skills/`. The gap is not mainly volume. The skipped files
are the instructions that shape every future agent run, so a defect there
propagates into the prose the checked surface is judged on.

The rules it does enforce are the ones already obeyed. The phrase apparatus
produces roughly two true positives across 554,000 words of `docs/` and
`skills/` prose. On `docs/` alone, 397,000 prose words, raw word-rule precision
measures 1.7%, rising to about 16% once domain terms and the one document that
quotes the rulebook are excluded. In that run, over all 47 words and 290 total
alerts, the two highest-volume matches are shirabe's own terms of art:
`tier`/`tiers`/`tiered` at 147 because Tier 1-4 is its decision vocabulary, and
`journey` at 112 because `## User Journeys` is a required heading in its own
BRIEF format. A banned word list fires hardest against the repo that wrote it,
and every adopter has equivalent collisions with no way to declare them.

The defect that does recur is one no copy can express. Counting body prose
only, em dashes run 3,114 in `docs/` and 1,188 in `skills/`. In `docs/` that is
7.84 per thousand words, with 72% of files above 3 per thousand and the worst
at 28.5; `skills/` runs a comparable 7.59 with 36% of files above 3. Frequency
is a document-level property, so a model composing one sentence cannot see it,
and no check in the validator counts occurrences or computes a rate against a
threshold. Bold density and sentence-length uniformity have the same shape.

## Goals

A single rule source that the validator and the drafting skills both read, so
a rule edit takes effect everywhere without a second copy to keep in sync.

Checking that covers both surfaces shirabe governs: the artifacts its skills
draft, and the instruction files that tell those skills what to do.

Rules that express document-level frequency, because that is the defect class
self-review structurally cannot reach.

A way for any adopting repo to declare its own terms of art, so precision does
not depend on shirabe's vocabulary happening to match theirs.

Arrival in adopter repos that does not break their builds. Adopters pin the
reusable workflow at `@main`, so whatever merges reaches koto, niwa, and tsuku
on their next docs PR with no action from them.

## User Stories

**As a shirabe maintainer editing a prose rule,** I want the edit to take
effect everywhere the rule is enforced, so that I don't have to find three
copies and hope I found them all.

**As a shirabe skill author editing `skills/execute/SKILL.md`,** I want prose
findings on the file I'm editing, so that the instructions shaping every agent
run get the same scrutiny as the artifacts those runs produce.

**As a drafting skill at its validate phase,** I want findings that name the
document-level properties I couldn't observe while composing, so that I revise
on information I didn't already have.

**As a maintainer of a repo that adopts shirabe,** I want to declare the words
my project uses as terms of art, so that the checking stops firing on them
without my having to disable it or fork the rulebook.

**As a maintainer of an adopting repo on the day this ships,** I want my builds
to keep passing, so that a capability I didn't ask for doesn't block my merges.

## Requirements

### Functional

**R1. Single rule source, read at enforcement time.** The writing-style rules
SHALL have exactly one authoritative representation in the repository, and
every enforcing surface SHALL read from it **at enforcement time** rather than
restating it or embedding a copy at build time. The three current copies SHALL
be reduced to that one source plus references to it.

The build-time clause is load-bearing and not pedantry. A build script that
reads the source at compile time and bakes a constant into the binary would
satisfy a requirement phrased only as "exactly one authoritative
representation", while reproducing the exact defect this PRD opens with: the
design that specified FC10 required the validator read the list at validate
time so updates would propagate, and the shipped code hardcodes it.

**R2. Both consumers read the same file at the same commit.** The validator and
the drafting skills SHALL each read the same rule file at the same commit,
reached through whichever root that consumer already uses: `.shirabe-src/` for
the validator in CI, the plugin root for a drafting skill, the repository
checkout for a local run. Identical path strings are not required and would
forbid the natural design. What is required is that no consumer can be
enforcing a different rule set than another at the same commit. A source
honored by only one consumer does not satisfy R1.

**R3. Instruction-file coverage.** `shirabe validate <file>` SHALL produce
prose findings by default for files that are not artifact-prefixed. The class
is defined by exclusion rather than by an allow-list: any Markdown file the
validator is handed that carries no artifact prefix is in scope, which covers
SKILL.md, CLAUDE.md, AGENTS.md, README.md, and their `.local.md` variants.
Prose checks and prose checks only apply to these; the structural checks that
presuppose an artifact schema SHALL NOT fire on them. The current format gate
returns "All checks passed" for every file in this class.

**R4. Prose scoping.** Findings SHALL be reported against prose only. Matches
inside fenced code blocks, inline code spans, URLs, table rows, and frontmatter
SHALL NOT be reported. Headings ARE prose for this purpose and SHALL be
included in both findings and any frequency denominator. That ruling is
required here rather than left open because it moves the corpus figure: 3,114
em dashes in `docs/` counting headings, against 2,785 counting body paragraphs
alone, and the measurement is not reproducible without knowing which was meant.
This is a stated requirement rather than an implementation detail, because a
frequency measurement that counts code fences is not the measurement the author
is being asked to act on.

**R5. Accurate locations.** A finding SHALL carry the line number of the
occurrence in the file as the author sees it. The current check reports
body-relative numbers offset by the frontmatter length: on this PRD it reports
line 38 for an occurrence at line 62, against a 24-line frontmatter. The
corrupted value reaches the `line` field of the `--format json` envelope, which
is what a machine consumer parses. It does not reach CI annotations, because
`--format annotation` emits `file=` with no `line=` attribute at all, so those
annotations point at a file rather than at a wrong line.

**R6. Frequency rules.** The checking SHALL express at least one rule that
evaluates a rate or count against a threshold rather than the presence or
absence of a pattern. Em dash density is the first such rule. This is a new
check shape for shirabe; no existing check counts occurrences or computes a
rate.

**R7. Frequency rule shape SHALL be stated.** For each frequency rule the
implementation SHALL define, and the documentation SHALL record: the
denominator, the reporting unit, the line a document-level finding carries, and
the threshold value. These are not implementation freedoms. The reporting unit
alone varies annotation volume on shirabe's corpus by roughly thirty times
between per-occurrence and per-document.

**R8. Per-repo vocabulary declaration.** A repository SHALL be able to declare
terms of art that the rules do not fire on. The declaration SHALL be
term-scoped, suppressing named terms while leaving every other rule active. It
SHALL NOT be rule-scoped: suppressing `tier` must not disable the word rules
and cost the repo the other 46 terms.

Matching SHALL be case-insensitive, so a declared `tier` suppresses `Tier`.
Matching SHALL NOT extend to morphological variants: a declared `tier` does not
suppress `tiered`, which is a separate entry on the rule list and a term a repo
may legitimately want flagged while using `Tier 1-4` as vocabulary. A repo
wanting both declares both.

**R9. Vocabulary extends, never replaces.** A repository's declaration SHALL
extend shirabe's rules rather than substitute for them. A repo that declares
terms SHALL continue to receive later rule additions, corrections, and removals
with no action on its part. This deliberately diverges from `--custom-statuses`,
shirabe's only existing adopter-supplied list, which is documented and tested as
replace.

**R10. Vocabulary is repo-local.** shirabe's own `tier` and `journey` SHALL be
declared through the same mechanism an adopter uses, not shipped as built-in
exemptions. A term suppressed in one repository SHALL NOT be suppressed in
another.

**R11. Non-breaking arrival.** A rule SHALL ship, on the release that
introduces it, at a severity that does not fail an adopter's build. Notice
level satisfies this. Draft-tolerable does not, for the first release only, and
the reason is recorded in the decisions below: it depends on a workflow change
every adopter inherits at `@main`. This requirement binds the introducing
release; promotion afterwards is R12's business. The measured
impact is threshold-contingent and the threshold is R7's to fix, so the range
is what binds: at 3 em dashes per thousand words, error level would fail 92 of
shirabe's 124 validator-visible docs, 47% of koto's corpus, 49% of niwa's, and
20% of tsuku's. At 15 per thousand it is 11 of 124. No threshold in the
plausible range brings the day-one failure count to zero, and all three
adopters would see the result the day it merged.

**R12. Promotion condition is an artifact.** A rule shipped below error level
SHALL have its promotion precondition recorded as a filed, tracked issue with a
measurable condition, not as a code comment. The condition SHALL be a stated
number rather than "the corpus is clean." Nine check codes currently sit at
notice level behind a comment promising a cleanup PR; no such PR or issue
exists for any of them, and no code has been promoted out of the notice set.

**R13. No silent registration.** If a check code is added, it SHALL be
registered in every list that gates it. R14 makes the addition conditional; the
stale-prose obligation below is unconditional. Six of the seventeen current
registration touchpoints fail silently when missed.

Independently of whether a code is added, the two stale prose copies SHALL be
corrected: the help text in `crates/shirabe/src/main.rs` and
`docs/guides/multi-consumer-cli-contract.md` both say `FC01`-`FC13` against a
registry of `FC01`-`FC16`.

**R14. Exactly one prose check code.** Exactly one check code SHALL be
emittable for the writing-style rules. The capability SHALL NOT leave two
overlapping prose checks registered, whether by adding a code beside the
existing one or by leaving a superseded code emitting. This is the success
condition for the extend-not-retire decision.

**R15. Retirement, if a later change chooses it, SHALL be non-breaking.** This
requirement constrains a path R14's decision does not take; it is stated
because R14 forecloses retirement for this capability, not for all time.
Retiring a check code SHALL NOT turn a previously valid `--check <code>`
invocation into a tool error, and the code SHALL remain selectable as a no-op
for at least one release. Retirement SHALL also state whether removing a code
from the emittable set is additive to `shirabe-validate/v1` or requires a
version bump, because the contract document versions the envelope shape and is
silent on the code vocabulary. No deprecation path exists today and neither
question is answered anywhere in the repository.

**R16. The vocabulary declaration is resolvable by every enforcing consumer.**
The declaration SHALL be resolvable from the file being checked, by the
validator, by a drafting skill, and by a local or pre-commit run, without CI
wiring. A declaration honored only in CI does not satisfy R8: it would leave
the drafting agent firing on terms the validator has been told to ignore, which
is the same split R2 exists to close for the rule source.

**R17. Day-zero behavior is stated.** A repository that has declared no
vocabulary SHALL receive findings for every term on the rule list, including
any that are its own terms of art. Nothing is suppressed by default and no
allowance is made for a repository that has not configured itself. This is
recorded rather than
mitigated: on `docs/` the measurements put raw word-rule precision at 1.7%,
rising to about 16% once domain terms and the one document that quotes the
rulebook are excluded, so the declaration does most of the precision work and
every adopter begins without one. R11 keeps that from
failing a build; it does not make the findings worth reading. Writing a
declaration is an adopting repository's first action, and the documentation
SHALL say so.

### Non-functional

**R18. No new runtime dependency for adopters.** The capability SHALL NOT
require an adopting repository's CI to install or fetch anything it does not
install today. The reusable workflow already checks out the shirabe repo at the
called ref and builds from source, so any rule file committed to shirabe is
already present on the runner at the exact commit that produced the binary.

**R19. Version skew SHALL be structurally impossible on the CI path.** The
rules and the enforcement SHALL originate from the same ref. The CI binary is
version-anonymous today, so a requirement phrased as a version compatibility
assertion has nothing to compare against.

**R20. Adopters SHALL need no workflow edit for artifact coverage.** A
capability scoped to the paths adopters already filter on SHALL reach them with
no change to their caller workflows. Coverage of instruction files outside
those filters SHALL be documented as requiring an adopter-side change, because
all three callers filter `paths: ['docs/**']` and shirabe cannot widen that
from its side.

## Acceptance Criteria

- [ ] The writing-style rules exist in exactly one file. `FC10_BANNED_WORDS` in
      `crates/shirabe-validate/src/checks.rs` and the inline word list in
      `skills/brief/references/phases/phase-4-validate.md` are replaced by
      references to that file's path.
- [ ] A CI check fails when a word-list-shaped literal, three or more entries
      drawn from the rule source, appears anywhere under `crates/**` or
      `skills/**` outside the rule source itself and
      `skills/writing-style/evals/`.
- [ ] Appending a sentinel term to the rule source causes `shirabe validate` to
      report it on a fixture containing that term, with no other file edited and
      without rebuilding the binary. A rebuild passing this criterion while an
      un-rebuilt binary fails it means the rules are embedded at build time,
      which R1 forbids.
- [ ] The rule set the validator applies at runtime is set-equal to the rule set
      parsed from the source file; a test asserts the equality and names the
      count.
- [ ] The same added rule is honored by a drafting skill without a second edit,
      verified by a skill eval under `skills/writing-style/evals/` run through
      `scripts/run-evals.sh`.
- [ ] For each of a fixture SKILL.md, CLAUDE.md, AGENTS.md, and README.md
      containing a known rule violation, `shirabe validate` reports at least one
      prose finding naming the violation. All four return "All checks passed" at
      exit 0 today.
- [ ] Running the same invocation over an artifact-prefixed file produces the
      finding set it produced before instruction-file coverage was added.
- [ ] A banned word inside a fenced code block, an inline code span, a URL, and
      YAML frontmatter produces no finding; the same word in prose produces one.
- [ ] Under `--format json`, a finding's `line` equals the line the author sees,
      verified on a fixture with frontmatter and on one without. Today a
      24-line-frontmatter file reports 38 for an occurrence at 62.
- [ ] `docs/guides/multi-consumer-cli-contract.md` records, for the em dash
      density rule, all four of denominator, reporting unit, threshold value,
      and the line number a document-level finding carries.
- [ ] A fixture whose density exceeds the recorded threshold produces exactly
      one finding per recorded reporting unit; a fixture below it produces none.
      The test reads the threshold from the recorded value rather than
      hardcoding it.
- [ ] A repository declaring `tier` receives no `tier` findings, still receives
      findings for every other rule, and still receives `tiered` findings.
- [ ] In a single invocation spanning files from shirabe and from another
      repository, a term declared in shirabe suppresses that term in shirabe's
      files and does not suppress it in the other repository's.
- [ ] Adding a rule to the source after a repository has declared its
      vocabulary causes that repository to receive the new rule with no edit to
      its declaration.
- [ ] Running the full check over shirabe, koto, niwa, and tsuku at the shipped
      severity produces exit code 0 in all four.
- [ ] `docs/guides/multi-consumer-cli-contract.md` contains, for each rule this
      change ships below error level, a `tsukumogami/shirabe#<n>` reference.
      Each referenced issue is open and its body states a numeric promotion
      condition. Scoped to rules this change introduces; the nine pre-existing
      notice-level codes in `is_intrinsic_notice`
      (`crates/shirabe-validate/src/validate.rs:83-98`) are out of scope.
- [ ] `--check <code>` exits 0 for every code `is_known_check_code` accepts, and
      every code named in `docs/guides/multi-consumer-cli-contract.md` is
      accepted by `is_known_check_code`. A code retired as a no-op is accepted
      and produces zero findings.
- [ ] The check-code ranges in the `crates/shirabe/src/main.rs` help text and in
      `docs/guides/multi-consumer-cli-contract.md` agree with the
      `is_known_check_code` match in `crates/shirabe-validate/src/validate.rs`.
      Today both prose copies say `FC01`-`FC13` against a registry of
      `FC01`-`FC16`.
- [ ] A test asserts every code `is_known_check_code` accepts also appears in
      each registration list that gates it, so a newly added code cannot be
      missing from one of them silently.
- [ ] Exactly one check code emits writing-style findings; validating a document
      containing a banned word in prose produces findings under one code, not
      two.
- [ ] A vocabulary declaration is honored by `shirabe validate` run locally with
      no CI environment present, on the same file, with the same result CI
      produces.
- [ ] The reusable workflow's diff against its pre-change version adds no
      install, fetch, download, or package-manager step.
- [ ] A CI run's log shows the rule source and the validator binary resolving
      from the same commit SHA.
- [ ] An adopter caller workflow left byte-for-byte unchanged produces prose
      findings on a PR touching `docs/**`.
- [ ] The documentation states that a repository with no vocabulary declaration
      receives the unsuppressed rate, and names writing a declaration as the
      first adopter action.

## Out of Scope

- **Choosing the mechanism.** Whether the checking is an external linter, a
  widened native check, a Claude Code hook, a CI job, or a combination is the
  DESIGN's decision. The exploration left three alternatives live.
- **Detecting cognitive tells.** Low information density, empty conclusions,
  unresolved demonstratives, and uncited attribution stay with model judgment
  and the jury reviewers. A fluent, entirely vacuous document produced ten
  alerts under three off-the-shelf style packages and none concerned the
  vacuity.
- **An adopter-facing add-banned-terms direction.** The vocabulary declaration
  suppresses; it does not let a repo extend the rule set with its own bans.
  That is a different product claim and it can be added later without
  invalidating this one.
- **Adopter-side per-rule rejection.** An adopting repo cannot switch off an
  individual rule it disagrees with. Its coarse lever remains declining to call
  the reusable workflow. This is stated rather than left silent because the
  frequency rules are the ones an adopter is most likely to reject on
  principle, and silence would read as a promise the vocabulary knob cannot
  keep.
- **Rewriting the rules themselves.** Their content is settled; only where they
  live and what enforces them is in question.
- **Cleaning any corpus.** Bringing shirabe's 3,114 em dashes under a threshold
  is follow-on work tracked by the R12 issue. Adopter corpora are their
  maintainers' business.
- **Widening adopter caller workflows.** shirabe cannot change the
  `paths: ['docs/**']` filter in koto, niwa, or tsuku. Instruction-file
  coverage in those repos requires a PR to each.
- **The schema-gate coverage gap.** 33 of shirabe's 124 validator-visible files
  emit "schema field missing, skipping" and run zero checks. Whatever ships does
  not see them. Closing that gate is separate work.
- **Prose in commit messages, issue bodies, and PR descriptions.** That prose
  does not land on disk in a checkable location.
- **Repairing FC10's existing defects as defects of FC10.** The properties in
  R4 and R5 are required of whatever ships, and R14 requires that exactly one
  prose check code survives. What stays out is treating today's line-number
  offset and code-fence matching as bugs to be filed and fixed on their own; an
  implementation satisfying R4 and R5 makes them moot.

## Decisions and Trade-offs

The four questions the BRIEF deferred close here.

**The rule source ships inside the shirabe repository.** The BRIEF asked
whether an adopter must be able to read it without installing shirabe. They do
not need to: the reusable workflow checks out the entire shirabe repo at the
called ref into `.shirabe-src` and builds the binary from that checkout, so a
committed rule file is already on the runner at the commit that produced the
binary.

Four alternatives were considered, and they don't fail the same way. A release
asset and a published package each add a fetch that can fail and a version an
adopter can pin independently of the binary. A vendored copy in each adopter
adds no fetch at all; it drifts silently instead, and shirabe has no freshness
detector for adopter-side copies. Compiling the rules into the binary with
`include_str!` is the nearest neighbour to today's FC10 and is named here
because the DESIGN will otherwise reopen it: it can't drift and it's simple,
but it embeds the rules at build time, which R1 forbids for the reason the
Problem Statement gives. The in-repo file wins because it's the only option
where the rules and the enforcement can't disagree and the rules are still read
at enforcement time. Recorded as R18 and R19.

That rationale is CI-specific, and R2 requires the rule source reach a local
run and a drafting skill as well. In-repo satisfies those too and for a
simpler reason: the file is present in any checkout of the repository being
worked in, and the plugin already resolves references from its own root for
the agent-side consumer. No option considered here serves CI and fails
locally, so the CI argument decides it without the local case dissenting.

**Vocabulary extends rather than replaces, and this diverges from precedent
deliberately.** `--custom-statuses` is shirabe's only adopter-supplied list and
it is documented and tested as replace. Following it here would institutionalize
the copy-that-drifts problem this feature exists to end: a repo that replaces
the rule set stops receiving corrections and becomes a fourth divergent copy by
another route. A reader who knows the codebase will notice the divergence, which
is why it is recorded rather than left implicit. Recorded as R9.

**The existing check is extended, not retired.** Retiring a check code touches
seventeen registration points across four lists, three test lists, two prose
copies, and a golden baseline, six of which fail silently; and it has no
deprecation path, so `--check FC10` would go from working to a hard exit-1 tool
error. Extending is materially cheaper and the repo has already rejected an
FC-code rename once on the same churn reasoning. The counter-argument is that
the code's name will no longer describe what it does. That is a real cost and
it is accepted. R14 records the success condition: exactly one prose check code
survives.

Because nothing is retired, the question of whether removing a code from the
emittable set breaks `shirabe-validate/v1` does not arise for this capability.
It remains unanswered in the repository, and R15 requires any later retirement
to answer it rather than leaving a consumer to discover the answer from a
parse failure.

**Frequency rules ship below error level with a filed promotion condition.**
Error on first release, at a 3-per-thousand threshold, would fail 92 of
shirabe's 124 validator-visible docs, 47% of koto's corpus and 49% of niwa's,
reaching all three adopters immediately because they pin `@main`. A laxer
threshold shrinks the count without reaching zero: 11 of 124 at 15 per
thousand. The alternative considered was shipping
error-level after a corpus cleanup, which the evidence rejects: nine codes have
sat at notice level behind a comment promising cleanup, no cleanup issue exists
for any of them, and no code has ever been promoted. A promise recorded only in
a comment has a demonstrated completion rate of zero here, which is why R12
requires a filed issue with a numeric condition rather than "the corpus is
clean." Recorded as R11 and R12.

Draft-tolerable severity was the third option and it is rejected for the first
release, not dismissed. It is the only posture that both enforces and survives
contact with the current corpus, and its machinery already exists. It is
rejected because `validate-docs.yml` does not thread `--mode` today, so
adopting it would make the first release depend on a workflow change that
every adopter inherits at `@main`, trading a noise problem for a behavior
change in three repositories that have not been asked. It becomes the natural
posture at promotion time, once the R12 issue's condition is met.

**A remaining unknown, recorded rather than resolved.** The reporting unit for
frequency findings varies annotation volume on shirabe's corpus by about thirty
times between per-occurrence, per-paragraph, and per-document. R7 requires the
decision be made and documented; this PRD does not make it, because it is a
judgment about what an author should see rather than a requirement the feature
succeeds or fails against. The DESIGN owns it.

## Known Limitations

The committed corpus does not pass at error level today for reasons unrelated
to prose. Validating every file under `docs/` explicitly returns 5 errors, all
R6 dangling `upstream:` links, alongside 139 notices of which 97 are FC10 and
33 are files skipped for a missing `schema` field. Any framing that treats "the
corpus is clean" as a starting condition is currently false.

The format gate that R3 addresses has a third consequence beyond skipping
instruction files, and it is the one most likely to mislead. `shirabe validate`
takes a file list and resolves each entry through the same prefix match, with no
directory walk: an argument that is a directory matches no prefix and is
skipped. `shirabe validate -- docs` therefore reports "All checks passed" at
exit 0 having validated nothing, while the same corpus passed as an explicit
file list reports 5 errors and 139 notices. CI is unaffected because the
reusable workflow passes changed files individually, but a maintainer checking
their corpus by hand gets a green result from a run that read no files. This
PRD does not require a directory walk; it records the behavior because R3's
value is easy to underestimate while it is described only as missing coverage
of instruction files.

Instruction-file coverage is only half deliverable from shirabe's side. shirabe
can make the checking exist and can apply it to its own repo; reaching an
adopter's CLAUDE.md and skill files requires a PR against each adopter's caller
workflow, because all three filter `paths: ['docs/**']`.

The advisory surface cannot currently explain a notice-level finding. It
composes notes only for draft-tolerable codes and prints "no draft-tolerable
findings to flag" on a run carrying dozens of prose notices. An author told
what to fix but not why or when it will start blocking is a worse experience
than the finding count suggests.
