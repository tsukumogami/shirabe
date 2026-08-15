---
schema: plan/v1
status: Active
execution_mode: single-pr
upstream: docs/designs/DESIGN-prose-reference-staleness.md
milestone: "Prose Reference Staleness"
issue_count: 5
---

# PLAN: prose-reference-staleness

## Status

Active

Five outlines, one branch, one PR. The work is confined to
`crates/shirabe-validate/` plus a documentation sweep, so there is one
repository and no reason to split the merge.

The outlines were also filed as GitHub issues (#293, #294, #300, #295, #296)
before this plan settled on single-pr. They are kept as trackers; the outlines
below are the execution contract, and the issue numbers are noted on each so the
two do not drift.

## Scope Summary

Two halves over one extractor.

**Prevention.** `shirabe transition` repoints inbound references as part of each
of the four moving transitions, so a correct lifecycle move stops stranding the
documents that named the old path. It is deterministic: the command holds the
old path and the new one, so nothing is inferred and nothing is left for a
person to edit by hand.

**Detection.** `FC18` reports a body-prose reference whose path names no file
when a file of the same basename survives elsewhere in the repository's artifact
directories. That surviving basename is the whole discriminator, and it
separates the 21 references a relocation actually broke from the 119
unresolvable paths that are template placeholders, eval fixture names, and
deliberately-deleted working artifacts. Detection is not made redundant by
prevention: it is the only thing that finds references broken by moves that
already happened, or by a rename that went around `shirabe transition`.

The check ships as a notice against the corpus it inherits, the corpus gets
cleaned by hand, and the check is promoted to an error. The cleanup stays manual
because those documents moved before the repoint existed, so no transition will
run over them. A `validate --fix` would have cleared them in one command and is
deliberately not built: validate reads and reports, and never writes.

## Decomposition Strategy

**Horizontal, five outlines, one fork, one branch.** Each outline is one layer
of the design's Implementation Approach, and every dependency edge is real
rather than stylistic:

- The extractor lands first (outline 1) because it has a parser behind it,
  because no finding count means anything until its context handling is right,
  and because two later outlines consume it. It must carry `RefSpan.range` from
  the start: outline 3 substitutes into that exact range, and an extractor that
  returns only `(line, text)` forces a second matcher that can disagree with the
  first.
- The check (outline 2) and the repoint (outline 3) both depend on outline 1 and
  on nothing else. This is the plan's only fork.
- The cleanup (outline 4) can only be scoped by the check's own output, so it
  cannot precede outline 2.
- The promotion (outline 5) is one line and would turn CI red before the cleanup
  lands, so it goes last.

**Why one PR.** The work touches one repository and one crate. The dependency
chain is linear apart from a single fork, so there is no parallel track for
separate PRs to exploit, and the last two outlines are a few lines each. Split
across five PRs, four of them would wait on a review queue to land a change the
fifth immediately builds on. The ordering discipline the sequence describes is
what keeps the single PR reviewable: commit per outline, in order.

## Issue Outlines

### Issue 1: feat(validate): reference extractor over the CommonMark parse

**Goal**: Add `prose::reference_spans`, a second selection over the same
CommonMark parse `prose_spans` already runs: inline code spans, link
destinations, and plain text in; fenced and indented code out. All 21 defects
live in inline code spans, which `prose_spans` deliberately excludes, so reusing
it finds zero. Tracked as #293.

**Acceptance Criteria**:
- [x] `reference_spans(body, body_start_line) -> Vec<RefSpan>` exists in `prose.rs`
- [x] `RefSpan` carries `line`, `text`, and `range` (byte offsets within the line)
- [x] A path in an inline code span, a link destination, and plain text is returned
- [x] A path in a fenced code block is not returned, including a fence whose first content line is itself a fence marker
- [x] A path in an indented code block is not returned
- [x] Line numbers are file lines on a document with frontmatter
- [x] A test asserts the byte range is correct on a line naming two distinct paths
- [x] The module header explains how the two functions partition one parse
- [x] `cargo test --workspace`, `cargo fmt --check`, `cargo clippy` clean

**Dependencies**: None

**Type**: feat

**Files**: `crates/shirabe-validate/src/prose.rs`

### Issue 2: feat(validate): FC18 reports a reference invalidated by a relocation

**Goal**: Add the candidate filter, the per-file repo-root resolver, the
memoized target index, and the `FC18` notice registered in `validate_prose` so
it reaches schema-less instruction files. Pin the corpus count at 21. Tracked as
#294.

**Acceptance Criteria**:
- [x] A reference naming `DESIGN-shirabe-scope-skill.md` under `docs/designs/` is reported, naming `docs/designs/current/DESIGN-shirabe-scope-skill.md` as the path that exists
- [x] The finding carries referring file, 1-indexed line, path as written, and resolved path
- [x] `docs/designs/DESIGN-foo.md` produces nothing (no surviving basename)
- [x] `docs/plans/PLAN-roadmap-plan-standardization.md` produces nothing (deleted working artifact)
- [x] A resolving path produces nothing, including a relative `../prds/PRD-<name>.md` written from `docs/designs/`. **Corrected**: the criterion named `../prds/PRD-scope-completion-cascade.md` from `docs/designs/current/`, which resolves to `docs/designs/prds/` and does not exist. It is a genuine stale reference and outline 4 repairs it.
- [x] `shirabe validate skills/scope/references/phases/phase-3-exit-finalization.md` reports the stale reference, proving the check reaches a file with no frontmatter
- [x] A cross-repo `owner/repo:path` reference produces nothing
- [x] The check reads `doc.body` only, so `cargo test -p shirabe --test parity` stays green
- [x] Repo root is found per file by walking up to `.git`; a file with no `.git` ancestor yields no findings
- [x] The target index covers `docs/{briefs,prds,designs,designs/current,designs/archive,plans,roadmaps,strategies,strategies/sunset,visions,visions/sunset,competitive}`
- [x] A basename at more than one path yields one finding naming every match in path order
- [x] Resolved paths are canonicalized and any escaping the repo root are dropped
- [x] The target index is scanned once per repo root per run
- [x] `FC18` is in `is_known_check_code` and in `is_intrinsic_notice`; a test asserts `Notice` under both postures
- [x] A corpus test asserts the finding count over tracked markdown is exactly 23. **Corrected** from 21: the design's count omitted the two relative references above, which it recorded as resolving and which do not.
- [x] Two runs over unchanged input produce byte-identical output
- [x] Single-file validation stays under 250 ms
- [x] `cargo test --workspace`, `cargo fmt --check`, `cargo clippy` clean

**Dependencies**: Issue 1

**Type**: feat

**Files**: `crates/shirabe-validate/src/checks.rs`, `crates/shirabe-validate/src/validate.rs`, `crates/shirabe-validate/src/formats.rs`

### Issue 3: feat(transition): repoint inbound references when a transition moves a doc

**Goal**: Rewrite every reference to the old path when any of the four moving
transitions relocates a document, staging the rewritten files with the moved
one. This is the half that stops the defect recurring. Tracked as #300.

**Acceptance Criteria**:
- [x] A design moved to `Current` leaves its three referrers naming the new path
- [x] The same holds for `Superseded`, and for a VISION and a STRATEGY moved to `Sunset`
- [x] Rewritten files are `git add`-ed alongside the moved file
- [x] Output names every rewritten file and its occurrence count
- [x] A repointed file's diff contains only the substituted path substrings; asserted on a CRLF file and one with trailing whitespace
- [x] A pre-move path inside a fenced or indented code block is not rewritten
- [x] An inbound frontmatter `upstream:` is rewritten, and `shirabe validate` reports no R6 dangle afterward
- [x] A relative-form referrer is repointed and stays relative
- [x] Edits apply right-to-left within a line
- [x] A second run reports zero rewritten files rather than failing
- [x] Every file is validated before any is written; a mid-run write failure exits non-zero, names the failing file and those already rewritten, and does not report the move as successful
- [x] The file set comes from `git ls-files -- '*.md'` with `-C <work-tree-root>`
- [x] `git add` uses an argument vector with `--`; nothing reaches a shell
- [x] The writing-style finding cap is not applied
- [x] `shirabe validate --check FC18` after a moving transition reports zero findings for the moved document
- [x] `cargo test --workspace`, `cargo fmt --check`, `cargo clippy` clean

**Dependencies**: Issue 1

**Type**: feat

**Files**: `crates/shirabe-validate/src/transition.rs`, `crates/shirabe-validate/src/prose.rs`

### Issue 4: docs: repoint the 21 stale prose references FC18 reports

**Goal**: Fix the 21 references across 15 documents under `docs/` and 2
instruction files under `skills/`. Paths only. Stays a hand edit because those
documents moved before the repoint existed, so no transition will run over them.
Tracked as #295.

**Acceptance Criteria**:
- [x] `git ls-files '*.md' | xargs shirabe validate --format json --check FC18` reports zero findings
- [x] Only paths change; no surrounding prose is reworded and no file reformatted
- [x] The corpus test from outline 2 is updated to expect 0
- [x] `shirabe validate --lifecycle . --mode=draft` exits 0
- [x] The one stale reference in `skills/plan/scripts/plan-to-tasks.sh` is noticed and a decision recorded; it is a shell comment, outside what the check reads. Decision: fixed, since the repair is the same one substring and the scope boundary is about what the check reads rather than what a person may correct.

**Dependencies**: Issue 2

**Type**: docs

**Files**: 15 documents under `docs/`, 2 under `skills/`, and the corpus test

### Issue 5: feat(validate): promote FC18 from notice to error

**Goal**: Delete the `FC18` arm from `is_intrinsic_notice` and flip the severity
test. One line of non-test code, gated on the corpus being clean. Tracked as
#296.

**Acceptance Criteria**:
- [x] The `"FC18"` arm is removed from `is_intrinsic_notice`
- [x] `effective_severity("FC18", ..)` returns `Error` under both postures
- [x] The diff to non-test code is one line
- [x] `shirabe validate --check FC18` over all tracked markdown exits 0, proving the cleanup landed. **Corrected**: an unqualified `shirabe validate` over *all* tracked markdown cannot exit 0 in this repository, because the golden corpora under `tests/fixtures/` and `evals/fixtures/` are deliberately invalid documents. CI excludes both directories; so does this criterion.
- [x] The comment naming the remaining notice-level checks no longer mentions `FC18`
- [x] `cargo test --workspace`, `cargo fmt --check`, `cargo clippy` clean

**Dependencies**: Issue 4

**Type**: feat

**Files**: `crates/shirabe-validate/src/validate.rs`

## Implementation Sequence

Outline 1 first, then 2 and 3 in either order or at once, then 4, then 5. One
branch, one commit per outline, in that order.

**Start with outline 1.** It is the only unblocked one, the only one whose
correctness is independently checkable, and the one both later pieces consume.
The context split (code span, fenced, plain) is what every count downstream
rests on, and the byte range is what outline 3's substitution needs. Land it
without the range and outline 3 either duplicates the matching logic or changes
a signature under tests that already passed.

**Outlines 2 and 3 fail differently.** The check can be subtly wrong while still
looking right: the discriminator, the resolution base, the moving-transition
destinations, the parity constraint, and the corpus count are each a way that
happens. The parity constraint deserves particular care: the check must read
`doc.body` only, because a Layer-1 golden fixture carries
`DESIGN-roadmap-plan-standardization.md` under the pre-move `docs/designs/` in
its `upstream:` field, and a frontmatter-reading check would produce a new
finding on pinned bytes. The repoint fails more loudly and does more damage: it
writes across the tree, so its criteria pin the diff shape, the edit order, and
the failure mode.

**The two differ on frontmatter, deliberately.** The check reads the body only;
the repoint rewrites `upstream:` as well. R6 already reports a dangling
`upstream:` loudly, so the check has nothing to add there, while the repoint is
in a position to fix it and a person otherwise has to.

**Outlines 4 and 5 are a pair.** Landing 4 without 5 leaves the check correct
and quiet; landing 5 without 4 turns CI red. If the PR has to be cut short, cut
it after outline 3: that is the outline that stops the defect recurring, and
everything after it describes or repairs a backlog.

**Re-measure rather than trusting line numbers.** The occurrence list recorded
in #295 is from the branch point and any merge moves it. Re-run the check.

## References

- `docs/designs/DESIGN-prose-reference-staleness.md` — the design this PLAN
  decomposes; its Implementation Approach names the same five batches.
- `docs/prds/PRD-prose-reference-staleness.md` — the requirements each outline's
  acceptance criteria cite.
