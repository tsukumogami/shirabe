---
schema: design/v1
status: Planned
problem: |
  Prose references to a durable artifact break when the artifact reaches its
  terminal state and moves, and nothing reads a path out of prose. The hard
  part is not finding unresolvable paths -- 140 of the corpus's 421
  artifact-shaped paths do not resolve -- but separating the 21 that are
  broken references from the 119 that are template placeholders, eval fixture
  names, and paths to working artifacts the cascade deleted on purpose.
decision: |
  A new notice-level `FC18` in the schema-independent prose arm reports a
  body-prose reference whose path names no file when a file of the same
  basename exists in another artifact directory of the same repository. The
  surviving basename is the discriminator: it is a property of the target
  rather than of the referring file, so it separates the two populations
  without scoping by directory or by section, and it hands the finding the new
  path. Extraction is a second selection over the CommonMark parse `prose.rs`
  already runs, taking the inline code spans and link destinations that module
  excludes and excluding the fenced blocks it also excludes.
rationale: |
  Every alternative discriminator fails on measured corpus data: directory
  scoping misses two genuine defects in `skills/` and admits ~60 placeholders
  in `docs/`; `## References`-section scoping misses 12 of the 21; a
  placeholder-name denylist is a second corpus to maintain. Surviving-basename
  resolution scores 21 true positives and 0 false positives on the whole tree,
  costs one directory scan, and produces an actionable finding. Notice
  severity is staging, not a verdict -- the defect earns error level by the
  repo's own promotion rule and gets there in a one-line diff once the 21
  inherited findings are cleaned.
upstream: docs/prds/PRD-prose-reference-staleness.md
user_visible_surface: false
---

# DESIGN: prose-reference-staleness

## Status

Planned

## Context and Problem Statement

`shirabe transition <design> Current` git-mv's a DESIGN from `docs/designs/`
into `docs/designs/current/`, and supersession moves it again into
`docs/designs/archive/`. The transition rewrites the moving document's own
frontmatter and status; it touches no other file. Every document that named
the old path in prose is wrong from that moment.

The frontmatter half is closed. `check_upstream_resolves` (R6) reports a
dangling `upstream:`, and `check_upstream_legality` (R10/R11) refuses the
illegal edges at authoring time. Both are structural checks: they run inside
`validate_structural`, which returns early behind the schema gate, and the
comment above the R10/R11 call says why in as many words -- the check
presupposes an artifact schema, so it cannot move to `validate_prose`, which
runs for every markdown file including schema-less ones.

Prose has no equivalent, and prose is where several edges are required to
live. A BRIEF may not name a DESIGN in `upstream:`, so a brief spawned by a
parent design records that parent in prose or nowhere. PLAN is the only format
whose `legal_upstream` includes DESIGN, and a PLAN is a working artifact the
cascade deletes in the same run that moves the design -- so after a terminal
transition, prose holds the whole inbound record.

### What the corpus says

Every number below was measured at the branch point (`3d5c20c`) over the files
`git ls-files` reports under `docs/`, `skills/`, and `references/`. The method
is in the Implementation Approach section, and rerunning it is a requirement
rather than a nicety: pull-request CI validates only a diff's files, and that
blind spot is how 21 stale references accumulated in documents that all
validate clean.

Artifact-shaped paths of the form `docs/.../<TYPE>-<name>.md`, by the markdown
context they sit in:

| Context | Occurrences | Do not resolve | Relocated |
|---|---|---|---|
| Inline code span | 272 | 79 | **21** |
| Plain prose | 95 | 10 | 0 |
| Fenced code block | 54 | 51 | 0 |
| **Total** | **421** | **140** | **21** |

"Relocated" means the written path names no file and a file of the same
basename exists elsewhere in the artifact directories. Those 21 are the whole
defect population, and their shape decides most of this design:

- All 21 are inside inline code spans. None is in a fenced block, and none is
  in plain prose.
- 19 are under `docs/` and 2 are in instruction files under `skills/`
  (`skills/plan/references/plan-to-tasks-contract.md:199` and
  `skills/scope/references/phases/phase-3-exit-finalization.md:352`). Both are
  genuine references, not examples.
- Only 9 of the 21 sit under a `## References` heading. The other 12 are under
  Goals, Requirements, Downstream Artifacts, Related, Questions Deferred to
  Design, and Mode-Specific Behavior.
- Five designs account for all of them:
  `DESIGN-roadmap-plan-standardization` (10),
  `DESIGN-shirabe-scope-skill` (5), `DESIGN-shirabe-progression-authoring`
  (4 -- all in one PRD), `DESIGN-shirabe-artifact-decision-contract` (1), and
  `DESIGN-issue-outlines-one-parser` (1).

The other 119 non-resolving paths are what a naive check would report as
defects. They are template placeholders (`DESIGN-foo.md` 11 times,
`PLAN-foo.md` 12, `PRD-foo.md` 8, `VISION-foo.md` 5, plus roughly thirty
one-off fixture names), and paths to working artifacts the cascade deleted on
purpose (`PLAN-roadmap-plan-standardization.md` 17,
`ROADMAP-strategic-pipeline.md` 6). A check that reports all 140 is a check
someone disables.

Three smaller facts constrain the mechanism. Three references are written
relative to their own file (`../prds/PRD-scope-completion-cascade.md` from
`docs/designs/current/`) and resolve correctly, so a check that anchors every
path at the repo root reports all three as broken. 171 mentions under `docs/`
name a document by basename alone, which no relocation can invalidate. And one
stale reference lives in a shell-script comment
(`skills/plan/scripts/plan-to-tasks.sh:428`), outside anything the validator
parses as markdown.

## Decision Drivers

**D1 -- False positives are fatal, not costly.** The ratio at stake is 21
useful findings against 119 useless ones. A check at that ratio is turned off,
and the ratio is the design problem rather than a tuning parameter.

**D2 -- Instruction files carry real references.** Two of the 21 are in
`skills/`, so a check gated on artifact frontmatter misses them. Both
populations -- corpus documents and instruction files -- contain both real
references and examples, so no file-location scope separates them.

**D3 -- The finding has to name the new path.** The reader's next action after
"this path is wrong" is the basename search the check already performed.

**D4 -- The CLI surface is closed.** New correctness rules belong in `shirabe
validate` as a check code or a mode, never as a subcommand. A subcommand that
renders or creates has been reverted in this repo once already.

**D5 -- The corpus is dirty on arrival.** Twenty-one inherited findings mean an
error-level check turns CI red the day it lands.

**D6 -- Byte-stable output.** The Layer-1 golden parity test pins stdout,
stderr, and exit code per fixture, and the reusable parity workflow makes the
same assertion for downstream adopters. A new finding on a pinned fixture
breaks it.

**D7 -- One parse, not two.** `prose.rs` already runs a CommonMark parse to
scope the writing-style rules, and the module's own header records what
hand-rolled fence detection cost the last time someone tried it.

## Considered Options

### Decision 1 -- What separates a real reference from an illustrative one

**Option 1A: surviving-basename resolution.** Report only when the written
path names no file AND a file of the same basename exists in one of the
artifact directories. **Chosen.** Measured over the whole tree: 21 findings,
all of them genuine; 0 findings on the 119 placeholders, fixture names, and
deleted-working-artifact paths. It discriminates on a property of the target
rather than of the referring file, which is why it works identically in
`docs/` and in `skills/`, and the surviving file is exactly the fact D3 wants
in the message.

**Option 1B: scope the check to files under `docs/`.** Rejected on data. It
misses the two genuine defects in `skills/` and still admits roughly 60
placeholder paths that live inside `docs/` itself -- `DESIGN-foo.md` appears
11 times there. The scope is intuitive and does not correlate with the thing
being separated.

**Option 1C: scope the check to `## References` sections.** Rejected on data,
harder: only 9 of the 21 sit under that heading. A reference in a PRD's Goals
section is the same defect with the same fix, and this option is silent on 12
of them.

**Option 1D: a placeholder-name denylist (`foo`, `bar`, `thing`, `my-*`,
`x`).** Rejected. It is a second corpus to maintain, it does not cover the
one-off fixture names (`DESIGN-cascade-test-short.md`,
`DESIGN-authentication-system.md`), and it fails open -- a new placeholder
nobody adds to the list becomes a false positive in a document unrelated to
whoever wrote the list.

**Option 1E: ask git whether a file ever existed at the written path.**
Rejected, and it is the option most worth rejecting explicitly, because it is
the more correct model. `git log --diff-filter=D` would distinguish a
relocation from a name that never existed with no dependence on basenames
surviving. It costs a subprocess per candidate reference against 421
candidates, and it answers a broader question than this design asks: a
reference to a deliberately deleted PLAN would also resolve as "existed once,"
and that is the separately-tracked fault this PRD puts out of scope. Option 1A
gets the same 21 findings for one directory scan.

### Decision 2 -- How references are extracted from a file

**Option 2A: a second selection over the CommonMark parse `prose.rs` already
runs.** **Chosen.** Take inline code spans, link destinations, and plain text;
exclude fenced and indented code blocks. The measured split makes this exact:
all 21 true positives are in inline code spans, and 51 of the 140
non-resolving paths are inside fenced blocks, where they are worked examples
by construction. Excluding fenced blocks costs nothing and removes 36% of the
candidate set.

**Option 2B: reuse `prose::prose_spans` as it stands.** Rejected, and it is
the tempting wrong answer. That module deliberately excludes inline code spans
and link destinations, because a writing-style rule must not fire on a path.
This check is its mirror image: the paths *are* the subject. Reusing it finds
0 of the 21.

**Option 2C: a raw line regex over the body.** Rejected. It fires inside
fenced blocks -- 51 occurrences today, every one of them illustrative -- and
`prose.rs`'s own header records the two specific bugs hand-rolled fence
detection produced the last time it was attempted here.

### Decision 3 -- What a written path resolves against

**Option 3A: repo root discovered per file, by canonicalizing the referring
file and walking up to the directory containing `.git`; relative forms (`./`,
`../`) resolve against the referring file's own directory instead.**
**Chosen.** The idiom is already in this crate: `resolve_claude_md_header`
walks exactly that way with `stop_at_repo_root`, and `check_writing_style`
resolves a repository's declared vocabulary per file for the stated reason
that one invocation may span two repositories. Handling the relative forms
separately is what keeps the three correct `../prds/...` references silent.

**Option 3B: resolve against the process working directory, as R6 does.**
Rejected. It is the older idiom and it is wrong for a multi-repo invocation:
a `docs/` path in a file from another checkout would resolve against this
one's tree, which is how a false finding gets manufactured out of an unrelated
repository's corpus. R6 is not changed here -- that would move parity bytes for
no benefit this design needs.

**Option 3C: skip relative forms entirely.** Rejected as a silent coverage
hole. The three that exist resolve today, but the form is legal and a future
relative reference would be invisible. Resolving them costs a `join` on the
referring file's parent.

### Decision 4 -- Which family, which code, and where the check runs

**Option 4A: a new `FC18` registered in `validate_prose`.** **Chosen.**
`validate_prose` is the schema-independent arm that runs for every markdown
file the validator is handed, including files with no frontmatter and no
artifact prefix -- which is the only way to reach D2's two defects in
`skills/`. FC10 (writing style) and `FC-CONVENTIONS` already live there, so
the FC family, not the R family, is the precedent for a schema-independent
check. `FC18` is the next free code: `is_known_check_code` runs `FC01`-`FC17`
today.

**Option 4B: an `R12` alongside R6 and R10/R11.** Rejected. The R6-R11 family
is thematically right -- these are cross-document resolution rules -- and
mechanically wrong. All of them run in `validate_structural`, behind the schema
gate, and the comment above the R10/R11 call states the rule directly: a check
that presupposes an artifact schema belongs there and not in `validate_prose`.
A prose check that must read schema-less instruction files is the exact
converse, so it belongs on the other side of that line, and the code should say
so.

**Option 4C: an `L`-code inside the `--lifecycle` tree walk.** Rejected,
though it has one real advantage: the lifecycle mode walks the whole tree, so
it would catch a stale reference in a file no pull request touched. It also
walks only `docs/{briefs,prds,designs,designs/current,plans,roadmaps}` and
parses only prefixed artifact documents, so instruction files, `docs/guides/`,
and `docs/designs/archive/` are all invisible to it. One of the 21 findings is
in `docs/guides/RELEASE-NOTES-artifact-decision-contract.md`. Making the
lifecycle index cover those directories is a larger change than this defect
justifies, and the whole-tree gap is recorded as a consequence instead.

**Option 4D: a new `shirabe check-references` subcommand.** Rejected by D4.

### Decision 5 -- Severity, and what unblocks promotion

**Option 5A: ship `FC18` in `is_intrinsic_notice`, clean the 21 in a
follow-on, promote by deleting one arm.** **Chosen.** The staging matches
`FC07`-`FC15`, whose arms in that match expression carry the comment naming
them "notice-level additions pending their respective corpus-cleanup PRs."

**Option 5B: ship at error level and clean the corpus in the same change.**
Rejected on ordering. The cleanup is defined by what the check reports, so the
check has to exist and run before the cleanup can be scoped -- and a single
change that adds a check, edits 21 files across 15 documents, and turns CI red
if either half is wrong is a change nobody can review as one thing.

**Option 5C: ship at error with an exemption list.** Rejected. The exemption
list is a second corpus, it needs its own staleness rule, and every entry is a
reference somebody should have fixed.

It is worth being explicit that the notice is staging and not a judgment about
the defect. `DESIGN-issue-outlines-one-parser` records the repo's promotion
rule: a finding earns error level when the failure it describes is silent and
permissive, and stays a notice when the failure already refuses loudly. A
stale prose reference is the textbook silent-and-permissive case -- the
document validates clean and the reader finds out by clicking. By that rule
`FC18` should be an error, and the only thing standing between it and error
level is 21 inherited findings.

## Decision Outcome

`FC18` lands in `validate_prose` as a notice. For each markdown file the
validator is handed, a new extractor takes a second selection over the same
CommonMark parse `prose.rs` runs -- inline code spans, link destinations, and
plain text, with fenced and indented code blocks excluded -- and yields
candidate path strings with their file lines. Candidates that do not look like
`<dir>/<TYPE>-<name>.md` are dropped. Each surviving candidate is resolved:
`./` and `../` forms against the referring file's directory, everything else
against the repo root found by walking up from the referring file to `.git`.
A candidate that resolves produces nothing. A candidate that does not resolve
is looked up by basename across the artifact directories, including
`docs/designs/archive/`; a hit is the finding, and it names the referring file,
the line, the path as written, and the path that exists.

The check reads `doc.body` only. R6 owns the frontmatter half, and keeping the
two halves on separate sides of the frontmatter boundary is also what leaves
the golden parity corpus untouched: all three artifact-shaped paths in it are
`upstream:` values, and one of them is `DESIGN-roadmap-plan-standardization.md`
under the pre-move `docs/designs/`, which a frontmatter-reading check would
turn into a new finding on a pinned fixture.

The pieces fit because each half of the decision answers a different question
and neither leaks into the other. The extractor decides *where in a file* a
path counts, and it is a selection over a parse that already exists. The
resolver decides *which paths are defects*, and it does so entirely from the
state of the target. Adding a new artifact directory means one entry in one
list; adding a new place references are written means one arm in the
extractor's match.

## Solution Architecture

### The extractor

A new function alongside `prose::prose_spans`, taking the same inputs and
returning a different projection:

```rust
/// A path-shaped candidate and the file line it sits on.
pub struct RefSpan {
    pub line: usize,
    pub text: String,
}

/// Path-bearing spans for a document body: inline code spans, link
/// destinations, and plain text. Fenced and indented code blocks are
/// excluded.
pub fn reference_spans(body: &[String], body_start_line: usize) -> Vec<RefSpan>
```

The relationship to `prose_spans` is deliberate and should be stated in the
module header: the two functions partition the same parse by opposite
criteria. `prose_spans` excludes code spans and link destinations because a
writing-style rule must not fire on a path; `reference_spans` includes them
because the paths are what it reads. Both exclude fenced and indented code.
The overlap is plain text, which both take, and which contributes zero
findings today but is the form a future reference could take.

### The candidate filter

A candidate is a substring matching a path shape whose final component starts
with a known artifact prefix and ends in `.md`. The prefix set is derived from
`formats()` rather than written out, so a new artifact type is covered by
adding it to the formats map, and the same longest-prefix logic `detect_format`
uses decides what counts.

Two candidate classes are dropped before resolution:

- **Cross-repo references** in the `owner/repo:path` convention. There is no
  local path to resolve, exactly as `check_upstream_resolves` skips them.
- **Absolute paths.** They are not a form this corpus uses and resolving them
  would let a finding depend on the host filesystem.

### The resolver

```
repo_root(file)          -> canonicalize(file), walk parents to the one
                            containing `.git`; None if there is none
resolve(candidate, file) -> if candidate starts with `./` or `../`:
                                file.parent().join(candidate), normalized
                            else:
                                repo_root.join(candidate)
```

A file with no `.git` ancestor yields no findings rather than an error: the
check needs a repository to know what an artifact directory is, and the
validator is expected to run against loose files.

### The target index

One scan per validation run, memoized, over the artifact directories:

```
docs/briefs  docs/prds  docs/designs  docs/designs/current
docs/designs/archive  docs/plans  docs/roadmaps  docs/strategies
docs/visions  docs/competitive
```

The list is `build_doc_index`'s directory list plus `docs/designs/archive/`
and the four directories this repo does not have but the format set defines.
The archive entry is load-bearing rather than defensive: supersession is one of
the two transitions this check exists for, and without it a superseded design
is indistinguishable from a deleted one.

The index maps basename to the sorted list of paths carrying it. When a
basename has more than one entry, the finding names all of them in path order,
so the output stays deterministic and the reader is told about the ambiguity
rather than handed one arbitrary resolution. No basename collides today.

The scan is memoized per repo root for the lifetime of a validate run. A
multi-file invocation spanning two repositories gets one index per repository,
which is the same per-file-repo discipline `check_writing_style` follows for
prose vocabulary.

### The finding

One `ValidationError` per occurrence, `code: "FC18"`, `line` set to the file
line the reference sits on, and a message carrying the four facts from R2.
`FC18` is added to `is_known_check_code` so `--check FC18` selects it, and to
`is_intrinsic_notice` so it resolves to a notice under both postures. It is
absent from `posture_class`'s draft-tolerable arm, which is correct: it is not
a legitimate intermediate state while a chain is being drafted, it is just not
yet promoted.

### Test-harness shape

Unit tests cover the extractor against the three contexts (a path in a fenced
block, in an inline code span, in plain text) and the resolver against the four
outcomes (resolves, relocated, unresolvable basename, cross-repo). A
corpus-level test asserts the check's finding count over the repository's own
tracked markdown matches the recorded figure, which is what makes R7's
measurement a regression test rather than a one-off. The three parity suites
are unaffected by construction, and a test asserting `effective_severity`
returns `Notice` in both postures pins the staging so the promotion is a
deliberate edit rather than a side effect.

## Implementation Approach

**The measurement procedure**, run before and after and recorded in the PLAN:

```bash
git ls-files '*.md' \
  | xargs shirabe validate --format json --check FC18 \
  | jq -r '.findings[] | [.file, .line, .code, .message] | @tsv' \
  | sort
```

Before the check exists, the same figures come from the enumeration this
design's tables were built from: extract artifact-shaped paths per file,
test each against disk, and partition the misses by whether the basename
survives elsewhere. Both forms are cheap and the second is what produced the
421/140/21 split above.

**Batch 1 -- the extractor.** `reference_spans` plus its unit tests, with no
check wired up. It lands alone because it is the piece with a parser behind it
and the piece whose contexts have to be right before any count means anything.

**Batch 2 -- the check.** The candidate filter, the resolver, the memoized
target index, `FC18` registered in `validate_prose`, `is_known_check_code`, and
`is_intrinsic_notice`. The corpus-count test lands here, pinning 21.

**Batch 3 -- the cleanup.** Fix the 21 references the check reports. It is
mechanical, it is reviewable as a diff of paths, and it is separate because it
touches 15 documents and the check touches none.

**Batch 4 -- the promotion.** Delete the `FC18` arm from
`is_intrinsic_notice` and flip the severity test. One line plus its test,
gated on batch 3 landing.

The batches are sequential and each is independently reviewable. Batches 3 and
4 are the ones a maintainer may reasonably defer; the check is useful at notice
level from batch 2 onward, and the corpus-count test keeps the number honest
in the meantime.

## Security Considerations

**Path traversal through a written reference.** A candidate is a string from a
document body and it becomes a filesystem read. The mitigation is the one
`build_doc_index` already uses: resolve, canonicalize, and require the result
to stay under the repo root. A `../../../etc/passwd` candidate fails the
artifact-prefix filter first and the containment check second, and either way
the check's only action on a resolved path is an existence test -- it never
reads content and never writes.

**Symlink escape.** A symlink under `docs/designs/current/` pointing outside
the tree could put an out-of-tree path into a finding message. Canonicalizing
target-index entries and dropping any that escape the root closes it, matching
`build_doc_index`'s L05 handling.

**No subprocess, no network.** Unlike R6, this check shells out to nothing. The
target index is a directory read. That is a deliberate difference: R6 runs
`git ls-files` once per upstream entry against a handful of entries per
document, while this check would face 421 candidates.

**Message injection into the annotation stream.** The finding message embeds a
path taken from document text, and the annotation format is line-oriented. The
existing sanitization the golden fixture `DESIGN-sanitize-newline-injection.md`
pins applies unchanged; the new message must route through the same escaping as
every other finding rather than formatting bytes of its own.

**Denial of service by candidate volume.** A document could contain thousands
of path-shaped strings. The per-file work is one directory index (shared) plus
one hash lookup per candidate, so the cost is linear in document size with a
small constant. The writing-style check already truncates at a finding cap;
`FC18` should adopt the same cap rather than inventing a second policy.

## Consequences

### Positive

The 21 stale references become visible, with their fixes attached, in a
validation run an author already performs.

The discriminator is measured rather than argued. Anyone can rerun the
procedure and get 21, and the corpus-count test fails when the number moves for
any reason, including a reason nobody predicted.

Instruction files gain reference coverage they have never had. Two of the 21
are in `skills/`, and neither is reachable by any check that reads frontmatter.

The promotion is one line at a seam that already exists and already carries
five other checks through the same staging.

### Negative

**A deliberately deleted document is indistinguishable from one that never
existed.** Both leave no surviving basename, and both stay silent. This is the
boundary the PRD draws on purpose, and it means the larger population -- prose
paths naming cascade-deleted PLANs and ROADMAPs -- is untouched by this work.

**Coverage still follows the diff.** Pull-request CI passes changed files, so a
reference in a file the PR does not touch is not re-checked. The corpus-count
test is the compensating control, and it runs on every `cargo test` rather than
on the documents themselves. Whole-tree per-file validation is the real fix and
is not in this design.

**The self-caller workflow does not fire on `skills/`-only changes.**
`validate-shirabe-docs.yml` triggers on `docs/**`, `crates/**`, and the Cargo
files, so a stale reference introduced into an instruction file alone is caught
on the next unrelated run. Pre-existing, and now more visible because the check
finally reads those files.

**A document that quotes a stale path cannot be told from one that refers to
it.** This is the sharp edge of Decision 1: the discriminator reads the target,
so a path written as an example of a broken reference looks exactly like a
broken reference. This chain hit it immediately. The first draft of these
documents spelled the pre-move path of `DESIGN-shirabe-scope-skill.md` and
`DESIGN-roadmap-plan-standardization.md` out in full while explaining what the
check reports, which would have added three findings to the corpus and made a
specification of the check into a violation of it.

Two mitigations are available and both are cheap. A path written inside a
fenced code block is outside the extractor by construction, which is what the
fenced-block exclusion is for. And a path split into a basename and a directory
(`DESIGN-<name>.md` under `docs/designs/`) is not a path token at all, which is
what these documents do -- it reads better in a sentence than a fence does. An
author who wants the literal and accepts the finding has neither, and that is
the honest limit of what a target-side discriminator can offer.

**A basename collision would produce an ambiguous finding.** None exists today.
The mitigation is to name every match rather than guess, which trades a
shorter message for an honest one.

**Downstream parity workflow callers see a new finding.** The reusable
`parity-check.yml` asserts the Rust binary reproduces a Go baseline frozen at
`20fb8ed`, and any check added since then diverges from it. `FC16` and `FC17`
already did. Nothing in this repo's own CI calls that workflow; the note
belongs in the release notes for adopters who pin it.

### Neutral

An eval cascade `git mv`s fixture designs into `docs/designs/current/` at
runtime, so the target index can transiently contain a fixture basename. The
case is unreachable today -- every rooted reference to a fixture design is in a
shell script, which this check does not read -- and the mitigation if it ever
fires is the exclusion `scripts/check-no-fixture-design-leak.sh` already
computes.

R6 keeps resolving against the process working directory while `FC18` resolves
per file. The divergence is recorded rather than fixed: changing R6 would move
parity bytes for no gain this design needs, and the two checks read different
halves of the document.

## References

- `docs/prds/PRD-prose-reference-staleness.md` — the requirements this design
  implements.
- `crates/shirabe-validate/src/validate.rs` — `validate_prose`, the
  schema-independent arm Decision 4 places the check in, and
  `is_intrinsic_notice`, the promotion seam Decision 5 uses.
- `crates/shirabe-validate/src/prose.rs` — the CommonMark parse Decision 2
  takes its second selection over, and the module header recording what
  hand-rolled fence detection cost.
- `crates/shirabe-validate/src/visibility.rs` — `resolve_claude_md_header`, the
  per-file repo-root walk Decision 3 reuses.
- `crates/shirabe-validate/src/lifecycle.rs` — `build_doc_index`, whose
  directory list and containment handling the target index extends.
- `docs/designs/current/DESIGN-issue-outlines-one-parser.md` — the promotion
  rule Decision 5 measures this check against, and the `FC17` precedent for
  splitting a code out by severity.
