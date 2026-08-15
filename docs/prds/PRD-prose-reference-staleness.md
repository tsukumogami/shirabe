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
  `shirabe validate` reports a prose reference whose path a relocation has
  invalidated, names where the document went, and says nothing about the
  illustrative paths that outnumber the real ones six to one. The check ships
  at notice level against the dirty corpus it inherits, with a measured count
  behind that choice and a one-line promotion once the count reaches zero.
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

Durable artifacts change path when they reach a terminal state. `shirabe
transition <design> Current` git-mv's a DESIGN from `docs/designs/` into
`docs/designs/current/`; supersession moves it again. The transition rewrites
the moving document's own frontmatter and status and touches nothing else, so
every document that named the old path is wrong the moment the move lands.

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

**A relocation is caught before it merges.** An author who transitions a design
to `Current` sees, in the same validation run, which documents still name the
path it left. Nothing about that is available today at any cost short of a
manual repo-wide search that nobody performs.

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

**As an author transitioning a design to its terminal state**, I want validation
to tell me which documents still name the old path, so that the audit trail
survives a move I made correctly.

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
directories the doc tree already recognizes, plus `docs/designs/archive/` —
without the archive directory a superseded design is indistinguishable from a
deleted one, and supersession is one of the two transitions this check exists
for.

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

## Out of Scope

**Rewriting inbound references at move time.** `shirabe transition` knows both
the old and the new path and could repoint every referrer as it moves the file.
That's the prevention half of the problem. It's deliberately deferred: it's the
more invasive change, and it does nothing about the 21 references that are
already stale. Detection first is sequencing, not rejection — if the check
proves out, prevention is the natural follow-on.

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

**Detection before prevention.** The upstream brief left this as a lean rather
than a conclusion, and the corpus settles it: 21 references are already stale,
and prevention at move time fixes none of them. Detection also produces the
measurement prevention would need to prove itself. The trade-off accepted is
that until prevention lands, every future transition creates new stale
references that an author has to fix by hand — the check just makes sure they
find out.

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
