---
schema: design/v1
status: Current
upstream: docs/prds/PRD-writing-style-enforcement.md
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
  An external linter buys a rule engine worth roughly two true positives across
  554,000 words, at the cost of a third-party binary and a network style fetch,
  and its frequency rule would still be hand-written in Tengo on a runtime that
  panics rather than degrades. The one feature worth having from it, a real
  CommonMark parse, is available as a crate that adds no CI step. Three
  stronger-sounding objections to the linter were withdrawn under review and
  are recorded as withdrawn in Decision 1.
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
would otherwise hand-write. Rejected, but not on the grounds an earlier revision
of this document gave.

That revision rested the rejection on three findings and called them
"in descending order of how hard they are to argue with." A review argued with
all three and was right about each. They are recorded here as withdrawn rather
than deleted, because this document is the one the next person will cite, and a
reader who finds only the surviving argument cannot tell whether the others were
considered or quietly dropped.

*Withdrawn: R18 forbids it.* The requirement says the capability adds no
install, fetch, download, or package-manager step to an adopter's CI. But
`validate-docs.yml` already installs a Rust toolchain, restores a cargo cache,
fetches the crates.io dependency tree, builds from source, and installs a binary
to `/usr/local/bin`. The workflow is made of those steps. Treating one more as
categorically forbidden, while defending `--rules <path>` in the same file as
"an argument, not a step," is a distinction the requirement does not support.
R18 states a real preference about adopter cost; it is not a constraint that
ends the discussion, and presenting it as one made the section read as
reverse-engineered from the conclusion.

*Withdrawn: Vale cannot read shirabe's skill tree.* It exits 2 with zero
findings across the 211 files under `skills/` because two of them carry an
unquoted scalar containing `: `, which is invalid YAML. PyYAML rejects both at
the same position. Vale was correctly diagnosing broken files in this
repository, and the earlier revision not only mistook that for a Vale
limitation but pinned the two broken files as fixtures for a fallback path.
They are repaired now.

*Withdrawn: R4 and R6 are mutually exclusive under Vale.* The component claims
hold — `metric` exposes no punctuation count, and a `script` sees whole-document
text only at `scope: raw`. The conclusion does not. The rate need not be
computed inside Vale: a script at a markup-aware scope can emit per-block word
and dash counts, and the Rust that already parses Vale's JSON can sum them.
Measured over 151 files, that route lands within one percent of ground truth,
with eight verdict disagreements at the shipped threshold. The original
investigation instrumented the per-block script, printed its counts, and stopped
one step short of summing them.

**What actually rejects it.** Three things, none of them a blocking constraint,
which is why the conclusion is a judgment rather than a deduction.

The rule engine buys almost nothing here. Vale's word and phrase matching
produces roughly two true positives across 554,000 words of this corpus, at 1.7%
raw precision. A third-party binary and a network style fetch is a poor trade
for an engine that would run green forever, and the supply-chain surface it adds
is real where the native path has none.

The frequency rule would still be hand-written, just in a worse language. Under
the aggregation route above, the block filtering that keeps frontmatter scalars
and table cells out of the denominator is code someone writes either way, and
under Vale it is Tengo on a runtime that panics on an out-of-range span rather
than degrading.

And the one feature worth having from Vale — a real CommonMark parse — is
available without Vale. See Option D.

**Option C, a split.** Native for CI, external for a local authoring loop.
Rejected because it doubles the rule-source problem it is meant to help: two
engines means two rule representations, or one representation and a translation
layer, and R1 and R2 exist to stop exactly that.

**Option D, a CommonMark parser crate with a native rule engine.** Chosen, and
absent from the original option space, which framed the decision as a 40 MB
external binary against hand-rolled line heuristics. That framing was wrong and
a review supplied the missing third option.

`pulldown-cmark` with default features off adds two crates and no workflow step,
because cargo already fetches the dependency tree during the build CI already
runs. It defeats R18 on R18's own terms, which is the clearest evidence that
R18 was never the real objection.

The hand-rolled scoper it replaced was measurably wrong in two ways, both of
them instances of the defect class this capability exists to end. A fenced block
whose first content line is itself a fence marker inverted: code was linted as
prose and the prose after it was skipped, a false positive and a false negative
in one file. A document opening with a `---` thematic break had everything up to
the next `---` consumed as frontmatter and never checked, while the file
reported success. Both are now regression tests.

It was also imprecise where precision is load-bearing. This design justifies a
threshold of 10 per thousand on the grounds that scoping precision changes
outcomes there, and used that same argument against Vale's raw-scope script. The
hand-rolled scoper disagreed with a correct parse on 11 files at that threshold
and inflated the word denominator by about 3%, which understates every rate it
reports. On this repository's own corpus it counted 3,298 words where a correct
parse counts 3,195. The precision standard used to reject the alternative was
not met by the implementation built to replace it.

`regex` and `saphyr` were already direct dependencies, so the rule matching and
the rule source needed nothing new; the parser is the only addition.

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

**Prose scoper.** Prose spans from a `pulldown-cmark` parse: fenced and
indented code, inline code, HTML, link and image destinations, table cells, and
frontmatter excluded; headings included. Link *labels* are prose because they
are words a reader reads. Bare URLs are dropped by token shape, since
CommonMark does not autolink them and the parser hands them back as text.

Walking a real parse rather than matching lines is the correction a review
forced. The hand-rolled version was about 90 lines and was wrong on two
constructs in ways that both instantiate the defect class this capability
exists to end; Decision 1's Option D records them.

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

**Negative.** shirabe takes on prose scoping it did not previously own. The
risk is much smaller than it was under the hand-rolled version: the markup
questions are answered by a CommonMark parser rather than re-derived one bug
report at a time, and the constructs that version silently mishandled —
setext headings, reference links, raw HTML, nested fences — are the parser's
problem now.

What remains shirabe's own is the decision layer: which node types count as
prose, whether link labels are prose while destinations are not, whether
headings enter the frequency denominator. Those are judgment calls, they are
each a test, and they are where a future correctness bug will live.

The cost of that correctness is a dependency where there was none: two crates,
`pulldown-cmark` and `unicase`, with default features off. That is the trade,
and it is worth naming plainly rather than presenting the parser as free.

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
