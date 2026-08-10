---
schema: plan/v1
status: Draft
execution_mode: single-pr
milestone: ""
issue_count: 4
upstream: docs/designs/current/DESIGN-populate-issueless-default.md
---

# PLAN: Populate issueless by default

## Status

Draft

Single-PR plan implementing `DESIGN-populate-issueless-default.md`. Four
outlines, executed in order on one branch, each leaving the workspace green.
No GitHub issues are filed for this plan — the whole change is one reviewable
PR, and filing four issues to close them in the same PR would be ceremony.

## Scope Summary

Flip `shirabe roadmap populate`'s default from issue-creating to issueless,
give the issue-creating path an explicit `--issues` flag, make the two mode
flags mutually exclusive, and make `/roadmap` populate its own reserved
sections during a normal run. Every in-repo caller — one skill invocation and
17 test invocations — gains an explicit mode flag, so nothing depends on the
default. A decision record supersedes D5 of
`DESIGN-roadmap-issueless-preference.md` and a release note names the breaking
change for direct CLI callers.

Neither renderer changes. `crates/shirabe-validate/src/checks.rs` does not
change; FC16 keeps its shape-gating.

## Decomposition Strategy

**Vertical, ordered, single branch.** The four outlines are sequential rather
than parallel because each depends on the previous one compiling: the flag has
to exist before callers can pass it, and callers have to pass it before the
suite is green.

The ordering is chosen so that the one intentionally-red window is small and
obvious. Outline 1 changes the CLI's default, which breaks the 17 integration
tests that relied on it; outline 2 fixes exactly those. Between them
`cargo test -p shirabe --lib` is green and the integration suite is red in a
way that enumerates the remaining work. Outlines 3 and 4 touch only prose and
cannot break the suite.

Complexity is `simple` throughout. The hard part of this change was the four
decisions, and those are settled in the design.

## Issue Outlines

### 1. Add `--issues`, invert the default, make the flags exclusive

**Goal**: Give the issue-creating path an explicit name, make issueless the
fall-through, and make the two mode flags mutually exclusive at the parser.

**Dependencies**: None

**Files**: `crates/shirabe/src/populate.rs`, `crates/shirabe/src/main.rs`.
Complexity: simple.

Add `issues: bool` to `PopulateArgs` as
`#[arg(long, conflicts_with = "no_issues")]`, documented so `--help` states
which mode runs when neither flag is given (AC5). Invert the mode branch in
`run_inner` (currently `if args.no_issues { return run_issueless(...) }` at
line 124) so the issueless path is the fall-through and the issue-creating
path runs only under `args.issues`. Revise the `--no-issues` doc comment,
which currently says the flag is "Set by the roadmap skill when the repo
declares `## Roadmap Issues: optional`" — that is no longer the only reason it
appears. Update the `RoadmapCommands::Populate` doc comment in `main.rs`,
which describes issue creation as the default in user-visible help text.

Add the new field to the four `PopulateArgs` constructions in the unit tests
(lines 1641, 1713, 2210, 2278). Note this is four, not the five the dispatch
brief predicted — the fifth occurrence at line 1600 is the `Probe` harness's
field declaration, a type annotation rather than a struct literal.

Extend `no_issues_flag_parses` or add siblings covering: `--issues` sets
`issues`, the unflagged parse leaves both false, and the conflicting parse
fails. Use `Probe::try_parse_from` for the conflict case so the failure is
asserted rather than panicking.

**Acceptance Criteria**:

- [ ] `cargo test -p shirabe --lib` is green.
- [ ] `cargo clippy -p shirabe` adds no warning over the 27-warning baseline.
- [ ] `--help` names both mode flags and states the no-flag behaviour.
- [ ] A conflicting parse of `--issues --no-issues` fails rather than
      resolving to a mode.

Satisfies R1, R2, R3, R4, R5.

### 2. Update every test caller and add the new coverage

**Goal**: Leave no test relying on the default, and cover the three behaviours
the flip introduces.

**Dependencies**: 1.

**Files**: `crates/shirabe/tests/populate_cli.rs`. Complexity: simple.

Add `--issues` to the 17 invocations that relied on the default. The 7
invocations already passing `--no-issues` (lines 643, 672, 707, 732, 835, 865,
872) are unchanged. The `--help` call at line 122 and the not-found-path call
at line 453 are not populate runs and need no mode. These are edits, not
deletions — R17 requires the issue-creating path's coverage not to drop, so
the post-change count of tests exercising it must still be 17.

Add three tests:

- The conflict case: `--issues --no-issues` exits non-zero, stderr names both
  flags, and the roadmap file is byte-identical afterwards (AC4).
- The unflagged case: a bare `roadmap populate <path>` fills both sections in
  issueless form, exits 0, and makes no `gh` call — asserted with the same
  PATH-injection harness the suite already uses around line 353, whose marker
  file proves a `gh` invocation would have been observed (AC1).
- The help case: `--help` output contains both `--issues` and `--no-issues`
  and states the no-flag behaviour (AC5).

**Acceptance Criteria**:

- [ ] `cargo test --workspace` is green.
- [ ] The count of tests exercising the issue-creating path is still 17.
- [ ] The conflict test asserts a non-zero exit and a byte-identical roadmap.
- [ ] The unflagged test proves no `gh` call via the PATH-injection harness.

Satisfies R17; AC1, AC2, AC3, AC4, AC5, AC14.

### 3. Rewire the roadmap skill and correct the docs

**Goal**: Make `/roadmap` populate its own reserved sections issuelessly, turn
`populate` into the issue-filing action, and leave no in-repo invocation
without a mode flag.

**Dependencies**: 2.

**Files**: `skills/roadmap/SKILL.md`,
`skills/roadmap/references/phases/phase-4-validate.md`,
`skills/roadmap/references/roadmap-format.md`,
`references/fixes/claude-md-conventions.md`. Complexity: simple.

In `SKILL.md`: rewrite input mode 3's description so `populate` reads as the
issue-filing action; rewrite the two-mode framing in "Populating the Issues
Table" so `required`/`optional` select what a human-invoked populate does
rather than describing an absent header as issue-creating; add `--issues` to
the issue-creating example in the Invocation block (lines 380-385 — the one
in-repo invocation relying on the default); add `--issues` to the options
list; update the R14 gate section so it gates the `--issues` path and is
skipped otherwise; and correct the Context Resolution paragraph at lines
145-154, whose "fail-closed toward the issue-creating, human-gated path"
wording inverts under the new default.

In `phase-4-validate.md`: add the automatic issueless populate after the jury
findings resolve and before the approval walkthrough, so the author reviews a
populated roadmap (R8); and add the re-run on the activate path, before
`shirabe transition <path> Active`. Both invoke with an explicit
`--no-issues`. State that the automatic runs never present the R14 gate,
because they create nothing.

In `roadmap-format.md`: correct the Reserved Sections prose (around lines
173-200) describing how the sections get filled, since `/plan` is no longer
the filler of first resort and the default marker changes.

In `claude-md-conventions.md`: correct the `## Roadmap Issues:` entry at line
64, which states the current default.

Then run the AC11 sweep: search `skills/`, `docs/`, `references/`, and
`crates/*/tests/` for populate invocations and confirm every one names a mode.
Prose that names the subcommand without invoking it is exempt — README.md:219,
the plan skill's phase-7 references, and the issueless-table-rendering
BRIEF/PRD/DESIGN are all prose.

**Acceptance Criteria**:

- [ ] The AC11 sweep finds no unflagged invocation in `skills/`, `docs/`,
      `references/`, or `crates/*/tests/`.
- [ ] `phase-4-validate.md` populates before the approval walkthrough and
      again on the activate path, both with an explicit `--no-issues`.
- [ ] The R14 gate section gates the `--issues` path only.
- [ ] No prose anywhere still describes an absent header as issue-creating.

Satisfies R6, R7, R8, R9, R10, R11, R12, R13, R14; AC6, AC7, AC8, AC9, AC10,
AC11.

### 4. Decision record and release note

**Goal**: Make the supersession of D5 and the breaking change legible to a
future reader and to a current CLI caller.

**Dependencies**: 3.

**Files**: `docs/decisions/`, release notes. Complexity: simple.

Write the decision record superseding D5 of
`DESIGN-roadmap-issueless-preference.md`. It names D5, quotes it, states it is
superseded, and gives the blast-radius reasoning from the design's D1 —
including why the backward-compatibility argument was right when issueless was
unproven and is not right now that it ships and the workflow uses it by
default. Follow the repo's existing
`DECISION-<topic>-<YYYY-MM-DD>.md` naming.

Write the release note naming the default flip as a breaking change: what
changed, who is affected (anyone invoking `shirabe roadmap populate` directly
without a flag), and the fix (add `--issues`).

**Acceptance Criteria**:

- [ ] A decision record under `docs/decisions/` names D5, quotes it, and
      states the blast-radius reasoning.
- [ ] The release note names the flip as breaking and gives the fix.
- [ ] `shirabe validate` runs clean over the repo's own docs.
- [ ] `git diff --stat` confirms `crates/shirabe-validate/src/checks.rs` is
      untouched.

Satisfies R15, R16, R18; AC12, AC13, AC15, AC16.

## Implementation Sequence

Strictly sequential: 1, then 2, then 3, then 4.

Only one dependency is load-bearing — outline 2 cannot compile until outline 1
adds the flag, and the workspace suite is red in between. That window is
intentional and bounded: the failures are exactly the 17 invocations outline 2
exists to fix, so a red run there is a worklist, not a surprise.

Outlines 3 and 4 touch only prose and could in principle run alongside 2, but
they are sequenced after it so that the AC11 sweep in outline 3 runs against
already-corrected tests and reports the true remaining set.

Verification at the end of outline 4, before the PR goes ready:

- `cargo test --workspace` green.
- `cargo clippy --workspace --all-targets` with no new warnings over the
  27-warning baseline.
- `cargo fmt --check` on the touched files only — the repo has pre-existing
  formatting drift in `crates/shirabe-validate/src/checks.rs` and four sibling
  files, so `cargo fmt --all` would bury the change in unrelated reformatting.
- `shirabe validate` clean over the repo's docs.
- The AC11 sweep re-run as a final check.
