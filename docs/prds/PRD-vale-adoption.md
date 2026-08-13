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
SKILL.md, CLAUDE.md, AGENTS.md, and README.md handed to it. It reads 440,003
words of artifact prose in shirabe's own repo and skips about 225,000, of which
197,538 are the 211 files under `skills/`. The gap is not mainly volume. The
skipped files are the instructions that shape every future agent run, so a
defect there propagates into the prose the checked surface is judged on.

The rules it does enforce are the ones already obeyed. Across 554,000 words the
phrase apparatus produces roughly two true positives, and raw word-rule
precision measures 1.7%, rising to about 16% once domain terms are excluded.
The two highest-volume matches are shirabe's own terms of art: `tier` is 128 of
156 alerts in a `docs/` run because Tier 1-4 is its decision vocabulary, and
`journey` at 112 hits is a required heading in its own BRIEF format. A banned
word list fires hardest against the repo that wrote it, and every adopter has
equivalent collisions with no way to declare them.

The defect that does recur is one no copy can express. Counting body prose
only, em dashes run 3,114 in `docs/` and 1,188 in `skills/`, 7.84 per thousand
words with 72% of files above 3 per thousand and the worst at 28.5. Frequency
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
effect everywhere the rule is enforced, so that I do not have to find and
update three copies and hope I found them all.

**As a shirabe skill author editing `skills/execute/SKILL.md`,** I want prose
findings on the file I am editing, so that the instructions shaping every agent
run get the same scrutiny as the artifacts those runs produce.

**As a drafting skill at its validate phase,** I want findings that name the
document-level properties I could not observe while composing, so that I revise
on information I did not already have.

**As a maintainer of a repo that adopts shirabe,** I want to declare the words
my project uses as terms of art, so that the checking stops firing on them
without my having to disable it or fork the rulebook.

**As a maintainer of an adopting repo on the day this ships,** I want my builds
to keep passing, so that a capability I did not ask for does not block my
merges.

## Requirements

### Functional

**R1. Single rule source.** The writing-style rules SHALL have exactly one
authoritative representation in the repository, and every enforcing surface
SHALL read from it rather than restating it. The three current copies SHALL be
reduced to that one source plus references to it.

**R2. Both consumers resolve identically.** The rule source SHALL be readable
by the validator and by the drafting skills through the same resolution, so a
rule honored at validate time is honored while drafting and the reverse. A
source honored by only one consumer does not satisfy R1.

**R3. Instruction-file coverage.** The checking SHALL be able to run against
files that are not artifact-prefixed, specifically SKILL.md, CLAUDE.md,
AGENTS.md, and README.md. The current format gate returns "All checks passed"
for these, which SHALL no longer be the case when prose checking is requested
for them.

**R4. Prose scoping.** Findings SHALL be reported against prose only. Matches
inside fenced code blocks, inline code spans, URLs, table delimiters, and
frontmatter SHALL NOT be reported. This is a stated requirement rather than an
implementation detail, because a frequency measurement that counts code fences
is not the measurement the author is being asked to act on.

**R5. Accurate locations.** A finding SHALL carry the line number of the
occurrence in the file as the author sees it. The current check reports
body-relative numbers offset by the frontmatter length, which makes its CI
annotations point at the wrong lines.

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

**R11. Non-breaking arrival.** Every rule SHALL ship at a severity that does
not fail an adopter's build on the release that introduces it. Measured:
error-level on first release would fail 92 of shirabe's 124 validator-visible
docs and roughly half of koto's and niwa's corpora, reaching all three the day
it merged.

**R12. Promotion condition is an artifact.** A rule shipped below error level
SHALL have its promotion precondition recorded as a filed, tracked issue with a
measurable condition, not as a code comment. The condition SHALL be a stated
number rather than "the corpus is clean." Nine check codes currently sit at
notice level behind a comment promising a cleanup PR; no such PR or issue
exists for any of them, and no code has been promoted out of the notice set.

**R13. No silent registration.** Adding a check code SHALL register it in every
list that gates it. Six of the seventeen current registration touchpoints fail
silently when missed, and two are already stale in the shipped tree, naming
`FC01`-`FC13` where the truth is `FC01`-`FC16`. The stale copies SHALL be
corrected.

**R14. Check-code retirement, if any, SHALL be non-breaking.** Retiring a code
SHALL NOT turn a previously valid `--check <code>` invocation into a tool
error, and the code SHALL remain selectable as a no-op for at least one
release. No deprecation path exists today.

### Non-functional

**R15. No new runtime dependency for adopters.** The capability SHALL NOT
require an adopting repository's CI to install or fetch anything it does not
install today. The reusable workflow already checks out the shirabe repo at the
called ref and builds from source, so any rule file committed to shirabe is
already present on the runner at the exact commit that produced the binary.

**R16. Version skew SHALL be structurally impossible on the CI path.** The
rules and the enforcement SHALL originate from the same ref. The CI binary is
version-anonymous today, so a requirement phrased as a version compatibility
assertion has nothing to compare against.

**R17. Adopters SHALL need no workflow edit for artifact coverage.** A
capability scoped to the paths adopters already filter on SHALL reach them with
no change to their caller workflows. Coverage of instruction files outside
those filters SHALL be documented as requiring an adopter-side change, because
all three callers filter `paths: ['docs/**']` and shirabe cannot widen that
from its side.

## Acceptance Criteria

- [ ] The writing-style rules exist in exactly one authoritative location; the
      FC10 constant and the BRIEF jury's inline word list are replaced by
      references to it.
- [ ] A rule added to that source is honored by `shirabe validate` and by a
      drafting skill without a second edit.
- [ ] `shirabe validate` produces prose findings for a SKILL.md, a CLAUDE.md, an
      AGENTS.md, and a README.md.
- [ ] A banned word inside a fenced code block, an inline code span, a URL, and
      YAML frontmatter produces no finding; the same word in prose produces one.
- [ ] A finding's reported line number equals the line the author sees in the
      file, verified on a file with frontmatter.
- [ ] An em dash density rule reports against a stated threshold, with
      denominator, reporting unit, threshold value, and line-number convention
      recorded in the multi-consumer contract doc.
- [ ] A repository declaring `tier` receives no `tier` findings and still
      receives findings for every other rule.
- [ ] A term declared in shirabe's repository produces no suppression in a
      different repository checked in the same run.
- [ ] Adding a rule to the source after a repository has declared its
      vocabulary causes that repository to receive the new rule with no edit to
      its declaration.
- [ ] Running the full check over shirabe, koto, niwa, and tsuku at the shipped
      severity produces exit code 0 in all four.
- [ ] A filed issue exists, referenced from the check's documentation, naming a
      numeric promotion condition for every rule shipped below error level.
- [ ] `--check <code>` succeeds for every code named in the contract doc,
      including any retired as a no-op.
- [ ] The check-code ranges in `cmd/shirabe` help output and in
      `docs/guides/multi-consumer-cli-contract.md` agree with the registry.

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
  R4 and R5 are required of whatever ships. Whether today's check is repaired or
  superseded follows from the mechanism choice.

## Decisions and Trade-offs

The four questions the BRIEF deferred close here.

**The rule source ships inside the shirabe repository.** The BRIEF asked
whether an adopter must be able to read it without installing shirabe. They do
not need to: the reusable workflow checks out the entire shirabe repo at the
called ref into `.shirabe-src` and builds the binary from that checkout, so a
committed rule file is already on the runner at the commit that produced the
binary. Alternatives considered: a release asset, a vendored copy in each
adopter, and a published package. All three introduce a fetch that can fail and
a skew between rules and binary that the in-repo option makes structurally
impossible. Recorded as R15 and R16.

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
it is accepted. Recorded as R14, which constrains retirement if a later change
chooses it anyway.

**Frequency rules ship below error level with a filed promotion condition.**
Error on first release would fail 92 of shirabe's 124 validator-visible docs and
about half of koto's and niwa's corpora, reaching all three adopters
immediately because they pin `@main`. The alternative considered was shipping
error-level after a corpus cleanup, which the evidence rejects: nine codes have
sat at notice level behind a comment promising cleanup, no cleanup issue exists
for any of them, and no code has ever been promoted. A promise recorded only in
a comment has a demonstrated completion rate of zero here, which is why R12
requires a filed issue with a numeric condition rather than "the corpus is
clean." Recorded as R11 and R12.

**A remaining unknown, recorded rather than resolved.** The reporting unit for
frequency findings varies annotation volume on shirabe's corpus by about thirty
times between per-occurrence, per-paragraph, and per-document. R7 requires the
decision be made and documented; this PRD does not make it, because it is a
judgment about what an author should see rather than a requirement the feature
succeeds or fails against. The DESIGN owns it.

## Known Limitations

The committed corpus does not pass at error level today for reasons unrelated
to prose: five dangling `upstream:` links from a deleted design produce R6
errors. Any framing that treats "the corpus is clean" as a starting condition is
currently false.

Instruction-file coverage is only half deliverable from shirabe's side. shirabe
can make the checking exist and can apply it to its own repo; reaching an
adopter's CLAUDE.md and skill files requires a PR against each adopter's caller
workflow, because all three filter `paths: ['docs/**']`.

The advisory surface cannot currently explain a notice-level finding. It
composes notes only for draft-tolerable codes and prints "no draft-tolerable
findings to flag" on a run carrying dozens of prose notices. An author told
what to fix but not why or when it will start blocking is a worse experience
than the finding count suggests.
