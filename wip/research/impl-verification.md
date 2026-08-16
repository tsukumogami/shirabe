# INCOMPLETE

Note: diffing against local `main` pulls in ~30 unrelated already-merged
commits (local `main` ref is stale relative to origin). The correct base for
this plan's work is `5eb7e14` (the commit right after the plan's final review
round, before Issue 1's implementation commit). All diffs below use
`5eb7e14..HEAD` unless noted. Mid-verification, a `chore(cascade): finalize
the chain` commit (`b006eed`) landed and deleted
`docs/plans/PLAN-multi-pr-plan-decoupling.md` per the normal Done cascade;
its content had already been captured before deletion and all findings below
are unaffected.

## Issue 1 — PASS

`references/split-triggers.md` exists with full content (not stub headings)
for Hard Constraint, Incremental Value, Stated Preference (plan profile, all
three as-is) and Merge-Order Necessity (coordinated profile, "adds a fourth").
`workflow-principles.md` P1 cites it and no longer enumerates escape
conditions inline. `coordination-strategy.md`'s Coarsest-Legal-Grouping Rule
cites it and keeps only Merge-Order Necessity as profile-specific
(`references/coordination-strategy.md:126-139`). "independently mergeable" /
"independently rollback-able" appear only inside split-triggers.md's Hard
Constraint section (`grep -rn` confirms). "reviewability ceiling" appears only
in split-triggers.md's Stated Preference section. Reviewability named exactly
once across the two citing files (`workflow-principles.md:24`, one hit).
`./target/release/shirabe validate references/split-triggers.md
references/workflow-principles.md references/coordination-strategy.md
--format json` → `errors: 0, notices: 1` (pre-existing FC10 em-dash-density
notice on coordination-strategy.md, confirmed present before the change too
via `git show 5eb7e14:...`) — outcome `clean` under both draft and ready mode.

## Issue 2 — PASS

`skills/plan/references/plan-format.md:47-81` documents `split_rationale` as
required under both disjuncts (execution_mode != single-pr, OR single-pr under
resolved `atomic` preference), states a value naming none of the three
branches fails L09, states it's free text with no enum added, and shows the
single-pr-under-consolidated no-field case as correct. Step 3.6
(`phase-3-decomposition.md:492-585`) names the branch per outcome and writes
`split_branch`/`split_rationale` into the decomposition artifact frontmatter.

## Issue 3 — PASS

`cargo test -p shirabe-validate --release`: 747 passed, 0 failed. The six
`l09_*` tests exist (`lifecycle.rs:2105-2189`) and pass individually
(`cargo test l09` → 6 passed): fires on multi-pr without rationale, passes
when rationale names a branch, fires when rationale names no branch, silent on
single-pr with no stated preference, fires on single-pr departing from
`atomic`, falls through to default on an unrecognized preference value. Both
positive and negative departure-branch directions are exercised, independent
of Issue 4 (fixture writes a raw CLAUDE.md header directly).
`git diff 5eb7e14..HEAD -- crates/shirabe-validate/src/formats.rs` is empty —
untouched (the diff against `main` shows changes, but those come from
unrelated PR #302, confirmed via `git log -- formats.rs`).
`crates/shirabe-validate/src/checks.rs` (home of `check_fc01`) is also
untouched (0-line diff); `check_fc01`'s signature is unchanged. Both doc
comments in `validate.rs` (lines 104-115 and 59-65) name `L09`, and
`posture_class_classifies_lifecycle_codes` (validate.rs:485-495) covers it.

## Issue 4 — PASS

`references/fixes/claude-md-conventions.md` carries `## Delivery Preference:
consolidated|atomic` with accepted values, default (`consolidated`), and
precedence (`flag > this header > consolidated default`), explicitly not
named `Execution Mode`. `skills/plan/SKILL.md`'s "Execution Mode Decision"
section and step 3.6 both resolve the header on the same stack and select a
branch per outcome. `lifecycle.rs`'s `resolve_delivery_preference` reads the
literal header text and falls through to `consolidated` on unrecognized
values (exercised by `l09_unrecognized_preference_falls_through_to_default`).
Note: the "two identical CLAUDE.md fixtures, differing only in Delivery
Preference, produce different execution_mode recommendations" criterion
describes a live `/plan` run through a prose skill procedure (step 3.6 is
agent instructions, not code) — verified structurally (the procedure text
correctly resolves the stack and records the consulted branch) rather than by
executing an actual `/plan` session, since that isn't scriptable the way the
Rust and shell checks are.

## Issue 5 — PASS

`claude-md-conventions.md` carries `## Tracking Level:
none|issues|issues-and-milestone` with accepted values, the mode-conditional
default (`issues-and-milestone` for multi-pr, `none` for single-pr, stated
explicitly), precedence (`flag > header > mode-derived default`), and
"unrecognized value falls through to the default." `phase-7-creation.md:62-96`
resolves the level before either mode branch, states it applies regardless of
`execution_mode`, exempts `coordinated` plans, documents all six
`{single-pr,multi-pr} x {none,issues,issues-and-milestone}` combinations in a
table, and writes `tracking_level` into PLAN frontmatter for later consumers.
Same caveat as Issue 4: this is a prose procedure, verified by content
inspection rather than a live two-fixture `/plan` run.

## Issue 6 — FAIL

Grep checks pass: the file-scoped completeness check (`grep -niE "(human[
-]approv|approval gate)"` over the eight files, piped through `grep -iE
"multi-pr|single-pr"`) returns **zero lines** — stronger than the "only
de-keyed prose" bar it has to clear. The tree-wide discovery check returns
hits only at the golden fixture, the decision-record amendment, and this
feature's own PRD/DESIGN/PLAN quoting old phrasing (already verified deleted
from the tree — PLAN itself is gone; PRD/DESIGN quotes intact by design).
Manually read all 14 approval-term hits across the eight files plus their
surrounding context: all correctly key on GitHub-issue-creation / resolved
Tracking Level, not on `execution_mode`. Golden fixture
(`crates/shirabe/tests/fixtures/golden/corpus/real/PLAN-roadmap-plan-standardization.md`)
is byte-identical to `main` (`git diff` empty). `transition.rs`'s actual Plan
transition-spec code and doc comment are correctly re-keyed
(`transition.rs:465-475`), and Phase 7's gate is code-verified to branch on
resolved tracking level (`phase-7-creation.md:106`).

**But** `skills/plan/references/plan-format.md`'s `### Transitions` section
(lines 287-298) was never touched (confirmed via `git diff 5eb7e14..HEAD --
skills/plan/references/plan-format.md`, which shows only the frontmatter
section changed). It still reads: "**Draft -> Active** (multi-pr only) --
... `single-pr` mode skips this state" and "**Draft -> Done** (single-pr
only)" — unconditionally gated on `execution_mode`, with no mention of
`tracking_level` at all. This directly contradicts the redesign (a `multi-pr`
plan with tracking `none` should skip Draft->Active like single-pr does; a
`single-pr` plan with tracking `issues` should NOT skip it) and fails the AC
bullet "The transition tables in `plan-format.md` and `plan-doc-structure.md`
cover `multi-pr` with `none` as automatic and `single-pr` with `issues` as
human-approved" — `plan-doc-structure.md`'s table was correctly redone
(`plan-doc-structure.md:84-98`, keyed on tracking level), but
`plan-format.md`'s was not touched at all. It evaded both mandated greps
because it says "(multi-pr only)"/"(single-pr only)" without the words
"approval" or "human," which is exactly the paraphrase-evasion the AC's
mandatory human-reading step exists to catch — and confirms why that step is
not optional.

Minor secondary note: `DESIGN-shirabe-artifact-decision-contract.md:197`
("paralleling PLAN's multi-pr gate") is an untouched, out-of-scope sentence
(Decision 3, not Decision 6's collateral mention that Issue 6 actually
edited) that still labels the gate "multi-pr" as a nickname. It doesn't
assert conditional keying and evades both greps (the two key words land on
different physical lines), so it isn't a required-scope FAIL, but a careful
reader may flag it as stale terminology.

## Issue 7 — PASS

`bash skills/plan/scripts/plan-to-tasks_test.sh`: 91 passed, 0 failed,
including the issueless-multi-pr tests (`ISSUE_SOURCE=plan_item`, dependency
edge resolves, no `ISSUE_NUMBER` emitted) and the multi-pr-with-`issues`
regression test (still `ISSUE_SOURCE=github` with `#N`). Built an independent
fixture (not copied from the test file) — a `multi-pr` PLAN with
`tracking_level: none` and two outlines, Issue 2 blocked-by Issue 1 — and ran
`plan-to-tasks.sh` directly:

```
[{"name":"m-build-the-base-layer","vars":{"ISSUE_SOURCE":"plan_item","ARTIFACT_PREFIX":"m-build-the-base-layer"},"waits_on":[]},
 {"name":"m-build-the-dependent-layer","vars":{"ISSUE_SOURCE":"plan_item","ARTIFACT_PREFIX":"m-build-the-dependent-layer"},"waits_on":["m-build-the-base-layer"]}]
```

Confirms `ISSUE_SOURCE: plan_item`, `m-`-prefixed names, and a resolving
`waits_on` edge, independent of the suite's own fixture.
`plan-to-tasks-contract.md` documents the third scheme (grep confirms).
`plan-to-tasks.sh:1250` shows the `none` path literally calls
`process_single_pr "$PLAN_PATH" "m-" "plan_item"`, reusing the single-pr
parser and local-id machinery as designed.

Side observation, not an AC failure: my fixture's `**Type**:\nfeat` (colon,
newline, value on its own line — the exact format
`PLAN-multi-pr-plan-decoupling.md` itself used throughout) parsed as
`type: null` via `shirabe plan outlines`, while the test suite's own fixtures
use inline `**Type**: code` and parse correctly. Issue 7's AC only requires
`ISSUE_TYPE` "when the outline carries one," and doesn't claim multi-line
`**Type**:` values are supported, so this isn't a scoped FAIL — but it means
the real plan being implemented would not have gotten `ISSUE_TYPE` emitted
for any of its own issues had it gone through this path. Worth a note to the
team, not a blocker for this issue's stated AC.

## Issue 8 — FAIL

Amendment section exists (`## Amendment to Decision 6 — 2026-08-15`), states
both required facts (default now conditional on resolved Delivery Preference;
de-conflation and value-anchoring unchanged) in its own text, cites
`DESIGN-multi-pr-plan-decoupling.md`, is appended at the end (not interleaved,
nothing in the original Decision 6 text deleted), and is not phrased as
superseding.

**But** the explicit numeric AC — `grep -cniE "(human[ -]approv|approval
gate)"` over the file returns zero, stated to be 7 before the change — is
unmet: it still returns **7** after the change (verified directly). The seven
hits (`lines 400, 456, 577, 637, 724, 795, 796`) are all correctly
non-mode-keyed (none mentions `multi-pr`/`single-pr` in the same clause), so
the *substance* of the re-key is fine and consistent with Issue 6's own stated
principle that "human approval" legitimately survives re-keying — but the
Issue 8 AC as literally written demands the phrase disappear entirely from
this specific file, and it does not. This is a direct, mechanical count
mismatch against the plan's own stated command and expected result.

Secondary, lower-confidence note: the AC also requires the amendment run "to
no more than two or three sentences." Counting the actual appended text, it
runs to 5 sentences across 3 paragraphs (2 + 2 + 1). This is a softer,
interpretation-dependent criterion but is also arguably unmet as literally
stated.

## Whole tree — PASS

`./target/release/shirabe validate --lifecycle . --format json` → `{"outcome":
"clean", "errors": 0, "notices": 0}`, 0 findings.

## Regressions / out-of-scope changes

`git diff 5eb7e14..HEAD --stat` (the correct base — see note above) touches
22 files. Two files outside every issue's Files list, both benign:

- `docs/plans/PLAN-work-on-friction-fixes.md` (+6 lines) — an unrelated,
  pre-existing multi-pr plan retroactively given `tracking_level:
  issues-and-milestone` and a `split_rationale` naming Incremental Value.
  Looks like necessary migration so this real document keeps passing L09/the
  new schema, not scope creep, but it's not listed in any issue's Files.
- `docs/designs/DESIGN-multi-pr-plan-decoupling.md` (+84/-? at time of
  capture, now further reduced by the finalize-cascade commit) — the
  feature's own upstream design self-corrected mid-implementation (occurrence
  counts, the three "Current" designs reclassified from "leave" to "re-key").
  Design-doc housekeeping alongside implementation, not a code/prose
  regression, but also not in any issue's Files list.

No other files outside the union of all eight issues' Files lists were
touched.

## Gaps

- `skills/plan/references/plan-format.md`'s `### Transitions` section (lines
  287-298) is unchanged and still gates Draft->Active on `execution_mode`
  ("multi-pr only" / "single-pr mode skips this state"), contradicting Issue
  6's explicit transition-table AC. Needs the same tracking-level-keyed
  rewrite `plan-doc-structure.md`'s table already got.
- Issue 8's `grep -cniE "(human[ -]approv|approval gate)"` over
  `DESIGN-roadmap-plan-standardization.md` returns 7, not the required 0. The
  content is substantively correct (non-mode-keyed) but the AC's literal
  numeric bar is unmet — either the AC needs relaxing to match Issue 6's own
  "approval terms may survive" principle, or the file's remaining 7 mentions
  need rewording to drop the exact phrases.
- Issue 8's amendment runs to 5 sentences, not "no more than two or three" —
  softer/interpretive, flagged for the team's judgment.
