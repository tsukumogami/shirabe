---
schema: design/v1
status: Proposed
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

Proposed

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

Full report: `wip/design_vale-adoption_decision_1_report.md`. Confidence: high.

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

Full report: `wip/design_vale-adoption_decision_2_report.md`.

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

Full report: `wip/design_vale-adoption_decision_3_report.md`.

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

Full report: `wip/design_vale-adoption_decision_4_report.md`.

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

**Prose scoper.** A markdown-aware extractor producing prose spans from a
document: fenced code, inline code, URLs, table rows, and frontmatter excluded;
headings included. Roughly 90 lines. This is the component the counter-argument
to Decision 1 correctly identifies as the risk, and it is the component whose
output is validated against Vale's on the real corpus.

**Prose check family.** Word and phrase rules over prose spans, plus at least
one frequency rule evaluating a rate against a threshold. All read the parsed
rule source and the resolved vocabulary. Reported through the existing
`ValidationError` shape.

**Header resolution.** `resolve_claude_md_header(path, key)` generalized out of
`visibility.rs`. `resolve_doc_visibility` becomes that call plus its
path-inference tail; `resolve_prose_vocabulary` becomes that call plus a comma
split, trim, lowercase, and empty-drop, with a size cap following the
`--custom-statuses` precedent.

**Dispatch.** `validate_file` takes `Option<&FormatSpec>`. Prose checks run on
both arms, above the schema gate so the 33 files currently emitting "schema
field missing, skipping" are covered. Structural checks run only on the `Some`
arm.

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
   start getting prose checks.
4. **Vocabulary resolution.** Generalize the header walk, add
   `## Prose Vocabulary:` to shirabe's own CLAUDE.md declaring `tier` and
   `journey`, and suppress accordingly.
5. **Frequency rule.** Add the em dash density rule with its four recorded
   values, notice-level, and file the promotion issue R12 requires before the
   check merges.
6. **Skill and prose reconciliation.** Reduce SKILL.md to guidance plus a
   pointer, delete the BRIEF jury's inline word list, and correct the two stale
   `FC01`-`FC13` prose copies.

Phases 1 through 3 are prerequisites for 4 and 5. Phase 6 depends on 1.

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

**Path traversal through the header walk.** The ancestor walk canonicalizes
before resolving and stops at the filesystem root. It reads only files named
`CLAUDE.md` or `CLAUDE.local.md`; the header cannot name a path in this design,
which is one reason Option B was not chosen for Decision 3.

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
is that its output is validated against Vale's on the real corpus rather than
asserted: 483 of 489 paragraph findings agree, and the disagreements are cases
where the native scoper is right. A second mitigation is that the scoper's
correctness is now a testable property with a reference implementation
available, which FC10's absent scoping never was.

The `FormatSpec` signature change touches the crate's central entry point. The
counter-argument raised in Decision 4 is fair, that a sibling function would
give the same compile-time guarantee without an `Option` in the public API, and
it is recorded in the report rather than dismissed.

**Neutral.** The check code keeps a name that no longer describes what it does.
That cost was accepted in the PRD's decisions and is not revisited here.
