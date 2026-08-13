# Phase 4 Verdict: Completeness

VERDICT: FAIL

Three criteria fail: the BRIEF's third Open Question is closed in Decisions and
then reopened by Out of Scope (criterion 2); two load-bearing research
implications are silently dropped (criterion 3); and three of seventeen
requirements have no acceptance criterion (criterion 5). Criteria 1, 4, 6, and 7
pass. `shirabe validate --visibility=public` on the PRD is clean (0 errors, 6
FC10 notices, exit 0), so nothing here is a mechanical-validator finding.

## Per-criterion

### 1. Required sections present and ordered — PASS

Body headings, in order: `## Status` (26), `## Problem Statement` (33),
`## Goals` (75), `## User Stories` (93), `## Requirements` (115),
`## Acceptance Criteria` (221), `## Out of Scope` (253). All seven required
sections present, in the canonical order. Two optional sections follow
(`## Decisions and Trade-offs` 290, `## Known Limitations` 340); FC15 accepts
that ordering — verified by running the validator, which reports no section-order
finding. Requirements carries the `### Functional` / `### Non-functional` split
the format asks for. No Open Questions section, correct for a doc that will
transition to Accepted.

### 2. BRIEF's four Open Questions closed — FAIL

The four questions are recorded verbatim in
`wip/scope_vale-adoption_decisions.md:16-29`. Disposition:

**Q1 (must an adopter read the rule source without installing shirabe) —
closed.** "The rule source ships inside the shirabe repository." Alternatives
named and rejected with reasons (release asset, vendored copy, published
package — each introduces a fetch that can fail and a rules/binary skew).
Bound to R15 and R16. This is a full close.

One weakness, not a fail: the rationale is entirely a CI argument (`.shirabe-src`
checkout at the called ref). The adopter-surface research §4 established that the
CI and local audiences have different reach — an adopter who installs only the
binary via `install.sh` or the tsuku recipe gets neither `references/` nor
`skills/`, so the in-repo answer is free for CI and unaddressed for local. R2
requires both the validator and the drafting skills resolve the same source, and
the recorded rationale only justifies one of the two. The research's own answer
(the plugin already places `references/` at `${CLAUDE_PLUGIN_ROOT}`, so one file
reaches both) is not carried into the PRD.

**Q2 (extend or replace) — closed.** "Vocabulary extends rather than replaces,
and this diverges from precedent deliberately." Alternative (`--custom-statuses`
replace semantics) named, rationale given, divergence flagged for the reader who
knows the codebase. Bound to R9. Full close.

**Q3 (is FC10 replaced or extended) — PARTIAL CLOSE, and this is the failure.**
The decision reads "The existing check is extended, not retired," with costs on
both sides and an accepted counter-argument. That is a well-formed decision. It
is then contradicted twice inside the same document:

- Out of Scope, last bullet: "Whether today's check is repaired or superseded
  follows from the mechanism choice." Superseded is retirement. The Decisions
  section says the question is settled; Out of Scope hands it back to the DESIGN.
- R14 is phrased "Check-code retirement, **if any**, SHALL be non-breaking,"
  which is a constraint on a path the Decisions section says is not being taken.

There is no requirement stating that the existing check is extended, and no
requirement or criterion forbidding two overlapping checks. The BRIEF's question
asked for exactly that: "the PRD should state which outcome counts as success so
the DESIGN is not free to leave two overlapping checks in place"
(`scope_vale-adoption_decisions.md:25-27`). As written, a DESIGN author reading
Out of Scope is free to supersede, and nothing in the Requirements or Acceptance
Criteria stops the two-overlapping-checks outcome the question was raised to
prevent. A decision that the requirements do not bind and the Out of Scope
section reopens is a partial close.

**Q4 (severity on first release) — closed.** "Frequency rules ship below error
level with a filed promotion condition." Alternative (error-level after a corpus
cleanup) named and rejected on measured evidence: nine codes at notice level
behind a comment, zero cleanup issues, zero promotions in 292 commits. Bound to
R11 and R12. Full close.

Minor gap: the check-lifecycle research surfaced a third severity option the
decision does not mention — draft-tolerable (`posture_class`), notice while a PR
is in draft and error once marked ready (research §2, implication 10). R11's
phrasing ("does not fail an adopter's build on the release that introduces it")
probably excludes it, which is a substantive narrowing made silently rather than
as a rejected alternative.

**Remaining unknown, recorded:** the reporting unit for frequency findings is
explicitly handed to the DESIGN with the 30x annotation-volume evidence attached.
That is a correct use of the "acknowledged remaining unknown" disposition.

### 3. Requirements coverage against the research — FAIL

The five hunted items:

| Item | Disposition |
|---|---|
| Advisory surface cannot explain a notice (check-lifecycle 11) | **Acknowledged**, not required. Known Limitations, final paragraph. Not a silent drop. |
| 27% schema-gate coverage gap (check-lifecycle 9) | **Deliberately excluded.** Out of Scope: "The schema-gate coverage gap. 33 of shirabe's 124 validator-visible files..." Correct handling. |
| Two stale prose copies naming FC01-FC13 (check-lifecycle 4) | **Covered.** R13 final sentence, plus AC13. But AC13 names `cmd/shirabe`, which does not exist in this repo (`ls cmd` fails; the crates are `crates/shirabe` and `crates/shirabe-validate`). See criterion 5. |
| Day-zero behavior with no vocabulary declaration (vocabulary open question 3) | **SILENT DROP.** |
| Emittable check-code set as part of the v1 contract (check-lifecycle open question 1, implication 3) | **SILENT DROP.** |

On the advisory surface: putting it in Known Limitations is a defensible
disposition, but note the tension it creates. The PRD's entire severity strategy
is notice-now-promote-later (R11 + R12), and the one surface that could tell an
author "this is tolerated now and will block later" is the surface the PRD
records as unable to speak. The third user story ("I want findings that name the
document-level properties I could not observe") is partly funded by a surface the
document says does not work. Either raise it to a requirement or say in Known
Limitations why R12's filed issue is judged sufficient substitute.

On the two silent drops, detail below.

Everything else in the three research files' numbered implications maps to a
requirement or an exclusion:

- check-lifecycle 1 → Decisions (extend), 2 → R14, 5 → R11, 6 → R12, 7 → R6+R7,
  8 → R4+R5, 9 → Out of Scope, 10 → subsumed by R11 (mechanism-neutral),
  11 → Known Limitations. **3 → dropped.**
- vocabulary 1 → R9, 2 → R10, 5 → R8, 6 → R11, 7 → Out of Scope
  ("Adopter-side per-rule rejection", a clean explicit close of the "silence
  reads as a promise" risk), 8 → DESIGN, 9 → R2. **3 → partial (below).**
  4 (list outgrows one line) → DESIGN, acceptable.
- adopter-surface: rule file in-repo → R15/R16 + Decisions; zero caller-workflow
  change → R17; coverage outside `docs/**` needs adopter PRs → R17 second
  sentence + Out of Scope + Known Limitations; version-assertion has nothing to
  compare → R16; the per-run install cost lever (also paid by `lifecycle.yml` and
  `pr-body.yml`, the latter unfiltered) → covered by R15's no-new-install
  constraint.

### 4. Requirements numbered, specific, testable — PASS

R1 through R17, each appearing exactly once, no gaps or duplicates (verified by
grep). Each states a SHALL/SHALL NOT condition rather than an aspiration. The
weakest three, none fatal:

- **R16** opens with "Version skew SHALL be structurally impossible on the CI
  path," which is unfalsifiable on its own; the second sentence ("The rules and
  the enforcement SHALL originate from the same ref") is the checkable form and
  rescues it.
- **R13**'s first clause ("Adding a check code SHALL register it in every list
  that gates it") is a process rule about future work rather than a property of
  this feature's output, and under the Q3 decision (extend, not retire) this
  feature may add no code at all. The second clause (correct the stale copies) is
  concrete and testable.
- **R2**'s second half ("a rule honored at validate time is honored while
  drafting and the reverse") is testable only through a skill eval, not a
  mechanical run. See criterion 5.

### 5. Acceptance criteria are a real contract — FAIL

Three requirements have no criterion: **R15, R16, R17.** All three are the
Non-functional block — the entire non-functional half of the requirements is
unbound by the contract. R17 in particular is the one requirement an adopter
would feel directly (their caller workflow keeps working unedited), and nothing
verifies it. AC10 (exit 0 across four repos) is about severity, not about whether
a caller workflow needed editing.

Two criteria cannot be executed as written:

- **AC2**, "honored by `shirabe validate` and by a drafting skill without a
  second edit." The validator half is mechanical. The drafting-skill half is a
  model-behavior assertion with no stated harness. The repo has an eval mechanism
  (`scripts/run-evals.sh`, per CLAUDE.md) — if that is the intended check, the
  criterion should say so; otherwise this is a judgment call wearing a checkbox.
- **AC13**, "The check-code ranges in `cmd/shirabe` help output..." There is no
  `cmd/` directory in this repository. The help text lives in
  `crates/shirabe/src/main.rs` (the clap doc comment at :213-219 and the
  error string at :529, per the check-lifecycle research). The criterion is
  executable in spirit — compare `shirabe --help` output and the contract doc
  against the registry — but the path it names is wrong, and a wrong path in a
  contract is how a criterion gets waved through as "not applicable."

One circularity worth noting: **AC12** requires `--check <code>` to succeed for
"every code named in the contract doc," and the contract doc is currently one of
the two stale copies (it says `FC01`-`FC13`). As written, AC12 is satisfiable
today by the stale set. R13 fixes the doc, so the two criteria resolve in
sequence, but AC12 should reference the registry rather than the doc.

### 6. Content boundaries — PASS

No architecture, no API shapes, no code. The deferral to DESIGN is real and
repeatedly enforced: Out of Scope's first bullet names the five candidate
mechanisms and hands the choice over; R6 says "at least one rule that evaluates a
rate or count against a threshold" without naming how; R8 says the declaration
must be term-scoped without naming a file, header, or format; the reporting-unit
decision is explicitly left to the DESIGN. The PRD never names a linter, a config
file, a header, or a code path as the answer.

**On R15 and R16 specifically — constraint, not design.** R15's normative clause
is "SHALL NOT require an adopting repository's CI to install or fetch anything it
does not install today," which is a textbook non-functional constraint. The
sentence that follows is evidence that the constraint is satisfiable, drawn from
a mechanism that already exists and that the PRD is not proposing to build. R16
is the same shape: "rules and enforcement SHALL originate from the same ref" is
an outcome, and the CI-binary-is-version-anonymous sentence explains why the
requirement is not phrased as a version assertion. Neither forces a mechanism —
they bound the solution space, which is what a non-functional requirement is for.
The Decisions entry does settle the rule source's *location*, but that closure was
sanctioned by the BRIEF's Q1, which the chain decisions record explicitly
authorizes the PRD to settle.

Two minor boundary leaks, both in the criteria rather than the requirements:

- **AC6** requires the frequency-rule shape be "recorded in the multi-consumer
  contract doc," naming a specific existing file. R7 itself says only "the
  documentation SHALL record," which is the right altitude; the AC narrows it to
  an implementation location.
- **AC13** names two specific files as the locations that must agree.

The closest requirement-side call is **R13**, whose "register it in every list
that gates it" is an internal engineering-practice rule about the codebase's
seventeen touchpoints. It stays inside the boundary only because the user-visible
half — `--check` help text lying about which codes exist — is a real adopter-
facing defect. If R13 is kept, tighten it to the user-visible property and let
the DESIGN own how registration is made non-silent.

### 7. Frontmatter — PASS

`schema: prd/v1` (line 2). `status: Draft` (3). `problem: |` (4) and `goals: |`
(12), both literal block scalars, each one paragraph. `upstream:
docs/briefs/BRIEF-vale-adoption.md` (18) — repo-root-relative, resolves to the
Accepted BRIEF, no `wip/` path. `motivating_context: |` (19), optional and
correctly a literal block. Body `## Status` first non-blank line is a bare
`Draft` (28), matching the frontmatter; the qualifying paragraph is separated by
a blank line, which is the required shape. `shirabe validate` reports no FC01 or
FC03 finding.

## Requirement-to-criterion map

| Req | Criterion | Notes |
|---|---|---|
| R1 single rule source | AC1 | Direct. |
| R2 both consumers resolve identically | AC2 | Drafting-skill half not mechanically executable. |
| R3 instruction-file coverage | AC3 | Direct, names all four file types. |
| R4 prose scoping | AC4 | Direct; covers fence, inline span, URL, frontmatter. Table delimiters named in R4 but not in AC4. |
| R5 accurate locations | AC5 | Direct, with the frontmatter case called out. |
| R6 frequency rules | AC6 | Direct. |
| R7 frequency rule shape stated | AC6 | Same criterion; covers all four named properties. |
| R8 per-repo vocabulary declaration | AC7 | Covers both halves (term suppressed, other rules still fire). |
| R9 vocabulary extends, never replaces | AC9 | Direct. |
| R10 vocabulary is repo-local | AC8 | Direct. |
| R11 non-breaking arrival | AC10 | Direct and executable (all four repos are in this workspace). |
| R12 promotion condition is an artifact | AC11 | Direct. |
| R13 no silent registration | AC13 | Covers the stale-copy half only; wrong path (`cmd/shirabe`). The "every list that gates it" half is uncovered. |
| R14 retirement is non-breaking | AC12 | Direct. |
| **R15 no new runtime dependency** | **none** | **Uncovered.** |
| **R16 version skew impossible on CI path** | **none** | **Uncovered.** |
| **R17 no adopter workflow edit** | **none** | **Uncovered.** |

## Silent drops

**1. Day-zero behavior for an adopter with no vocabulary declaration.**
Source: vocabulary-model research, Open question 3. "An adopter who never writes
a declaration gets the unsuppressed rate under every model considered here.
Whether that is acceptable, and whether the word rules should therefore default
to report-only until a repo has declared its terms, is a product call." The same
research's implications block asks for fail-open defaults for unconfigured
adopters, and the adopter-surface research names the existing precedent (the
schema gate emits `::notice` rather than failing; FC-CONVENTIONS is notice-level).

The PRD never states what an adopter who declares nothing receives. Grepping the
document for "no declaration", "does not declare", "day zero", "default", and
"precision" returns two hits, both in the Problem Statement's precision numbers.
This matters because the PRD's own Problem Statement makes it matter: raw
word-rule precision is 1.7%, rising to 16% once domain terms are excluded, which
means the vocabulary declaration is doing most of the precision work, and every
adopter starts with none. R11 blunts the consequence (nothing fails a build) but
says nothing about the noise, and the fifth user story ("I want my builds to keep
passing") is not the same claim as "the findings I get on day one are worth
reading."

This is either a requirement (word rules report-only, or suppressed, until a repo
declares) or an explicit Out of Scope entry ("an adopter with no declaration
receives the unsuppressed rate; tuning it is their first PR"). Right now it is
neither.

**2. Whether removing a check code from the emittable set is breaking for
`shirabe-validate/v1`.** Source: check-lifecycle research, Finding 1(b) and
implication 3 — "The contract doc versions the envelope shape but is silent on
the code vocabulary. Removing a code is either additive (keeps v1) or breaking
(bumps to v2), and nothing currently says which. **This is undecided and the PRD
has to decide it.**" It is also the first of that lead's Open questions, marked
as needing a human call.

The PRD does not mention `schema_version`, the JSON envelope, or breaking
changes anywhere. R14 constrains the CLI-selection surface (`--check <code>` must
not become a tool error) but says nothing about the machine-readable contract
that downstream consumers parse. The Q3 decision ("extended, not retired") makes
the question dormant rather than moot, and R14's own "retirement, if any"
phrasing keeps the retirement path alive — so the PRD constrains a path it has
not fully specified.

**3. Partial: where the vocabulary declaration must be resolvable from.**
Source: vocabulary-model implication 3 — "The declaration must be resolvable from
the file being checked, in the repo, with no CI wiring. It has to reach the
drafting agent, a local `shirabe validate`, the pre-commit hook, and CI. A
workflow input reaches only the last of those and costs every adopter a workflow
edit." R2 covers this property for the *rule source* but is scoped to "The rule
source"; R8 and R10 say the declaration exists and is repo-local without saying
which consumers must honor it. R17 forbids a workflow edit for *coverage*, not
for *configuration*. As written, a DESIGN could satisfy R8, R9, R10, and R17 with
a second `workflow_call` input following the `--custom-statuses` precedent — the
exact shape the research argues against — and violate nothing. Not a full drop,
because R17 leans the right way, but the requirement that would close it is
missing.

## Required changes

1. **Bind the Q3 decision in a requirement, and stop Out of Scope from reopening
   it.** Add a requirement stating the success condition — e.g. "Exactly one
   prose check code SHALL be emittable for the writing-style rules; the
   capability SHALL NOT leave two overlapping checks registered" — and rewrite
   the final Out of Scope bullet so it excludes *repairing FC10's defects as
   defects of FC10* (which is the BRIEF's actual boundary) without also saying
   the repaired-or-superseded question follows from the mechanism choice.
   Reconcile R14's "if any" with the Decisions section, either by keeping it as a
   forward-looking constraint and saying so, or by folding it into the new
   requirement.

2. **Add acceptance criteria for R15, R16, and R17.** Suggested shapes, all
   mechanically checkable: for R15, a diff of the reusable workflow shows no new
   install, fetch, or download step relative to the pre-change version; for R16,
   the rule source and the binary in a CI run resolve from the same commit SHA,
   demonstrable from the run log; for R17, an adopter caller workflow unchanged
   at its current 19-20 lines produces prose findings on a `docs/**` PR.

3. **Close the day-zero vocabulary question.** Either a requirement fixing what
   an undeclared repo receives, or an explicit Out of Scope entry saying it
   receives the unsuppressed rate and that tuning is the adopter's first action.
   State it; do not leave it inferable from R11.

4. **Decide, or explicitly defer, whether the emittable check-code set is part of
   `shirabe-validate/v1`.** If the answer is "the question does not arise because
   nothing is retired," say that in the Q3 decision and drop R14's "if any"
   framing. If R14 survives as a forward constraint, it needs a companion
   sentence on the JSON contract, or a recorded remaining unknown alongside the
   reporting-unit one.

5. **Fix AC13's path.** Replace `cmd/shirabe` with the actual location of the
   help text (`crates/shirabe`), or better, phrase it without a path: "the
   check-code range in `shirabe validate --help` output and in the multi-consumer
   contract doc agree with the set `is_known_check_code` accepts."

6. **Make AC2 executable or say what executes it.** Name the eval harness for the
   drafting-skill half, or split the criterion into a mechanical half (validator
   honors the new rule) and an eval half with its harness named.

7. **Reference the registry, not the contract doc, in AC12.** As written it is
   satisfiable against a document R13 exists to correct.

8. **Add a requirement that the vocabulary declaration is resolvable by every
   consumer that enforces the rules** — validator, drafting skill, and local run
   — not only by CI. Without it, a workflow input satisfies every current
   requirement.

9. **Optional but recommended:** name draft-tolerable as a considered-and-rejected
   alternative in the Q4 decision, since R11's phrasing excludes it and the
   research put it forward as the only option that is both enforcing and
   survivable. And extend the Q1 rationale to cover the local (non-CI) consumer
   that R2 requires, since the recorded justification is CI-only.
