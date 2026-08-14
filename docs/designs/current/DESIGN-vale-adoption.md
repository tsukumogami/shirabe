---
schema: design/v1
status: Current
upstream: docs/prds/PRD-vale-adoption.md
problem: |
  shirabe's writing-style rules live in three divergent copies, only one of
  which is mechanical, and that one checks seven words, never sees instruction
  files, reports line numbers offset by the frontmatter length, and matches
  inside code fences. The defect that recurs measurably, document-level
  frequency, is one no copy can express, and no check in the validator counts
  occurrences or computes a rate.
decision: |
  Widen the existing native check rather than adopt an external linter. Rules
  move to a YAML file the validator parses at enforcement time and the
  writing-style skill points at. A repository declares terms of art through a
  parsed CLAUDE.md header resolved by a generalized ancestor walk. FormatSpec
  becomes optional per check so prose checks reach instruction files while
  structural checks cannot fire on them.
rationale: |
  Vale is a better linter than what shirabe will build, and it cannot do this
  job. Its adopter cost is forbidden outright by R18, it exits 2 with zero
  findings on shirabe's own skill tree, and the one rule carrying the empirical
  case for the capability is the one rule its markup scoping is switched off
  for. A 90-line native scoper agrees with Vale on 483 of 489 paragraph
  findings and gets the edge cases Vale misses.
---

## Status

Current

Four decision questions were evaluated in parallel, each with equal-depth
alternatives. Their reports are the audit trail for the choices below.

## Context and Problem Statement

The upstream PRD states the problem in full. What the design must settle is
narrower and technical: what enforces the rules, where the rules live, how a
repository declares its vocabulary, and how the file-selection gate changes.

The exploration that produced this chain started from the question "should
shirabe adopt Vale" and inverted its own premise twice. First, mechanical prose
checking already ships: FC10 has been in `shirabe validate` since June. Second,
the rules a linter would add are the ones a drafting model already obeys, at
1.7% raw precision on shirabe's corpus, while the defect that recurs is a
frequency property no rule in the rulebook can express.

So the technical question is not whether shirabe needs a prose linter. It is
whether the checking it already has should be widened, and by what.

## Decision Drivers

**R18 is a hard constraint, not a preference.** The capability must add no
install, fetch, download, or package-manager step to an adopting repository's
CI. All three adopters call shirabe's reusable workflow pinned at `@main` and
pass no inputs; whatever merges reaches them on their next docs PR.

**R1 forbids build-time embedding.** Rules must be read at enforcement time.
The design that specified FC10 required exactly this and the shipped code
hardcodes the list instead, which is the divergence the capability exists to
end. A solution that satisfies "one source" by baking it into the binary
reproduces the defect.

**R4 and R6 must hold simultaneously.** Prose scoping and frequency
measurement are not independent: a rate computed over text that includes code
fences is not the rate the author is asked to act on.

**Silent success is the failure mode.** Three separate defects in the current
gate all report success without having checked. Any design that adds a fourth
way to pass without running is worse than the gap it closes.

**The corpus is the test case.** shirabe's own repo is the largest body of
shirabe-authored prose available, and every measurement below comes from it.

## Considered Options

### Decision 1: what enforces the rules

Confidence: high. The decision report backing this section was a wip/
artifact, removed at finalization per the workspace rule; the reasoning it
carried is summarized below rather than cited.

**Option A, an external linter invoked by the validator.** Vale is mature,
markup-aware, has a real Markdown parser, and its scoping is the feature shirabe
would otherwise hand-write. Rejected on three findings, in descending order of
how hard they are to argue with.

R18 forbids it outright. Every route to putting a 40 MB binary on an adopter's
runner is an install, fetch, download, or package-manager step, and the
acceptance criterion names all four. This is not a cost-benefit judgment a fast
download can win.

R3 fails on shirabe's own tree. Run across the 211 files under `skills/`, Vale
exits 2 with zero findings, because two of them carry frontmatter its YAML
parser rejects. It is fixable by invoking Vale per file and tolerating errors,
but that fix ships a checking surface that reports success for files it could
not read, which is precisely what R12a exists to end.

R4 and R6 are mutually exclusive under Vale. Its `metric` check has no
punctuation variable, and a `script` rule sees whole-document text only at
`scope: raw`, where markup scoping is switched off by definition. The one rule
carrying the empirical case for this entire capability is the one rule for
which Vale's best feature is unavailable, and the scoping would have to be
rewritten in Tengo, without lookaround, on a runtime that panics on an
out-of-range span.

**Option C, a split.** Native for CI, external for a local authoring loop.
Rejected because it doubles the rule-source problem it is meant to help: two
engines means two rule representations, or one representation and a translation
layer, and R1 and R2 exist to stop exactly that.

**Option B, a widened native check.** Chosen. `regex` is already a direct
dependency and already imported in `checks.rs`; FC10 does not use it and
hand-rolls ASCII byte matching instead, so the current narrowness is not
explained by a missing capability.

The strongest counter deserves stating: this is reimplementing a mature linter,
and shirabe's own FC10 is the cautionary tale for hand-rolled matching that
fires inside code fences and misreports lines. The answer is that the counter
misidentifies FC10's failure. FC10 does not fire inside code fences because its
scoping was attempted and failed; it fires there because it iterates `doc.body`
raw and attempts no scoping at all. The measured cost of attempting it is 90
lines, and the result agrees with Vale on 483 of 489 paragraph findings while
getting three edge cases Vale gets wrong.

### Decision 2: where the rules live

**Option A, parse the existing SKILL.md tables.** No migration, no new file,
the skill prose stays the source. Rejected on measured fragility: adding a third
column to a rule table drops four rules and exits 0. A prose file can be edited
by anyone who reads it, which is its virtue as instructions and its defect as a
parse target. It also cannot carry what R7 requires; the em dash rule needs a
threshold, denominator, reporting unit, and finding line, and the table row it
occupies today reads `Em dash overuse (—)`.

**Options B and D**, a data file plus a separate prose reference, or rules in
SKILL.md frontmatter. Both workable; B splits one concept across two files, and
D puts a growing data structure in a position readers expect to be short.

**Option C, one YAML file carrying rules and per-rule prose.** Chosen.
`skills/writing-style/rules.yaml`, parsed with `saphyr`, already a dependency
and already driven over arbitrary strings in `frontmatter.rs`. R7's four values
become fields rather than prose a parser must guess at. The drafting consumer
gets better material than the comma-jammed table rows it reads today.

### Decision 3: how a repository declares vocabulary

**Options C and D**, a dotfile or a fixed conventional path. Both introduce a
config-file concept shirabe has deliberately never had.

**Option B**, a header naming a path to a list file. Follows the path-valued
`## Release Notes Convention:` precedent. Reasonable, and one indirection more
than the problem needs at shirabe's scale of two terms.

**Option A, a parsed `## Prose Vocabulary:` header.** Chosen. Comma-delimited,
resolved by generalizing `resolve_doc_visibility` into
`resolve_claude_md_header(path, key)`: canonicalize, walk up from the file's
directory, `CLAUDE.local.md` before `CLAUDE.md`, header-less files transparent,
first hit wins.

The reuse is the point. Because the walk starts from the file being checked
rather than loading configuration once per run, R10's requirement that a term
declared in one repository not suppress it in another is satisfied
structurally. A global flag or a single config load fails that test.

Matching is case-insensitive whole-term, so a declared `tier` suppresses `Tier`
and does not suppress `tiered`; those are two independent terms on one rule row,
and a repo wanting both declares both. An absent header means the empty set,
which is R17 verbatim: nothing suppressed, no fail-safe inversion, because
unlike visibility there is nothing to fail safe toward.

### Decision 4: how the file-selection gate changes

**Option A**, a prose-only pseudo-format returned by `detect_format`. Rejected
because it leaves "structural checks must not fire on a schema-less file" to a
sentinel value someone must remember, adding an eighteenth registration
touchpoint to a surface where six of the existing seventeen already fail
silently and two are stale in the shipped tree.

**Option C**, a separate prose pass in the binary crate. Rejected because it
moves check dispatch out of the library, so a library consumer silently loses
prose checking.

**Option B, `FormatSpec` becomes optional per check.** Chosen. `check_fc01`,
`check_fc04`, and `check_fc15` take `&FormatSpec` by signature, so on the
`None` path there is no spec to pass and the invariant becomes a type error
rather than a convention. Directories are rejected as a tool error rather than
walked; CI passes changed files individually, so a walk buys nothing, and
rejection turns today's false green into a visible failure.

## Decision Outcome

shirabe widens what it already has rather than adopting what it does not.

The rules move to `skills/writing-style/rules.yaml`, read at enforcement time by
the validator and pointed at by the writing-style skill, so the three copies
collapse to one source with references. A repository declares terms of art in a
`## Prose Vocabulary:` header resolved per file by a generalized ancestor walk.
`FormatSpec` becomes optional per check, which lets prose checks reach
instruction files while making it a compile error for a structural check to
fire on one, and the same change makes `check_claude_md_conventions` reachable
and turns a directory argument into an error instead of a false pass.

The four decisions are mutually reinforcing rather than independent. The native
engine is what makes the YAML source readable at enforcement time without a
second config format. The generalized header walk is what makes vocabulary
per-file, and it is the same walk the validator already runs for visibility.
The optional `FormatSpec` is what lets one prose implementation serve artifacts
and instruction files without a second dispatch path.

## Solution Architecture

**Rule source.** `skills/writing-style/rules.yaml`. Each rule carries its
identity, its match data, and its prose. Frequency rules additionally carry
threshold, denominator, reporting unit, and finding-line convention as fields,
satisfying R7 by construction. Parsed with `saphyr` at enforcement time.

**How the rule source is found.** The binary and the rules are separate files,
so resolution has to be stated for every position the validator runs from, and
nothing in phase 1 can land without it.

| Position | Resolution |
|---|---|
| CI via the reusable workflow | `--rules <path>` pointing into `.shirabe-src/`, passed by the workflow that already checks that tree out |
| Local run | Ancestor walk from the working directory for `skills/writing-style/rules.yaml`, same shape as the CLAUDE.md walk |
| Pre-commit hook | The same ancestor walk; the hook runs inside the repo |
| `cargo test` | `SHIRABE_RULES` env var set by the harness, because the parity tests set cwd to `tests/fixtures/golden/corpus` where the walk would escape the crate |

Precedence is flag, then env var, then walk. A flag on an invocation the
workflow already makes is not an install, fetch, download, or
package-manager step, so R18's acceptance criterion is satisfied: the diff adds
an argument, not a step. R19 holds because the workflow passes a path inside
the checkout it made at the called ref, so the rules and the binary come from
one commit; the CI log shows both resolving from the same SHA.

**Missing or malformed rule source.** Fail closed. A rules file that cannot be
found or cannot be parsed is a tool error, exit 1, distinct from a content
violation. The design driver is that silent success is the failure mode this
capability exists to end; a validator that quietly checks nothing because its
rules did not load would be the fourth instance of that defect, added by the
change meant to fix the first three.

**Unknown declared terms are not an error.** A `## Prose Vocabulary:` entry
naming a term that is not on the rule list is ignored silently. Erroring would
break R9 the moment shirabe removes a word from the rulebook: every adopter
still declaring it would fail on a shirabe-side change they did not make.

**Prose scoper.** A markdown-aware extractor producing prose spans from a
document: fenced code, inline code, URLs, table rows, and frontmatter excluded;
headings included. Roughly 90 lines. This is the component the counter-argument
to Decision 1 correctly identifies as the risk, and it is the component whose
output is validated against Vale's on the real corpus.

**Prose check family.** Word and phrase rules over prose spans, plus at least
one frequency rule evaluating a rate against a threshold. All read the parsed
rule source and the resolved vocabulary. Reported through the existing
`ValidationError` shape.

### The em dash rule's four values

R7 requires these decided and recorded, and assigned the decision here. They
are stated as values, not as schema slots, and recorded in
`docs/guides/multi-consumer-cli-contract.md`, which is the surface the
acceptance criterion names.

| Value | Setting |
|---|---|
| Denominator | Words of scoped prose in the document, per R4: fenced code, inline code, URLs, table rows, and frontmatter excluded; headings included |
| Reporting unit | One finding per document |
| Threshold | 10 em dashes per thousand words |
| Finding line | The line of the first em dash occurrence in the document |

Per-document reporting is chosen over per-occurrence and per-paragraph because
the defect is a document-level property and the annotation volumes differ by
about thirty times; a rate defect reported 2,785 times is noise about one
problem. The first-occurrence line is chosen because a document-level finding
still has to point somewhere an author can click, and the alternative, line 1,
points at frontmatter.

The threshold is the value that decides whether this design's own R4/R6 driver
is load-bearing or vacuous, so it is chosen with that in view. At 3 per
thousand the raw-versus-prose scoping distinction flips zero verdicts, which
would make the scoper's precision irrelevant to the outcome. At 10 to 15 it
flips 6 to 11 files, so scoping correctness changes the result. 10 is chosen as
the lower end of that band: it makes the scoping matter while failing 49 of
shirabe's 124 validator-visible files, which is a corpus-cleanup target rather
than a wall.

Both the threshold and the reporting unit are fields in `rules.yaml`, so
changing them is a data edit rather than a code change. That is the point of
Decision 2.

**Header resolution.** `resolve_claude_md_header(path, key)` generalized out of
`visibility.rs`. `resolve_doc_visibility` becomes that call plus its
path-inference tail; `resolve_prose_vocabulary` becomes that call plus a comma
split, trim, lowercase, and empty-drop, with a size cap following the
`--custom-statuses` precedent.

R16 requires the vocabulary reach a drafting skill and a local run, not only
CI, and for a CLAUDE.md header that is nearly free: CLAUDE.md is already loaded
into a drafting agent's context, so a skill reads the declaration without any
new mechanism. That is Decision 3's deciding argument over a dotfile, which the
agent would have to be told to go read. A local `shirabe validate` run uses the
same walk as CI.

One interaction the four decisions create between them: Decision 4 makes
CLAUDE.md itself a prose-checkable file, so a CLAUDE.md carrying a
`## Prose Vocabulary:` header is a document whose own vocabulary must resolve
while it is being checked. The walk starts from the file's own directory, so a
CLAUDE.md resolves its own header. That is the correct behavior and it falls
out of the algorithm rather than needing a special case.

**Dispatch.** `validate_file` takes `Option<&FormatSpec>`. Structural checks
run only on the `Some` arm. Prose checks run on both, above the schema gate.
The `None` arm additionally gates on a `.md` extension, because
`validate-docs.yml` passes the PR's whole changed-file set and a non-Markdown
path reaching prose checking would be a new way to produce nonsense findings.

**Frontmatter parse failure on the `None` arm is not a tool error.** Two of
shirabe's own files, `skills/writing-style/SKILL.md` and
`skills/review-plan/SKILL.md`, fail `saphyr` frontmatter parsing today. This is
the same pair that makes Vale exit 2 across the skill tree, and it means a
`None` arm that treats a parse failure as a tool error would turn shirabe's own
CI red on the phase that adds instruction-file coverage. The prose family falls
back to raw-line scanning over the whole file instead. Both files are pinned
fixtures for that behavior.

**Findings are bounded.** Each rule emits at most 50 findings per file plus one
summarizing finding when truncated. Unbounded emission is measurable on the
current tree: a 10 MB document produces 1,500,000 FC10 findings at 875 MB
resident, which is a denial of service reachable from any repository under
check.

**Line endings are normalized once at entry.** `split_lines` retains `\r` on
every line of a CRLF document, which breaks fence close-matching and paragraph
boundary detection and silently collapses a per-paragraph frequency denominator
to the whole document.

**This widens the PRD's boundary, deliberately.** The PRD lists the 33 files
emitting "schema field missing, skipping" as out of scope, and placing prose
checks above the schema gate covers them. The expansion is recorded rather than
absorbed silently, because an unremarked scope change is how a design stops
being an instrument its PRD can audit.

The justification is R12a's principle. Those 33 files run zero checks and
report success, which is the same silent-success defect R12a exists to end,
arriving through a different gate. Fixing three instances of that pattern while
stepping around a fourth in the same dispatch path would be arbitrary. The cost
is that the change touches more files than the PRD anticipated, and that cost
lands concretely on the golden fixtures named in the phase plan below.

**Line numbers.** `Doc` gains the body start line so a finding can report the
line the author sees. This is the minimal change R5 needs and it does not exist
today.

## Implementation Approach

Phased so each phase is independently reviewable and leaves the tree green.

1. **Rule source and parser.** Add `rules.yaml`, parse it, and make FC10 read
   from it instead of `FC10_BANNED_WORDS`. Behavior-preserving by construction:
   the seven words move into the file first, the other 40 arrive later. This
   phase alone satisfies R1 and R2 for the validator consumer.
2. **Prose scoper and line numbers.** Add the scoper, carry the body start line
   into `Doc`, and make the existing check use both. This is where FC10's code
   fence and line-number defects disappear as a consequence of R4 and R5.
3. **Optional FormatSpec and gate changes.** Change the dispatch signature,
   reject directories, and make FC-CONVENTIONS reachable. Instruction files
   start getting prose checks. Includes the `.md` admission predicate on the
   `None` arm, the two parse-failing SKILL.md fixtures, and a decision on what
   a submodule directory does when passed as an argument.
4. **Vocabulary resolution.** Generalize the header walk, add
   `## Prose Vocabulary:` to shirabe's own CLAUDE.md declaring `tier` and
   `journey`, and suppress accordingly.
5. **Frequency rule.** Add the em dash density rule with its four recorded
   values, notice-level, and file the promotion issue R12 requires before the
   check merges. Merge precondition: a test asserting every prose code appears
   in both `is_known_check_code` and `is_intrinsic_notice` and resolves to
   `Severity::Notice` under both postures. Omitting the code from
   `is_intrinsic_notice` ships it at error level to three adopters pinned at
   `@main` on their next docs PR, which is the exact breaking change R11
   forbids, arriving through a registration list rather than through a
   decision.
6. **Skill and prose reconciliation.** Reduce SKILL.md to guidance plus a
   pointer, delete the BRIEF jury's inline word list, and correct the two stale
   `FC01`-`FC13` prose copies. Also in this phase: repoint the 12 repo-relative
   `skills/writing-style/SKILL.md` references that other skills carry; add the
   CI check the acceptance criteria require, failing when a word-list-shaped
   literal appears under `crates/**` or `skills/**` outside the rule source; and
   update `skills/writing-style/evals/evals.json`, both because CLAUDE.md
   requires evals whenever a skill changes and because the acceptance criterion
   for rule propagation to the drafting consumer IS an eval. Run the existing
   evals against the rewritten SKILL.md before merging.

**Check code.** One code, `FC10`, keeps emitting for every prose rule including
the frequency rule, which is how R14's "exactly one prose check code" holds
once the frequency rule exists. Rules are distinguished within the finding
message, not by code. This discharges R13's conditional half trivially: no code
is added, so no registration list changes, and the acceptance criterion's
registration-list test guards future additions rather than this one. R15 is
likewise vacuous here and recorded as such: nothing is retired.

Phases 1 through 3 are prerequisites for 4 and 5. Phase 6 depends on 1.

### Golden fixtures move, and the phase plan owns it

An earlier revision of this design claimed each phase leaves the tree green
without checking what the frozen parity fixtures assert. That claim was false.
Three fixtures change behavior and the phases that change them must amend the
expectations in the same commit.

| Fixture | Asserts today | Phase | Becomes |
|---|---|---|---|
| `corpus/real/DESIGN-gha-doc-validation.md` | one SCHEMA notice; the file is schema-skipped and contains `Tier` at line 161 | 3 | SCHEMA notice plus prose findings, once prose runs above the schema gate |
| `corpus/real/BRIEF-shirabe-strategy-skill.md` | empty stdout, exit 0; carries 8 em dashes | 5 | an em dash density finding |
| `corpus/real/PRD-roadmap-skill.md` and `corpus/real/ROADMAP-strategic-pipeline.md` | empty stdout; 3 em dashes each | 5 | depends on their word counts against the 10-per-thousand threshold; recompute rather than assume |
| `corpus/synthetic/README-unrecognized-format.md` | documents the current skip as intended behavior | 3 | its prose is now wrong and must be rewritten, not re-baselined |

The last one matters most. That fixture's prose asserts the defect is the
design. Re-baselining it silently would leave a file in the tree explaining
that a fixed bug is correct behavior.

The parity contract against the Go implementation is frozen, so these fixtures
cannot simply be re-recorded. The phase that moves each one either migrates it
to a Rust-owned expectation set or adds a documented exemption naming this
design. Which of the two is an implementation decision; doing neither is not
available.

## Security Considerations

The capability reads two new inputs from a repository under check: a rule file
from shirabe's own tree and a vocabulary header from an arbitrary adopter's
CLAUDE.md. Both are parsed, neither is executed.

**Untrusted vocabulary input.** The header value comes from a repository the
validator may not own. It is split on commas, trimmed, lowercased, and used
only as literal match terms, never compiled into a pattern. Compiling adopter
input as a regex would be a denial-of-service surface through catastrophic
backtracking; the design forbids it. The value is size-capped following the
existing `--custom-statuses` precedent.

**The header walk's reach.** `resolve_claude_md_header` canonicalizes the
document path before walking, so `..` resolves before any ancestor is read, and
the walk terminates at the filesystem root. Neither property bounds it to the
repository, and the shipped `resolve_doc_visibility` has demonstrated bypasses
on both counts. Two are addressed rather than accepted: the walk stops at the
first directory containing `.git`, so a `## Prose Vocabulary:` declared above a
repository root cannot suppress findings inside it, which is what R10 requires;
and a CLAUDE.md whose canonicalized path escapes that bound is ignored, so a
committed symlink cannot redirect resolution outside the repository. This
change corrects the existing behavior as well as governing the new reader.
Unlike visibility, which `--visibility` can mask in CI, there is no vocabulary
flag, so the walk is always live.

**The prose rules are advisory, not a control.** Matching is ASCII-literal.
Homoglyph, fullwidth, zero-width, and Turkish-dotted-I variants do not match and
are out of scope. Nothing may be gated on the prose family without revisiting
this, because a writer who wants to evade it can.

**Rule-source parsing.** `saphyr` is already trusted for frontmatter across the
same corpus. The rule file is shirabe's own, arriving at the same commit as the
binary, so it is not an adopter-controlled input.

**Rejected as a security consideration.** Option A would have added a 40 MB
third-party binary to every adopter's CI runner and a `vale sync` step fetching
style packages over the network at build time. That is a supply-chain surface
the chosen design does not have. It is recorded here because it was a real
difference between the options, not to relitigate Decision 1.

## Consequences

**Positive.** Three rule copies become one, read at enforcement time, so the
divergence that produced this chain cannot recur silently. Three silent-success
defects in one gate are fixed together rather than left behind a change that
touches them. The 33 files currently running zero checks start being checked.
Adopters get the capability with no workflow edit and no new dependency.

**Negative.** shirabe takes on markdown scoping it did not previously own, and
that code is the most likely place for a future correctness bug. The mitigation
is that its output is measured against Vale's on the real corpus rather than
asserted: 483 findings against Vale's 489 across 147 files, with 14 findings of
gross disagreement spread over 12 files. The disagreements are not uniformly in
the native scoper's favour, and an earlier revision of this design said they
were. One is Vale reporting inside a construct R4 excludes; the rest are
nested-list segmentation differences that nobody has adjudicated, and in four
of those files the native scoper finds more, not fewer.

Three constructs the 90-line scoper does not handle: setext headings,
reference-style links, and raw HTML blocks. None appears in the corpus it was
measured on, which is why the agreement number is high and also why the number
is not a guarantee about prose the corpus does not contain.

A second mitigation is that the scoper's correctness is now a testable property
with a reference implementation available to diff against, which FC10's absent
scoping never was.

The `FormatSpec` signature change touches the crate's central entry point. The
counter-argument raised in Decision 4 is fair, that a sibling function would
give the same compile-time guarantee without an `Option` in the public API, and
it is recorded in the report rather than dismissed.

**Neutral.** The check code keeps a name that no longer describes what it does.
That cost was accepted in the PRD's decisions and is not revisited here.

Adopter instruction-file coverage still needs a pull request against each
adopter, because koto, niwa, and tsuku all filter their caller workflows on
`paths: ['docs/**']` and shirabe cannot widen that from its side. R20's first
clause holds without adopter action: artifact coverage arrives on the next docs
PR. Its second clause does not, and that is a property of the adopters' own
configuration rather than something this design can discharge.
