---
schema: prd/v1
status: In Progress
problem: |
  A durable artifact's path changes when it reaches its terminal state, and
  `shirabe transition` rewrites only the moving document's own frontmatter.
  Every document that named the old path in prose is wrong from that moment,
  and no check reads prose paths. Twenty-one such references sit in the tracked
  corpus today, in documents that validate clean, and the population grows by
  roughly one document's worth on every terminal transition.
goals: |
  A transition that moves a document repoints its inbound references in the same
  command, so the problem stops recurring. `shirabe validate` reports the
  references that are already broken, names where the document went, and says
  nothing about the illustrative paths that outnumber the real ones six to one.
  The check ships at notice level against the dirty corpus it inherits, with a
  measured count behind that choice and a one-line promotion once it is clean.
upstream: docs/briefs/BRIEF-prose-reference-staleness.md
source_issue: 289
---

# PRD: prose-reference-staleness

## Status

In Progress

The downstream DESIGN owns how a real reference is told apart from an
illustrative one, which check code carries the finding, and where the check
runs inside the validator.

## Problem Statement

Durable artifacts change path when they reach a terminal state. Four
transitions move a file: a DESIGN to `Current` and to `Superseded`, and a VISION
or STRATEGY to `Sunset`. Each runs a real `git mv`. The transition rewrites the
moving document's own frontmatter and status and touches nothing else, so every
document that named the old path is wrong the moment the move lands.

The command that breaks those references is holding both halves of the fix while
it does so. It has the old path, it has the new one, it has the repository root,
and it is already staging a rename. Substituting one path for the other in the
documents that name it is not a judgment call, and leaving it undone means every
future move creates work that only a person can be trusted to notice.

Frontmatter survives this. R6 reports a dangling `upstream:` the next time the
referring file is validated, and R10 and R11 refuse the illegal edges at
authoring time. Prose has no equivalent — no check reads a path out of a
`## References` entry or a paragraph, so a reference that was correct when it
was written goes wrong silently and stays wrong.

That's worse than it sounds, because prose is where several edges are *required*
to live. The `upstream:` legality table won't let a BRIEF name a DESIGN, so a
brief spawned by a parent design records that parent in prose or nowhere. And
PLAN is the only format whose `legal_upstream` includes DESIGN, so the one legal
inbound frontmatter link into a design belongs to a working artifact the cascade
deletes in the same run that moves the design. After a terminal transition,
prose holds the whole inbound record.

The scale is measurable rather than hypothetical. Across every tracked markdown
file at the branch point, 21 references name a path that a document has vacated
and still exists at elsewhere. Nineteen sit under `docs/` — 14 of them naming
`DESIGN-roadmap-plan-standardization` and `DESIGN-shirabe-scope-skill` alone —
and two sit in instruction files under `skills/`. Every one of those files
validates clean today.

What makes this a design problem rather than a chore is that most
artifact-shaped paths in the corpus are examples. Of the 421 such paths in
tracked markdown, 140 don't resolve, and only 21 of those 140 are references
that broke. The remaining 119 are template placeholders (`DESIGN-foo.md`,
`PLAN-foo.md`, `PRD-foo.md`), eval fixture names, and paths to working
artifacts the cascade legitimately deleted. A check that resolves paths against
disk and reports every miss produces 119 false findings on arrival, and a check
with that ratio gets disabled rather than fixed. Nor does directory scoping
rescue it: `docs/` itself carries about 60 placeholder paths, and two of the 21
genuine defects live in `skills/`.

Two smaller shapes also have to survive. Only 9 of the 21 sit under a
`## References` heading — the other 12 are in Goals, Requirements, Downstream
Artifacts, and ordinary body paragraphs — so a References-section-only check
misses more than half of what it's for. And a reference written relative to its
own file (`../prds/PRD-<name>.md`) resolves correctly today; three exist, and a
check resolving every path against the repo root would report all three as
broken.

## Goals

**A move repairs what it breaks.** The transition that relocates a document
repoints the documents that named it, in the same command, and stages them with
the moved file. The author reviews a diff instead of performing an edit that had
one correct answer.

**A relocation is caught before it merges.** For a move that already happened,
or a rename that went around `shirabe transition`, validation reports which
documents still name the vacated path. Nothing about that is available today at
any cost short of a manual repo-wide search that nobody performs.

**The finding is a fix, not a lead.** It names the referring file, the line, the
path as written, and where the document lives now. A finding that only says
"this path is wrong" hands the reader the search that the check just did.

**Silence on everything else.** Example paths in skills, format references, and
templates produce nothing. So do references to documents the cascade deleted —
that's a different fault with a different cause and a much larger population,
and folding it in would change what the check means.

**The severity is a measurement, not a guess.** The corpus count is taken before
the severity is chosen and again after the check lands, over every tracked file
rather than a pull request's diff. Pull-request CI validates only changed files,
and that blind spot is exactly how 21 stale references accumulated unnoticed.

**Promotion is one line.** The check ships as a notice against a corpus that
isn't clean. When the count reaches zero, making it an error is a single-line
change at the promotion seam the staged checks already use, not a rewrite.

## User Stories

**As an author transitioning a design to its terminal state**, I want the
command that moves the file to repoint the documents that named it, so that a
correct move does not leave me a deterministic edit to perform by hand.

**As a reviewer of that transition's commit**, I want the repointed files staged
alongside the moved one and named in the command's output, so that I can see
what was rewritten without diffing the whole tree.

**As an author whose design moved before this feature existed**, I want
validation to tell me which documents still name the old path, so that the audit
trail survives a move no repoint ran over.

**As a reviewer following a References entry**, I want the path to resolve, so
that reading the trail costs me a click instead of a repo-wide search for a
basename.

**As a skill author writing a worked example**, I want `docs/designs/DESIGN-foo.md`
in my template to produce no finding, so that the check stays worth having.

**As a maintainer deciding when to make the check an error**, I want a repeatable
count over the whole corpus, so that I know how much cleanup stands between the
notice and a red build.

**As the author of a document that cites a design by name alone**, I want the
check to stay quiet, so that a stylistic choice about how to cite isn't
retroactively made into a defect.

## Requirements

### Functional Requirements

**R1: Relocation detection.** `shirabe validate` reports a finding when a
markdown file contains a path-shaped reference to a shirabe artifact document,
that path names no file, and a file with the same basename exists at another
artifact location in the same repository. The artifact locations are the
directories the doc tree already recognizes plus every destination of a moving
transition — `docs/designs/archive/`, `docs/visions/sunset/`, and
`docs/strategies/sunset/`. Omitting any of the three makes the corresponding
move undetectable: a superseded design, a sunset vision, and a sunset strategy
would each be indistinguishable from a deleted document.

**R2: The finding carries the resolved path.** Each finding names the referring
file, the 1-indexed line the reference sits on, the path as written, and the
path the document now occupies. The DESIGN owns the message wording; the four
facts are the requirement.

**R3: A resolving reference is never reported.** A path that names an existing
file produces no finding, whether it was written repo-relative or relative to
the referring file. The three relative-form references in the corpus today
resolve correctly and must stay silent.

**R4: An unresolvable basename is never reported.** When the referenced path
names no file *and* no file of that basename exists anywhere in the artifact
directories, the check produces nothing. This is the requirement that keeps
template placeholders, eval fixture names, and references to cascade-deleted
working artifacts out of the finding set. It is also the boundary against the
separately-tracked fault of durable documents naming ephemeral ones: that fault
is real, larger, and out of this PRD's scope.

**R5: Coverage is every markdown file the validator is handed.** The check runs
on artifact documents and on instruction files alike, and does not require
frontmatter, a recognized artifact prefix, or a `schema` field. Two of the 21
genuine defects are in `skills/`, so a check gated on artifact frontmatter
misses them.

**R6: Notice severity at ship, with a one-line promotion.** The check's findings
are notices in both review postures when it lands, so a validation run over the
inherited corpus exits zero. Promotion to error is a single-line change at the
existing intrinsic-notice seam, matching how the already-staged checks handle
the same situation.

**R7: A repeatable corpus measurement.** A documented procedure produces, over
every tracked markdown file rather than a diff, the count of findings and the
list of files carrying them. The measurement is run and recorded before the
severity is chosen and again after the check lands, and the two are compared.

**R8: The check is a `shirabe validate` check code.** It is addressable by
`--check <CODE>` like every other per-file check, and it introduces no new CLI
subcommand. New correctness rules belong in `validate` as a check or a mode;
a subcommand that renders or creates is an anti-pattern this repo has already
reverted once.

**R9: Findings are ordered deterministically.** Repeated runs over unchanged
input produce byte-identical output, so the annotation stream stays stable for
CI and for the cross-implementation parity gate.

### Non-Functional Requirements

**R10: No false positives on the current corpus.** Running the check over every
tracked markdown file at the branch point produces findings only for relocated
references. Concretely: at most 21 findings, and zero on the 119 non-resolving
paths that are placeholders, fixtures, or deleted working artifacts.

**R11: Per-file validation stays fast.** Validating a single file completes in
under 250 ms on the current corpus. The measured baseline before the check is
54 ms for the largest PRD, so the check has room for a directory scan and none
for a per-reference subprocess.

**R12: No network access.** The check reads the working tree and nothing else.
It runs in the same offline contexts every other per-file check does.

### Repoint Requirements

Functional requirements for the transition-time half. They are numbered after
the non-functional block rather than interleaved with R1-R9 so that nothing
already cited downstream has to be renumbered.

**R13: A moving transition repoints its inbound references.** When `shirabe
transition` moves a document, it rewrites every reference to the old path in the
repository's tracked markdown to name the new path, before it reports success.
This applies to all four moving transitions -- DESIGN to `Current`, DESIGN to
`Superseded`, VISION to `Sunset`, STRATEGY to `Sunset` -- because they share one
mechanism and there is no reason for them to differ.

**R14: Only the path changes.** A repointed file differs from its previous
contents by the substituted path substrings and nothing else: no reflowed
paragraphs, no reformatting, no trailing-whitespace normalization, no line-ending
change. This is the requirement that makes the rewrite reviewable as a diff.

**R15: The repoint respects the same contexts the check does.** A path inside a
fenced or indented code block is not rewritten, for the same reason it is not
reported: it is an example, and an example of a pre-move path stops being the
example it was chosen to be if a tool silently updates it.

**R16: Frontmatter `upstream:` is repointed too.** A moving transition rewrites
an inbound `upstream:` value naming the old path as well as the prose
occurrences. The determinism argument does not change at the frontmatter
boundary, and leaving it out would mean a transition that fixes prose and leaves
an error-level R6 dangle in the same file.

**R17: The repointed files are staged.** Rewritten files are `git add`-ed
alongside the moved file, so the transition's result is one reviewable staged
change rather than a rename plus unstaged edits an author might commit
separately or lose.

**R18: The repoint reports what it touched.** The command's output names every
rewritten file and the number of occurrences in each. A silent rewrite of files
the author did not name is the failure mode this requirement exists to prevent.

**R19: A failed repoint does not leave a half-done move.** If the rewrite cannot
complete -- an unreadable file, a write failure -- the transition fails with a
non-zero exit and a message naming the file, and the move is not reported as
successful. The DESIGN owns whether the recovery is a rollback or a refusal to
start, and it must say which.

## Acceptance Criteria

- [ ] `shirabe validate <file>` reports a finding for a reference naming
      `DESIGN-shirabe-scope-skill.md` under `docs/designs/`, and the finding
      names `docs/designs/current/DESIGN-shirabe-scope-skill.md` as the current
      path. (The pre-move path is spelled in two pieces here on purpose: a
      criterion that wrote it out in full would be a live stale reference in
      this document, which the check would then report.)
- [ ] The same command reports nothing for a reference naming
      `docs/designs/DESIGN-foo.md`, for which no file of that basename exists.
- [ ] The same command reports nothing for a reference naming
      `docs/plans/PLAN-roadmap-plan-standardization.md`, a working artifact the
      cascade deleted, which has no surviving file of that basename.
- [ ] The same command reports nothing for a reference naming a path that
      resolves, including `../prds/PRD-scope-completion-cascade.md` written from
      `docs/designs/current/`.
- [ ] `shirabe validate skills/scope/references/phases/phase-3-exit-finalization.md`
      reports the stale reference at line 352, proving the check runs on a file
      with no frontmatter.
- [ ] Running the check over every tracked markdown file produces exactly the
      set of findings recorded in the DESIGN's corpus measurement, and the count
      is written into the DESIGN before the severity is chosen.
- [ ] `shirabe validate --check <CODE>` accepts the new code, and an unknown
      code is still a tool error.
- [ ] `shirabe validate --lifecycle . --mode=draft` exits 0 with the check in
      place, and `shirabe validate` over the whole corpus exits 0 because every
      finding is a notice.
- [ ] Promoting the check to error is a diff touching one line of the
      intrinsic-notice set, demonstrated by a test that asserts the promoted
      severity.
- [ ] `cargo test --workspace`, `cargo fmt --check`, and `cargo clippy` are
      clean.
- [ ] Two runs of the check over unchanged input produce byte-identical output.
- [ ] `shirabe transition <design> Current` on a design named by three other
      documents leaves all three naming the new path, with the three files
      staged and named in the command's output.
- [ ] The same holds for `Superseded`, and for a VISION and a STRATEGY moved to
      `Sunset`.
- [ ] A repointed file's diff against its previous contents contains only the
      substituted path substrings.
- [ ] A pre-move path written inside a fenced code block is not rewritten.
- [ ] An inbound `upstream:` naming the old path is rewritten, and `shirabe
      validate` reports no R6 dangle afterward.
- [ ] Running the transition twice is safe: the second run finds nothing to
      repoint and reports zero rewritten files rather than failing.
- [ ] A transition whose repoint cannot complete exits non-zero, names the
      offending file, and does not report the move as successful.
- [ ] Running the check immediately after a moving transition reports zero
      findings for the moved document.

## Out of Scope

**A writing mode on `shirabe validate`.** The repoint mechanism could also be
offered as a `--fix` that repairs whatever the check reports, and it would clear
the existing 21 in one command instead of by hand. It isn't, and the reason is a
contract: validate reads and reports; it never writes. Mutation lives in
`shirabe transition`, which is where it already lives. The accepted cost is that
the inherited backlog is repaired by hand, because those documents moved before
any repoint existed and no future transition will run over them.

**References to documents that never existed or were deleted.** A prose path
naming a cascade-deleted PLAN or ROADMAP is the separately-tracked fault of
durable documents naming ephemeral ones. It's noticeably larger — of the 140
non-resolving paths, most fall here or in the placeholder set — and it needs a
different discriminator, because there is no surviving file to point at.

**Bare basename mentions.** A document referred to by filename alone survives a
relocation untouched; there's no path to break. Whether the corpus's 171 such
mentions are good style is a separate question.

**Fixing the 21 stale references.** This PRD sizes the cleanup and requires the
measurement that scopes it. Whether the cleanup lands with the check or as
scheduled follow-on work is a planning decision, and the check has to ship at
notice level either way, because the corpus is dirty at the moment it lands.

**Non-markdown files.** One stale reference sits in a shell-script comment.
Extending the check past markdown means a second extraction model for a
population of one, and the check's coverage requirement is deliberately written
against the files the validator already parses as markdown.

**A new CLI subcommand.** Named here as well as in R8 because it is the specific
shape this repo has reverted before.

## Decisions and Trade-offs

**Both halves, not detection alone.** An earlier draft of this PRD scoped
detection only and left the repair to whoever read the findings. That was wrong,
and the reason is worth recording so it is not re-argued: the check computes the
referring file, the line, the path as written, and the path that exists, and in
the single-match case that tuple fully determines a byte substitution. Handing a
determined edit to a person, or to an agent, is how the surrounding prose gets
reflowed and one of the twenty-one gets missed. The tell was in the draft's own
acceptance criterion for the cleanup, which had to say "only the paths change" —
a guard against an actor doing a job a program should do.

**Repointing lives in `transition`, not in `validate`.** The two candidate homes
do different things. In `transition` the repoint is prevention: it runs at the
moment of the move, it knows the old and new path exactly rather than inferring
by basename, and no reference ever becomes stale. In `validate` it would be
repair, and it would also make the correctness engine a writer. The first is
worth more, because the recurrence is unbounded while the backlog is 21 and
fixed. The accepted consequence is that nothing automatic repairs those 21.

**The repoint covers frontmatter as well as prose.** This is wider than the
feature's name. It is included because the argument for it is identical — the
transition knows both paths, so the edit is determined — and because excluding
it would produce the odd result of a command that repairs a document's prose and
leaves an error-level R6 dangle three lines above it in the same file.

**Notice at ship, error after cleanup.** An error-level check turns CI red on
arrival against 21 inherited findings. The alternatives were to clean the corpus
in the same change and ship at error, or to ship at error with an exemption
list. Cleaning first inverts the dependency — the cleanup is defined by what the
check reports, so the check has to exist to scope it — and an exemption list is
a second corpus to maintain. Notice-then-error is the pattern the already-staged
checks use, and the promotion is a single line at a seam that already exists.

**Scope by what the reference resolves to, not by where it's written.** Scoping
the check to `docs/` was the obvious first answer and the corpus rejects it:
`docs/` carries about 60 placeholder paths, and two genuine defects live in
`skills/`. Scoping to `## References` sections fails the same way — only 9 of
the 21 are under that heading. What separates the two populations cleanly is
whether a document of that basename exists somewhere else, which is a property
of the target rather than of the referring file. The trade-off is that a
reference to a document that was genuinely deleted looks identical to a
reference to one that never existed, and both stay silent; that's the boundary
the out-of-scope section draws deliberately.

**Report a path, not a diagnosis.** The finding names where the document is now
rather than asserting that a transition moved it. The check can't distinguish a
relocation from a coincidental basename collision, and doesn't need to: either
way the reader wants the path that exists.

## Known Limitations

A basename collision across two artifact directories would let the check name
the wrong target. Nothing in the corpus collides today, and the DESIGN owns
whether the check picks one target or names all of them.

The check catches a stale reference only when the referring file is validated.
Pull-request CI passes only changed files, so a reference in a file the PR
doesn't touch surfaces on the corpus-wide run rather than on the pull request
that broke it. Closing that gap for good means running the check over the tree,
which is a mode this PRD does not require.

The self-caller workflow that runs per-file validation triggers on changes under
`docs/`, `crates/`, and the Cargo files. A pull request touching only `skills/`
therefore validates nothing, so a stale reference introduced into an instruction
file is caught on the next unrelated run rather than on its own. That's a
pre-existing gap in the workflow's trigger paths, not one this check creates.

## References

- `docs/briefs/BRIEF-prose-reference-staleness.md` — the framing this PRD's
  requirements are written from.
- `crates/shirabe-validate/src/formats.rs` — the `legal_upstream` table that
  leaves prose as the only inbound record after a design's terminal transition.
- `crates/shirabe-validate/src/validate.rs` — `validate_prose`, which runs for
  every markdown file regardless of frontmatter, and `is_intrinsic_notice`, the
  promotion seam R6 refers to.
