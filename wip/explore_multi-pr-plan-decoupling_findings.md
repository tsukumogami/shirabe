# Exploration Findings: multi-pr-plan-decoupling

## Core Question

Multi-pr PLAN execution mode fuses three independent decisions into one flag:
whether a plan *can* land in a single PR, whether it *should*, and how the
resulting work is *tracked*. Should these be separated -- the "can" gate derived
near-deterministically from the design's decomposition, the "should" gate bound
to a repo-level preference, and the tracking mechanism bound to its own
preference rather than hardcoded to multi-pr?

## Round 1

### Key Insights

**The fusion is real, and it is localized to two files.** (lead-mode-decision-flow,
lead-issue-milestone-wiring) The mode is chosen in
`skills/plan/references/phases/phase-3-decomposition.md` step 3.6, which runs one
4-way branch fusing a hard-constraint check (a "can" fact) with an
independently-useful check (a "should" judgment) into a single `AskUserQuestion`
and records the result as `execution_mode` in PLAN frontmatter. Tracking is then
a hardcoded consequence in `phase-7-creation.md`: multi-pr calls
`create-issues-batch.sh --milestone`, single-pr creates nothing. There is no
knob, at any level, for "multiple PRs but no GitHub issues" or the inverse.

**The blast radius of decoupling tracking is far narrower than it looks.**
(lead-issue-milestone-wiring, lead-milestone-worthiness) `/execute` explicitly
refuses to run multi-pr plans at all -- it owns `single-pr` and `coordinated`
and redirects multi-pr to `/work-on`. So every consumer of multi-pr GitHub state
lives in one skill. Within that skill the dependency is thinner still: milestones
have exactly one functional consumer, `/work-on M<N>`'s "pick the next unblocked
issue" selector. No progress percentage reads it, no completion cascade reads
it, `/inflight` doesn't touch it. Grepping `skills/execute/` and
`skills/inflight/` for milestone logic returns nothing.

**The mechanism the author wants already exists twice, scoped one level too
narrowly.** (lead-config-surfaces, lead-tooling-enforcement)
- `## Roadmap Issues: optional|required`, resolved `flag > CLAUDE.md-header >
  default`, governs whether `/roadmap populate` files GitHub issues. Issueless is
  now the default (`DECISION-populate-issueless-default-2026-08-10.md`), with an
  explicit rule that automatic runs are *always* issueless regardless of header.
  This is the tracking preference, built and shipped -- for ROADMAP only.
  `grep -rn "issueless\|no_issues" skills/plan/` returns nothing.
- `## PR Grouping Policy: coarsest-legal` plus `## Reviewability Ceiling:`,
  resolved on the same stack, govern how a coordinated multi-repo effort splits
  into PRs: one PR per repo by default, split only on one of four *recorded
  triggers* (independently mergeable, independently rollback-able, exceeds the
  configured reviewability ceiling, breaks a merge-order cycle). This is the
  decomposition preference -- with a named trigger list and a configurable
  threshold -- built and shipped for cross-repo coordination only.

Neither reaches the plan-level single-pr/multi-pr decision. The work is largely
generalization of proven mechanisms, not invention.

**The "can" gate is thinner than the framing hopes.** (lead-single-pr-determinism)
Only one signal is near-deterministic: repo-count spread -- and it routes to
`coordinated`, a structurally distinct third mode, not to plain `multi-pr`. The
other named hard constraint (an artifact must be released, published, or reach
main before later work can consume it) *does* have a built mechanism -- Gate
nodes in `references/coordination-strategy.md`, with an authoring format, a DAG
contraction algorithm, an acyclicity check, and a live merge-gate validator --
but that mechanism exists **only inside the cross-repo coordinated contract**.
There is no same-repo equivalent. "A workflow must reach main before it can be
invoked" is named in three places as a real category and has no detection
mechanism, no worked example, and no validator anywhere in the repo.

**Issue count and dependency depth are proven not to force multiple PRs.**
(lead-single-pr-determinism) `/execute`'s single-pr path drives an arbitrary
number of dependent issues through one shared branch and one PR, using Phase 5's
parallelization and critical-path machinery to sequence them. So the intuition
"many issues means many PRs" is already disproven by shipped behavior. Complexity
labels (`trivial|simple|testable|complex`) measure review rigor per issue, a
different axis entirely.

**Half the work was already done, by a design not in the reading list.**
(lead-design-corpus-priors) `DESIGN-roadmap-plan-standardization.md` Decision 6
owns the current rule. It already de-conflated *decomposition strategy* from
*execution mode* and re-anchored "roadmap input is multi-pr" on value rather than
mechanism. It stopped exactly one level short: no repo preference, and tracking
never treated as an axis. Any new design should amend Decision 6 rather than
re-derive its reasoning.

**Decoupling tracking removes the stated justification for a shipped approval
gate.** (lead-design-corpus-priors) `DECISION-multi-pr-posture-detection-2026-06-06.md`
makes the Draft->Active transition human-approved for multi-pr and automatic for
single-pr *because* multi-pr is the moment remote GitHub artifacts get created.
Once tracking is independent, that gate has to be re-keyed on "does this run
create GitHub artifacts" rather than "is this multi-pr." Those are the same
predicate today.

**The hint-rather-hard-fail pattern already exists as first-class machinery.**
(lead-tooling-enforcement) `crates/shirabe-validate/src/advisory.rs` runs an
advisory-never-gates layer, and `PostureClass::DraftTolerable` findings are
notices under `--mode=draft` and errors under `--mode=ready`, with CI asserting
ready only once the PR leaves draft. A "multi-pr declared without a recorded
trigger" check has a ready home. Rust already parses CLAUDE.md headers through a
generic, tested walker (`resolve_claude_md_header` in `visibility.rs`), so a
tooling-side check on a new header is a closure, not a subsystem.

### Tensions

**T1 -- The "should" preference contradicts a stated universal principle, which
the codebase already contradicts elsewhere.** Principle P1
(`references/workflow-principles.md`) says usable value is the unit of work:
default to one PR, split only for a hard constraint or genuine incremental value,
"never by mechanism." Reviewability is not a legitimate reason to split under P1.
But `references/coordination-strategy.md` lists "a single PR would exceed the
configured reviewability ceiling" as a recorded split trigger, and shirabe's own
CLAUDE.md ships a `## Reviewability Ceiling:` header to configure it. So shirabe
already permits reviewability-driven splitting at the coordination altitude while
forbidding it at the plan altitude. The author's "other orgs prefer small atomic
increments because it's easier to review" is a reviewability argument -- currently
principle-forbidden in one place and principle-blessed in another. This
inconsistency has to be resolved before the preference can be specified.

**T2 -- An orthogonal tracking field is the shape a prior decision rejected.**
`DESIGN-capstone-orchestration.md` Decision G considered an orthogonal
`coordinated: true` flag layered over `multi-pr` and rejected it: "splits the
coordinated effort's identity across two fields and permits invalid combinations
(`single-pr` + coordinated); a single enum has no invalid state and gives the
validator one branch." Adding a tracking field alongside `execution_mode` is the
same shape. The distinguishing argument is available -- `coordinated` *is* a
cardinality value, whereas tracking is not, so the two fields are genuinely
orthogonal rather than one field split in half -- but it has to be made
explicitly, and the invalid-combination question (single-pr + issues; multi-pr +
no issues but `/work-on M<N>` as the only scheduler) has to be answered cell by
cell.

**T3 -- Milestone-worthiness may be the wrong frame for what shirabe milestones
actually are.** The author's intuition is about signal: a plan forced into
several PRs by mechanical necessity isn't a project milestone. But shirabe
milestones carry no strategic semantics -- no progress rollup, no completion
trigger, no cascade participation. They are an issue-selection filter for
`/work-on`, plus GitHub-UI grouping. A single ROADMAP can already spawn one
roadmap-level milestone plus one per feature-PLAN, so "milestone" is already a
per-artifact bookkeeping unit rather than a project landmark. The honest
restatement of the author's question is therefore mechanical, not significance-
based: *does this plan need a GitHub-side grouping handle, or do bare issues
suffice?* That is a real question with a cheap wrong answer (it degrades one
entry-point ergonomic, not correctness) -- but it is not the significance
judgment the framing implies.

**T4 -- The trust the author wants from the "can" gate is not deliverable
today.** The goal is that a multi-pr plan in a prefer-single repo becomes
reliable evidence that no other option existed. That holds only if every forcing
constraint is detectable. Repo-count is. Release/availability gates are, but only
in the cross-repo contract. Workflow-must-reach-main is not detectable at all.
Absent a same-repo Gate-node mechanism, the "can" gate formalizes what a careful
author already had to notice by hand -- it relocates the judgment rather than
removing it.

### Gaps

- What replaces `/work-on M<N>` as the "what's next" scheduler for an issueless
  multi-pr plan. Single-pr's answer (Issue Outlines plus `plan-to-tasks.sh`'s
  `waits_on` graph) exists but is bound to `/execute`'s shared-branch model, which
  multi-pr deliberately does not use.
- `skills/plan/scripts/plan-to-tasks.sh` parses `#N` GitHub references at task
  extraction for multi-pr rows. An issueless multi-pr PLAN has no `#N` to parse,
  so `plan-to-tasks-contract.md` needs a third source-var scheme (or a
  repurposed `plan_outline` scheme with a distinct internal-ID convention --
  multi-pr's dependency column keys on `#N`, so single-pr's `o-<slug>` is not a
  drop-in).
- Where `execution_mode: coordinated` is actually *set*. Phase 3.6's documented
  procedure only ever emits `single-pr` or `multi-pr`; no wiring to `coordinated`
  was found. Either an undocumented manual override or a genuine gap.
- Whether re-keying the Draft->Active approval gate is in scope for this work or
  a dependency on it.
- Documentation drift found in passing: `plan-format.md` still describes
  `execution_mode` as a two-value enum, omitting `coordinated`;
  `DESIGN-gha-doc-validation.md` still carries `status: Current` while describing
  a Go implementation that is Rust in the tree.

### Decisions

Recorded in `wip/explore_multi-pr-plan-decoupling_decisions.md`.

### User Focus

The author framed both halves as one theme while inviting a split into two
issues, and asked that the relationship between them be the deliverable. The
author also asked that contested points be resolved through `/decision` rather
than returned as questions.

## Accumulated Understanding

The author's diagnosis is correct and better-supported than the framing claimed:
`execution_mode` is a single fused flag, and tracking is a hardcoded consequence
of it. But the research reframes the work in three ways.

First, this is mostly a **generalization**, not an invention. Two proven
preference mechanisms already exist on the same `flag > CLAUDE.md-header >
default` stack -- `## Roadmap Issues:` for tracking, and `## PR Grouping Policy:`
plus `## Reviewability Ceiling:` for decomposition-with-named-triggers. Both are
scoped one altitude away from the plan-level decision. The natural design lifts
the coarsest-legal-grouping rule *up* to plan level and the issueless preference
*down* to PLAN, rather than authoring new mechanisms.

Second, the **"should" gate is blocked on a principle conflict, not on
plumbing**. P1 currently forbids reviewability-driven splitting while the
coordination contract permits it. Until that is resolved -- either P1 becomes a
default a repo can invert, or reviewability becomes a named trigger under P1 with
a configurable threshold -- the preference has nothing coherent to configure.
This is the pivotal open decision.

Third, the **"can" gate is real but partial**, and its trustworthiness depends on
a mechanism that exists for cross-repo and not for same-repo: Gate nodes for
release/availability dependencies. Generalizing Gate nodes to single-repo plans is
the enabling move that would make the "can" gate deliver the trust the author
wants. Without it, "can" formalizes rather than removes the judgment.

On the milestone question, the counter-hypothesis largely holds as stated: today
milestone-worthiness has fully collapsed into multi-PR-ness, and shirabe
milestones carry too little semantics to bear a significance judgment. But the
seam the author wants already exists mechanically -- Phase 2 *derives* the
milestone title early and Phase 7 *creates* it late, gated only on
`execution_mode` -- so exposing the gate as a decision is cheap. The right
question to expose is mechanical ("does this plan need a grouping handle"), not
strategic ("is this a milestone").

The two halves of the author's theme are separable in delivery but share one
mechanism: a preference-resolution stack read by `/plan` and hinted at by the
validator's existing draft-tolerable advisory layer. The tracking half is nearly
shovel-ready (proven precedent, narrow blast radius, one consumer). The
decomposition half is blocked on the P1 question and, for full trust, on
same-repo Gate nodes.

## Decision: Crystallize
