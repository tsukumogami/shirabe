---
schema: design/v1
status: Current
upstream: docs/prds/PRD-contradiction-settlement.md
problem: |
  The koto-templated skills and the references they and /scope's hops load
  state the same rules in several places that disagree, often against the
  script or template gate that decides what happens, and carry prose no run
  acts on. Execution needs a located, reasoned list to edit from, and later
  gate and ablation work needs stable identifiers to depend on.
decision: |
  A 48-item inventory read at 662f6ec (38 mechanical, 10 policy; two found during execution), each item
  with a kebab-case identifier, every side located by line range and a
  file-unique excerpt, and a winner chosen by one rule: the side the code
  enforces wins, then the file the state directive points at, then the
  file that owns the topic. Policy items go to a person as decisions. A
  dead-prose inventory by category with per-profile totals, and a list of
  withholding candidates kept out of this feature.
rationale: |
  Code-first matches what runs today, so fixing the prose changes no
  behavior; everything that would change behavior is by definition a
  policy call and goes to a person. Excerpts rather than line numbers
  survive the edits earlier work items make. Per-skill work items keep each
  change reviewable and let a later feature wait on one identifier.
---

# DESIGN: Contradiction Settlement

## Status

Current. The work landed in these pull requests, each squash-merged into
`main` as the commit beside it:

- #531, `d34134d`: the ten policy decisions, recorded under `docs/decisions/`.
- #534, `44bd606`: /review-plan.
- #541, `dcf925f`: /deliver, /brief and /prd.
- #557, `3cc4c54`: /work-on.
- #579, `aa103ec`: the baseline manifest change that /execute's settlement
  needed.
- #545, `273f7ae`: /execute.
- #586, `c4226c3`: /scope and /charter.
- #637, `92fd1c5`: /design.
- #658, `354ff38`: /plan.
- #660, `0398358`: /brief's and /prd's share of the policy decisions.
- #665, `3c66996`: the re-count.
- #507, `a2081b5`: this design, the inventory and the measuring script, and
  the coordination of the pull requests above.

Each inventory item below names the pull requests that settled it. The node
index in #507's description shows every pull request open at a head commit,
because that description was written before the nodes merged and can't be
edited now. It isn't the record: the merge gate reads each pull request's
state live from GitHub, and the list above is what merged.

## Context and Problem Statement

A run of `/work-on`, `/execute`, `/scope` or `/deliver` reads three kinds of
text: the skill's SKILL.md, resident for the whole run; the koto template's
directive for each state it visits; and whichever references those two
name. Under `/scope`, each hop also loads `/brief`, `/prd`, `/design` or
`/plan` and their phase files. The baseline pin (pull request #488) records
which files each of five profiles loads and how many instruction tokens that
comes to. Behind the prose sit scripts and template gates that decide what
actually happens: `resume-probe.sh` decides whether a state file is valid,
`push-and-record.sh` decides how a push is made, the validator's FC and L
checks decide whether a document passes.

Reading every loaded file against the others and against that code at
`662f6ec` turns up 48 places where two statements disagree about the same
situation. They fall into three shapes:

- **Prose against code.** A reference says `phase_pointer: phase-0`; the
  probe rejects anything but an integer. A format reference lists PLAN
  complexity values the validator's FC05 rejects, and FC11's message sends
  the agent to that reference.
- **Prose against prose, one side stale.** A phase file says to commit a
  plan that now lives only as a koto context key. `/execute`'s SKILL.md
  describes a state-file projection nothing writes.
- **Prose against prose where the choice is open.** Whether to force-push
  after a rebase; how many retries before escalating; whether a child skill
  opens its own pull request under `/scope`.

The requirements this design answers, as written before execution (the
policy items have since been decided):

- Every loaded file for the five profiles is examined, and each disagreement
  names every side as a path and line range at one commit, with an excerpt
  that occurs once in its file so later work can find it after lines move
  (PRD R1, R3).
- Each item has a stable kebab-case identifier; the list is closed when this
  design is accepted (R4).
- A mechanical item names the surviving statement and why, naming the
  enforcing script or gate when there is one; when code wins, one prose
  statement is rewritten to match and the others go (R5).
- An item is policy when its winner would change whether the workflow
  pushes, force-pushes, merges, files issues, asks for or skips approval,
  retries, or stops; when unsure, policy. Force-push after a rebase, retry
  caps, child-skill steps under `/scope` (with `/design`'s inline-decision
  fallback) and issue filing under `--auto` are policy (R6).
- A policy item is a decision with context, problem, explained options and
  one recommendation, and its winner stays `open` (R9, R10).
- Dead prose is inventoried in four categories with every duplicate's
  survivor named, per-profile totals in tokens and as a share of raw load,
  and no deletion of a rule's only statement: those are withholding
  candidates, out of this feature (R11 to R13).
- Execution waits for the baseline pin, finds spans by excerpt, stops an item
  whose excerpt is missing or ambiguous, and ends with a re-count (R14 to
  R19).

## Decision Drivers

- **No behavior change without a person.** Settling a contradiction by
  editing prose must not quietly change what the workflow does; anything that
  would is a decision for the policy owner.
- **Findable after edits.** Line numbers move as soon as the first work item
  lands. Each location has to survive that.
- **Citable one at a time.** A later gate feature must be able to wait on a
  single item.
- **Reviewable diffs.** Each work item should be small enough that a reviewer
  can check every winner against its cited script.
- **No silent withholding.** A rule loses its last loaded statement only in
  the ablation feature, deliberately.
- **Public content.** Nothing committed names anything outside the public
  repositories.

## Considered Options

### Decision 1: How a winner is chosen

**Option 1a: Code first, then the directive's file, then the topic owner
(chosen).** If a script, validator check or template gate enforces one side,
that side wins. Otherwise the file the state directive points the agent at
wins, because it is what the agent reads at the moment of acting. Otherwise
the file that owns the topic (the reference that says it is the single
statement, or the shared reference several skills load) wins.

**Option 1b: Newest statement wins.** Use git history to pick the side edited
most recently. Rejected: several stale statements were touched recently for
unrelated reasons, and recency says nothing about which side the code
follows.

**Option 1c: Decide each item on its merits with no rule.** Rejected: 38
mechanical items decided ad hoc would produce inconsistent winners, and a
reviewer would have no rule to check a winner against.

### Decision 2: How each location is recorded

**Option 2a: Path, line range and a file-unique excerpt at one commit
(chosen).** Matches the baseline pin's rule-key form (`<path>#L<start>-L<end>`)
and adds text a work item can search for after lines move. For a span that
is a verbatim copy of other text in the same file, the excerpt is the
nearest unique line above it, marked `above:`.

**Option 2b: Line ranges only.** Rejected: the first work item to land
invalidates every later item's locations.

**Option 2c: Wait for a rule registry and key everything by rule id.**
Rejected: no registry exists, and the gate feature that would build one wants
to cite these items first. When a registry lands, its ids replace these
identifiers.

### Decision 3: How work is split into work items

**Option 3a: One work item per skill for its mechanical items and dead
prose, one per policy decision, one for the final re-count (chosen).** A
skill's SKILL.md, template and references change together, so one reviewer
reads one skill's diff at a time; a policy item's edit waits only on its own
decision.

**Option 3b: One work item per contradiction.** Rejected: 38 pull requests
for mechanical fixes, many of them one line, with heavy overlap in the same
files and constant rebasing.

**Option 3c: One work item per dead-prose category across all skills.**
Rejected: a category-wide diff touches every skill at once, and a reviewer
would have to hold all of them in mind.

### Decision 4: What happens to a file several skills load

`phase-6-pr.md` (loaded by `/work-on` and `/execute`),
`worktree-discipline.md` (loaded by `/execute` and `/scope`) and
`decision-protocol.md` (loaded under `--auto` by several skills) each carry
statements that are wrong for one caller.

**Option 4a: Drop the pointer from the caller the file does not fit
(chosen).** `/execute` stops loading `phase-6-pr.md` and
`worktree-discipline.md`; its own directives already state its rules. The
files stay correct for their remaining callers.

**Option 4b: Split each file per caller.** Rejected: two copies of shared
rules is the duplication this feature removes.

**Option 4c: Add caller-conditional paragraphs.** Rejected: every caller then
loads every other caller's rules, which is the dead-prose problem again.

## Decision Outcome

The inventory below has 48 items: 38 mechanical, each with a winner chosen by
the code-first rule, and 10 policy items put to the policy owner with a recommendation,
all since decided and recorded under `docs/decisions/`.
Every PRD R2 item maps to at least one identifier. Dead prose comes to
28.2% of `/work-on`'s raw load, 51.0% of `/execute`'s single-pr load, 62.4% of
its coordinated load, 27.9% of `/deliver`'s and 12.2% of `/scope`'s, plus
27,032 tokens of zero-weight plugin references that `scope-reference-table-vs-lazy-load`
stops `/scope` from telling the agent to read. Five withholding candidates
are listed and left alone.

The pieces fit because each one answers a driver without weakening another:
code-first means a mechanical fix never changes behavior, so the only
behavior changes are the policy decisions a person makes; excerpts keep the
locations valid across the per-skill work items; and per-skill work items
keep diffs reviewable while the identifiers let later work cite one item.

## Solution Architecture

### Inventory commit

Every location below is at `662f6ec` on `main`. Every file under `skills/`,
`references/`, `scripts/` and `crates/` is identical there to the baseline
pin's commit `2a3719e`, so a line number is the same at both.

### Files examined

A file counts as examined for a profile when the load manifest lists it or a
loaded directive or SKILL.md instructs the agent to read or follow it. Files a
skill only mentions (for example `/execute`'s SKILL.md naming the
parent-skill references, or `/plan`'s SKILL.md naming its templates) were
checked and are not listed.

- `work-on`, 27 files from the load manifest plus the template: `skills/work-on/koto-templates/work-on.md`, `.claude/shirabe-extensions/work-on.md`, `references/decision-presentation.md`, `references/decision-protocol.md`, `references/default-action-conversion.md`, `references/fixes/sub-agent-dispatch.md`, `references/koto-session-retention.md`, `references/pr-body-conformance.md`, `skills/private-content/SKILL.md`, `skills/public-content/SKILL.md`, `skills/work-on/SKILL.md`, `skills/work-on/references/agent-instructions/phase-3-analysis.md`, `skills/work-on/references/finishing-obligations.md`, `skills/work-on/references/koto-context-conventions.md`, `skills/work-on/references/phases/phase-0-context-injection.md`, `skills/work-on/references/phases/phase-1-setup.md`, `skills/work-on/references/phases/phase-2-introspection.md`, `skills/work-on/references/phases/phase-3-analysis.md`, `skills/work-on/references/phases/phase-4-implementation.md`, `skills/work-on/references/phases/phase-4a-scrutiny.md`, `skills/work-on/references/phases/phase-4b-review.md`, `skills/work-on/references/phases/phase-4c-qa.md`, `skills/work-on/references/phases/phase-5-finalization.md`, `skills/work-on/references/phases/phase-6-design-diagram-update.md`, `skills/work-on/references/phases/phase-6-pr.md`, `skills/work-on/references/review-panel-orchestration.md`, `skills/work-on/references/verification-map.md`, `skills/writing-style/SKILL.md`. Also read because a directive or SKILL.md names it or it enforces a side: `references/wip-hygiene.md`, `skills/work-on/references/phases/phase-2.5-worktree-discipline.md`, `skills/work-on/scripts/retry-clearing_test.sh`.
- `execute-single-pr`, 6 files from the load manifest plus the template: `skills/execute/koto-templates/execute.md`, `references/pr-body-conformance.md`, `references/worktree-discipline.md`, `skills/execute/SKILL.md`, `skills/execute/references/cross-issue-context.md`, `skills/work-on/references/phases/phase-2.5-worktree-discipline.md`, `skills/work-on/references/phases/phase-6-pr.md`. Also read because a directive or SKILL.md names it or it enforces a side: `skills/execute/references/cross-issue-context.md`, `skills/work-on/references/phases/phase-2.5-worktree-discipline.md`, `references/worktree-discipline.md`, `skills/execute/scripts/`, `skills/plan/scripts/plan-to-tasks.sh`.
- `execute-coordinated`, 1 files from the load manifest plus the template: `skills/execute/koto-templates/execute-coordinated.md`, `skills/execute/SKILL.md`. Also read because a directive or SKILL.md names it or it enforces a side: `skills/execute/scripts/`.
- `deliver`, 1 files from the load manifest plus the template: `skills/deliver/koto-templates/deliver.md`, `skills/deliver/SKILL.md`. Also read because a directive or SKILL.md names it or it enforces a side: `skills/execute/scripts/execute-open.sh`.
- `scope`, 69 files from the load manifest plus the template: `skills/scope/koto-templates/scope.md`, `references/decision-presentation.md`, `references/decision-report-format.md`, `references/fixes/sub-agent-dispatch.md`, `references/parent-skill-child-inspection.md`, `references/parent-skill-pattern.md`, `references/parent-skill-resume-ladder-template.md`, `references/parent-skill-security.md`, `references/parent-skill-state-schema.md`, `references/worktree-discipline.md`, `skills/brief/SKILL.md`, `skills/brief/references/brief-format.md`, `skills/brief/references/phases/phase-0-setup.md`, `skills/brief/references/phases/phase-1-discover.md`, `skills/brief/references/phases/phase-2-draft.md`, `skills/brief/references/phases/phase-3-structural-fill.md`, `skills/brief/references/phases/phase-4-validate.md`, `skills/brief/references/phases/phase-5-finalize.md`, `skills/design/SKILL.md`, `skills/design/references/design-format.md`, `skills/design/references/lifecycle.md`, `skills/design/references/phases/phase-0-setup-freeform.md`, `skills/design/references/phases/phase-0-setup-prd.md`, `skills/design/references/phases/phase-1-decomposition.md`, `skills/design/references/phases/phase-2-execution.md`, `skills/design/references/phases/phase-3-cross-validation.md`, `skills/design/references/phases/phase-4-architecture.md`, `skills/design/references/phases/phase-5-security.md`, `skills/design/references/phases/phase-6-final-review.md`, `skills/design/references/quality/considered-options-structure.md`, `skills/plan/SKILL.md`, `skills/plan/references/phases/phase-1-analysis.md`, `skills/plan/references/phases/phase-2-milestone.md`, `skills/plan/references/phases/phase-3-decomposition.md`, `skills/plan/references/phases/phase-4-agent-generation.md`, `skills/plan/references/phases/phase-5-dependencies.md`, `skills/plan/references/phases/phase-6-review.md`, `skills/plan/references/phases/phase-7-creation.md`, `skills/plan/references/plan-format.md`, `skills/plan/references/quality/plan-doc-structure.md`, `skills/plan/references/templates/agent-prompt.md`, `skills/prd/SKILL.md`, `skills/prd/references/phases/phase-1-scope.md`, `skills/prd/references/phases/phase-2-discover.md`, `skills/prd/references/phases/phase-3-draft.md`, `skills/prd/references/phases/phase-4-validate.md`, `skills/prd/references/prd-format.md`, `skills/public-content/SKILL.md`, `skills/review-plan/SKILL.md`, `skills/review-plan/references/phases/phase-0-setup.md`, `skills/review-plan/references/phases/phase-1-scope-gate.md`, `skills/review-plan/references/phases/phase-2-design-fidelity.md`, `skills/review-plan/references/phases/phase-3-ac-discriminability.md`, `skills/review-plan/references/phases/phase-4-sequencing.md`, `skills/review-plan/references/phases/phase-5-verdict.md`, `skills/review-plan/references/templates/ac-discriminability-taxonomy.md`, `skills/review-plan/references/templates/review-result-schema.md`, `skills/scope/SKILL.md`, `skills/scope/references/decision-record-design-re-evaluation.md`, `skills/scope/references/decision-record-design-rejection.md`, `skills/scope/references/decision-record-prd-re-evaluation.md`, `skills/scope/references/decision-record-prd-rejection.md`, `skills/scope/references/phases/phase-0-setup.md`, `skills/scope/references/phases/phase-1-discovery.md`, `skills/scope/references/phases/phase-2-chain-orchestration.md`, `skills/scope/references/phases/phase-3-exit-finalization.md`, `skills/scope/references/phases/phase-4-cleanup.md`, `skills/scope/references/phases/phase-resume.md`, `skills/scope/references/state-schema.md`, `skills/writing-style/SKILL.md`. Also read because a directive or SKILL.md names it or it enforces a side: `references/decision-protocol.md`, `references/issues-table.md`, `skills/scope/scripts/`, `skills/plan/scripts/`, `crates/shirabe-validate/src/`.

### Coverage of the PRD's required items

| PRD R2 item | Identifier(s) |
|---|---|
| 1 | `force-push-after-rebase` |
| 2 | `retry-caps` |
| 3 | `panel-round-counter` |
| 4 | `panel-detail-files-in-wip` |
| 5 | `decision-recording-channel` |
| 6 | `commit-koto-context-artifacts` |
| 7 | `worktree-discipline-vs-drift-state` |
| 8 | `execute-pr-title-type` |
| 9 | `scope-reference-table-vs-lazy-load` |
| 10 | `plan-single-pr-draft-commit` |
| 11 | `plan-complexity-values` |
| 12 | `plan-required-sections` |
| 13 | `scope-state-initial-values` |
| 14 | `design-spawned-from-shape` |
| 15 | `design-superseded-location` |
| 16 | `design-implementation-issues-owner` |
| 17 | `child-steps-under-scope`, `design-inline-decision-fallback` |
| 18 | `plan-issue-filing-under-auto` |
| 19 | `fc10-already-caught` |

### Contradictions

Each item lists every statement, what the code does where it decides the
matter, and the winner. Excerpts are verbatim and occur once in their file.

### Policy calls

Each was open when the inventory was taken, and each has since been decided by the policy owner and recorded under `docs/decisions/`; every item below links its record. The options and recommendations are as they were put to the policy owner.

#### `force-push-after-rebase`

Force-push after a rebase. Class: **policy**. Profiles: `work-on`, `execute-single-pr`. PRD R2 item 1. Settled by #557, #545.

Statements:

- `skills/work-on/references/phases/phase-6-pr.md#L25-L29`: push, and after a rebase use --force-with-lease. Excerpt: `git push -u origin <branch>`
- `skills/work-on/references/phases/phase-6-pr.md#L7`: rebase if the branch is behind. Excerpt: `Rebase on latest main if behind. Resolve`
- `skills/work-on/koto-templates/work-on.md#L2029`: pr_creation pushes with a plain git push -u. Excerpt: `` Push with `git push -u origin {{BRANCH}}`. ``
- `skills/execute/SKILL.md#L1228-L1232`: no execute push path force-pushes. Excerpt: `` - **Pushes**, only through `scripts/push-and-record.sh` ``
- `skills/work-on/references/finishing-obligations.md#L65`: rebase currency is deliberately advisory. Excerpt: `` | Rebase currency beyond mergeability | `merge_state_clean` ``

What runs:

- `skills/execute/scripts/push-and-record.sh#L25-L31`: pushes an explicit refspec and never with a force option. Excerpt: `# The push is exactly`
- `skills/work-on/koto-templates/work-on.md#L1963-L1973`: pre_pr_evidence assumes history is final before it; a later rebase leaves its referents unchecked. Excerpt: `The finishing obligations that can be decided`

Winner: decided by the policy owner (record linked below). Recommended: option 2, rebase if behind, before verification, with a plain push only.

- **Context.** phase-6-pr.md, which /work-on loads at pr_creation and /execute loads at every ci_monitor visit, tells the agent to rebase when behind and push with --force-with-lease. The /work-on template pushes plainly, /execute says nothing it runs force-pushes, and push-and-record.sh refuses a force push.
- **Problem.** An agent following phase-6 either gets a rejected push under /execute or rewrites a shared branch; under /work-on a rebase after pre_pr_evidence means the gate judged a tip that no longer ships.
- **Option 1: Never rebase at PR time and never force-push.** Simplest and matches the code today, but a branch that falls behind main stays behind until a person merges main in.
- **Option 2 (recommended): Rebase if behind, before verification, with a plain push only.** Keeps the no-force rule true for both callers and every gate sees the tip that ships; the rebase moves earlier in /work-on.
- **Option 3: Allow --force-with-lease inside push-and-record.sh, leased on expected_head.** Keeps rebase-then-push working, but rewrites history on a branch several children commit to, which the autonomy section says needs a person.
- **Why the recommendation.** It is the only option that keeps /execute's no-force guarantee and /work-on's gate evidence both true.
- **Decided.** See [`docs/decisions/DECISION-contradiction-force-push-after-rebase-2026-09-28.md`](../../decisions/DECISION-contradiction-force-push-after-rebase-2026-09-28.md).

#### `retry-caps`

Retry caps. Class: **policy**. Profiles: `work-on`, `execute-single-pr`. PRD R2 item 2. Settled by #557.

Statements:

- `skills/work-on/references/review-panel-orchestration.md#L16-L17`: after 2 blocking_retry outcomes the next pass must escalate. Excerpt: `` `koto overrides list`. The retry loop is ``
- `skills/work-on/references/phases/phase-4a-scrutiny.md#L79`: escalate after 2+ retry cycles. Excerpt: `If a blocking finding cannot be resolved`
- `skills/work-on/references/phases/phase-4c-qa.md#L72`: escalate after 2+ retry cycles. Excerpt: `If a defect cannot be resolved (after 2+`
- `skills/work-on/references/phases/phase-4b-review.md#L71-L73`: no cap. Excerpt: `## Escalation`
- `skills/work-on/koto-templates/work-on.md#L1725`: analysis: up to 3. Excerpt: `` Self-loop with `scope_changed_retry` (up ``
- `skills/work-on/koto-templates/work-on.md#L1738`: implementation: up to 3. Excerpt: `` Self-loop with `partial_tests_failing_retry` ``
- `skills/work-on/references/phases/phase-6-pr.md#L55-L57`: CI: ask the user after 2-3 iterations. Excerpt: `If stuck after 2-3 iterations, ask the user.`
- `skills/work-on/references/phases/phase-6-pr.md#L66`: retry up to 3. Excerpt: `` - `pr_status: creation_failed_retry` (up ``

What runs:

- `skills/work-on/koto-templates/work-on.md#L754-L756`: every retry edge is unconditional; nothing counts visits. Excerpt: `scrutiny_outcome: blocking_retry`
- `skills/execute/koto-templates/execute.md#L1469-L1475`: ci_monitor fix pushes go through push-and-record.sh with no counter. Excerpt: `If the gate fails because a check failed,`

Winner: decided by the policy owner (record linked below). Recommended: option 1, state each cap once, in the looping state's directive.

- **Context.** The review panels, analysis, implementation, PR creation and CI loops each state a limit somewhere, the limits differ (2, 2+, 3, 2-3, none), and nothing in koto counts visits. The CI line tells the agent to ask the user, which /execute's --auto mandate forbids.
- **Problem.** The agent has no single cap to apply, the panel cap's scope (per panel or shared) is unstated, and under --auto the CI instruction is unfollowable.
- **Option 1 (recommended): State each cap once, in the looping state's directive.** One shared panel cap of 2 blocking retries across the three panels, 3 for analysis, implementation and PR creation, 3 fix pushes for CI then failing_unresolvable, never ask under --auto. The directive is what the agent reads when it decides.
- **Option 2: Have koto count visits and enforce the caps.** Enforced rather than stated, but needs koto support that does not exist for this yet.
- **Option 3: Drop the caps.** Removes the contradiction by removing the limit; loops are then bounded only by the agent's judgment.
- **Why the recommendation.** It gives every loop one number in the place the agent reads it, and removes the --auto violation without waiting on koto. These directive caps are temporary: when koto enforces retry caps from its attempt counts, the numbers stay the same and the directive prose becomes a deletion candidate.
- **Decided.** See [`docs/decisions/DECISION-contradiction-retry-caps-2026-09-28.md`](../../decisions/DECISION-contradiction-retry-caps-2026-09-28.md).

#### `ci-fix-ends-run-unverified`

A CI fix ends the run without re-checking CI. Class: **policy**. Profiles: `work-on`. Settled by #557.

Statements:

- `skills/work-on/references/phases/phase-6-pr.md#L3`: monitor until all checks pass. Excerpt: `Create the PR and monitor CI until all checks`
- `skills/work-on/SKILL.md#L420`: output is a PR with passing CI. Excerpt: `An open, ready PR with passing CI, referencing`
- `skills/work-on/koto-templates/work-on.md#L2123`: done directive assumes green CI. Excerpt: `The workflow is complete. The PR has been`
- `skills/work-on/references/finishing-obligations.md#L20`: CI green is gate-enforced. Excerpt: `` | CI is green | `ci_monitor` | `ci_passing` ``
- `skills/work-on/koto-templates/work-on.md#L2054`: directive points the agent at failing_fixed. Excerpt: `If the gate fails, fix what you can and submit`

What runs:

- `skills/work-on/koto-templates/work-on.md#L1272-L1278`: failing_fixed routes to done with no gate. Excerpt: `# failing_fixed: agent pushed a follow-up`
- `skills/work-on/koto-templates/work-on.md#L1279-L1284`: the fallback edge also reaches done. Excerpt: `failure_reason: "ci_monitor: unresolvable`

Winner: decided by the policy owner (record linked below). Recommended: option 1, failing_fixed loops back to ci_monitor and the fallback goes to done_blocked.

- **Context.** /work-on promises a PR with passing CI, but ci_monitor's failing_fixed outcome and its fallback edge go to done without re-checking CI.
- **Problem.** A run can end reporting success on red or unfinished CI; which behavior is intended decides whether the run stops or keeps polling.
- **Option 1 (recommended): failing_fixed loops back to ci_monitor and the fallback goes to done_blocked.** Enforces the skill's own contract at the cost of one more poll per fix.
- **Option 2: Keep the routing and correct the prose to say CI is not re-checked.** No behavior change, but the output contract gets weaker.
- **Why the recommendation.** The promise of passing CI is what callers rely on, and the cost is one poll.
- **Decided.** See [`docs/decisions/DECISION-contradiction-ci-fix-ends-run-unverified-2026-09-28.md`](../../decisions/DECISION-contradiction-ci-fix-ends-run-unverified-2026-09-28.md).

#### `cross-issue-context-no-consumer`

Cross-issue context is built but nothing reads it. Class: **policy**. Profiles: `execute-single-pr`. Settled by #545.

Statements:

- `skills/execute/references/cross-issue-context.md#L3-L13`: before each child, concatenate earlier children's summaries into current-context.md. Excerpt: `Before dispatching each child, collect summaries`
- `skills/execute/koto-templates/execute.md#L1377`: spawn_and_await points at cross-issue-context.md. Excerpt: `koto materializes one child per task using`
- `skills/execute/koto-templates/execute.md#L1379`: do not inspect children. Excerpt: `**Tick 2 — complete**: once all children`
- `skills/execute/SKILL.md#L1211-L1213`: the closed write-target set has no loose file at the checkout root. Excerpt: `` 2. **Closed write-target set.** `/execute`'s ``

What runs:

- `skills/plan/scripts/plan-to-tasks.sh#L744-L751`: children receive only task variables; koto schedules them. Excerpt: `$issue_source, ARTIFACT_PREFIX: $artifact_prefix,`

Winner: decided by the policy owner (record linked below). Recommended: option 2, wire /work-on's analysis phase to read it, built outside the work tree.

- **Context.** /execute tells the agent to build current-context.md from completed children's summaries before each child, but koto schedules the children, no /work-on file reads that file, and only evals assert it.
- **Problem.** Deleting the step removes a capability the skill advertises; keeping it leaves an instruction with no effect and a stray file in the work tree.
- **Option 1: Delete the step.** Honest about what runs today; drops the advertised carry-forward.
- **Option 2 (recommended): Wire /work-on's analysis phase to read it, built outside the work tree.** Makes the capability real; needs a template change in both skills.
- **Option 3: Leave it.** No work, but the instruction keeps claiming an effect it does not have.
- **Why the recommendation.** Carry-forward is listed as a capability and the evals assert it; if the wiring cannot land soon, deleting beats prose with no effect.
- **Decided.** See [`docs/decisions/DECISION-contradiction-cross-issue-context-no-consumer-2026-09-28.md`](../../decisions/DECISION-contradiction-cross-issue-context-no-consumer-2026-09-28.md).

#### `child-steps-under-scope`

Child skills run their own approval, push and pull-request steps under /scope. Class: **policy**. Profiles: `scope`. PRD R2 item 17. Settled by #586, #637, #658, #660.

Statements:

- `skills/brief/references/phases/phase-5-finalize.md#L73-L93`: /brief asks for approval even when both reviewers pass. Excerpt: `## 5.2 Request Explicit Approval`
- `skills/brief/references/phases/phase-5-finalize.md#L174-L192`: /brief pushes and runs gh pr create. Excerpt: `## 5.5 Create the PR`
- `skills/prd/references/phases/phase-4-validate.md#L202-L241`: /prd asks for approval and creates a PR. Excerpt: `### 4.5 Present to User`
- `skills/prd/SKILL.md#L154-L176`: /prd creates a branch when on an unrelated one and transitions the brief. Excerpt: `0. **Setup**: Ensure work happens on a feature`
- `skills/design/references/phases/phase-6-final-review.md#L181-L186`: /design commits, pushes and creates a PR. Excerpt: `### 6.6 Commit and PR`
- `skills/design/SKILL.md#L221-L243`: /design asks Plan or Approve only. Excerpt: `Run a complexity assessment based on the`
- `skills/plan/references/phases/phase-7-creation.md#L696-L728`: /plan asks about an upstream issue and runs gh issue edit. Excerpt: `### 7.8 Upstream Issue Update`
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L602-L606`: nothing pushes during the chain. Excerpt: `**Nothing pushes here.** The per-hop commits`
- `skills/scope/SKILL.md#L655-L686`: closed write-target set; the publish script's gh calls are the only gh writes. Excerpt: `**Commits**, by Phase 2's per-hop commit`
- `references/fixes/sub-agent-dispatch.md#L64-L74`: children leave Draft/Proposed and the parent approves. Excerpt: `### 2. Parent-delegated-approval`

What runs:

- `skills/plan/references/phases/phase-1-analysis.md#L83-L95`: /plan hard-stops unless the DESIGN is already Accepted. Excerpt: `**STOP and inform user if status is not "Accepted".**`
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L381-L418`: /scope detects a reject only through the child's discard commit. Excerpt: `## Phase-N Reject Handling`

Winner: decided by the policy owner (record linked below). Recommended: option 1, children keep their verdict and status transition but skip push, PR, cleanup commit, branch creation and routing prompts under the sentinel.

- **Context.** Each child skill runs its own approval prompt, status transition, commits and, for /brief, /prd and /design, a push and a pull request, and none of those steps checks the parent_orchestration sentinel. /scope promises one push and one PR at exit and a closed write set. The dispatch reference says children should leave artifacts unapproved for the parent, but /design and /plan require their upstream already Accepted and /scope never transitions anything.
- **Problem.** Under /scope the children push and open PRs /scope says never happen, and the reference that defines child behavior under a parent describes a flow that would stall the chain.
- **Option 1 (recommended): Children keep their verdict and status transition but skip push, PR, cleanup commit, branch creation and routing prompts under the sentinel.** Under --auto the child takes the recommended approval and says so. The dispatch reference is rewritten to match. Smallest change that makes every stated promise true.
- **Option 2: Parent-delegated approval as the dispatch reference describes.** Adds a per-hop approval and transition to /scope and changes /design's and /plan's preconditions.
- **Option 3: Keep today's behavior and drop /scope's one-push promise.** No child change, but a no-intent /scope run then pushes, and an intent run can open two PRs.
- **Why the recommendation.** It keeps the per-artifact gate the next hop depends on and removes only the steps that collide with /scope's publish model.
- **Decided.** See [`docs/decisions/DECISION-contradiction-child-steps-under-scope-2026-09-28.md`](../../decisions/DECISION-contradiction-child-steps-under-scope-2026-09-28.md).

#### `design-inline-decision-fallback`

/design's inline-decision fallback under a parent. Class: **policy**. Profiles: `scope`. PRD R2 item 17. Settled by #637.

Statements:

- `references/fixes/sub-agent-dispatch.md#L76-L86`: under a parent, /design resolves decisions inline and records decision_provenance. Excerpt: `### 3. Decision-bypass-with-inline-resolution`
- `skills/design/references/phases/phase-2-execution.md#L23-L50`: always spawn one /decision agent per question. Excerpt: `### 2.3 Spawn Decider Agents`
- `skills/design/SKILL.md#L145-L148`: Phase 2 delegates each question to the decision skill. Excerpt: `The core pattern is decompose-decide-validate:`

What runs:

- `skills/scope/scripts/testdata/design.md.fixture#L6`: a /scope fixture carries decision_provenance: inline-resolved. Excerpt: `decision_provenance: inline-resolved`

Winner: decided by the policy owner (record linked below). Recommended: option 2, make it checkable: under the sentinel, standard-tier questions resolve inline and critical ones go to /decision; add the field to the format reference.

- **Context.** The dispatch reference lets /design resolve decisions inline when a parent routes decisions back to itself; /design's own Phase 2 always spawns /decision, nothing defines when the fallback applies, and the provenance field is in no format reference or validator.
- **Problem.** Whether a /scope run bypasses /decision is left to the agent's judgment.
- **Option 1: Delete the fallback.** Every run spawns /decision agents; most expensive.
- **Option 2 (recommended): Make it checkable: under the sentinel, standard-tier questions resolve inline and critical ones go to /decision; add the field to the format reference.** A condition the agent can check, and irreversible questions still get the full treatment.
- **Option 3: Resolve every question inline under /scope.** Cheapest; loses /decision's rigor on the questions that need it.
- **Why the recommendation.** It turns an unstated judgment into a checkable rule without giving up /decision where it matters.
- **Decided.** See [`docs/decisions/DECISION-contradiction-design-inline-decision-fallback-2026-09-28.md`](../../decisions/DECISION-contradiction-design-inline-decision-fallback-2026-09-28.md).

#### `plan-issue-filing-under-auto`

/plan files issues and a milestone under --auto without approval. Class: **policy**. Profiles: `scope`. PRD R2 item 18. Settled by #658.

Statements:

- `skills/plan/SKILL.md#L68-L77`: an activation that files issues requires human approval. Excerpt: `PLAN docs use a unified Draft -> Active ->`
- `skills/plan/references/phases/phase-7-creation.md#L119-L203`: multi-pr step 7.1 files issues and a milestone with no approval step. Excerpt: `` Steps 7.1 through 7.4 apply when `execution_mode: ``
- `skills/plan/references/phases/phase-7-creation.md#L400-L401`: the approval step exists only on the coordinated path. Excerpt: `The multi-pr and single-pr branches above`
- `skills/plan/references/phases/phase-3-decomposition.md#L638-L663`: tracking is asked separately, but nothing asks it. Excerpt: `6. **Present the recommendation to the user`
- `skills/scope/SKILL.md#L685`: gh pr create and gh pr edit are /scope's only gh writes. Excerpt: `` `gh pr create` and that `gh pr edit` are ``

What runs:

- `skills/plan/references/phases/phase-7-creation.md#L81-L84`: default tracking is issues-and-milestone. Excerpt: `Where a level is stated it applies regardless`

Winner: decided by the policy owner (record linked below). Recommended: option 1, approval on every filing path; under --auto, file only when CLAUDE.md declares a Tracking Level header, else emit an issueless PLAN with outlines.

- **Context.** /plan's own rule says filing issues needs human approval, but the multi-pr path and single-pr-with-tracking file issues and a milestone with no approval step, and under --auto the tracking question is never asked. /scope forwards --auto to /plan on intent runs.
- **Problem.** An unattended run can create GitHub issues and a milestone that nobody approved.
- **Option 1 (recommended): Approval on every filing path; under --auto, file only when CLAUDE.md declares a Tracking Level header, else emit an issueless PLAN with outlines.** Makes the stated rule true and reuses the rule the coordinated path already follows.
- **Option 2: Never file under --auto or under a parent.** Simplest; a caller who wants issues runs /plan again interactively.
- **Option 3: Keep the behavior and rewrite the rule to allow it.** No behavior change; unattended filing becomes intended.
- **Why the recommendation.** It keeps filing possible where a repository has opted in and otherwise produces a PLAN the validator already accepts.
- **Decided.** See [`docs/decisions/DECISION-contradiction-plan-issue-filing-under-auto-2026-09-28.md`](../../decisions/DECISION-contradiction-plan-issue-filing-under-auto-2026-09-28.md).

#### `scope-abandonment-draft-plan`

/scope's abandonment exit writes a Draft PLAN that fails L01. Class: **policy**. Profiles: `scope`. Settled by #586.

Statements:

- `skills/scope/references/phases/phase-3-exit-finalization.md#L166-L186`: abandonment triggered at /plan writes the PLAN at Draft with a marker. Excerpt: `### Abandonment-Forced Exit`
- `skills/scope/references/phases/phase-3-exit-finalization.md#L44-L48`: a committed Draft PLAN is a violation. Excerpt: `` The chain completed through `/plan`. The ``
- `skills/plan/SKILL.md#L76-L77`: a committed PLAN at status Draft is a violation. Excerpt: `` `issues` waits for approval. A committed ``

What runs:

- `crates/shirabe-validate/src/lifecycle.rs#L862-L874`: the single-pr posture requires Active; L01 has no abandonment exemption. Excerpt: `` // Single-pr mid-PR. The PLAN is at `Active`: ``

Winner: decided by the policy owner (record linked below). Recommended: option 2, abandonment never writes a PLAN, only the upstream artifacts.

- **Context.** An abandonment exit triggered while /plan is running force-materializes the PLAN at Draft at its canonical path; the same reference and /plan's rules say a committed Draft PLAN is a violation, and the lifecycle check has no exemption.
- **Problem.** An abandoned run's branch fails the lifecycle check, so the exit meant to preserve work produces a red branch.
- **Option 1: The validator skips a PLAN carrying the abandonment marker.** Keeps the partial PLAN; adds an exemption to the validator.
- **Option 2 (recommended): Abandonment never writes a PLAN, only the upstream artifacts.** No exemption; the partial PLAN's content is lost unless the upstream drafts carry it.
- **Why the recommendation.** It needs no validator exemption, and a PLAN that never finished has little a later run could reuse.
- **Decided.** See [`docs/decisions/DECISION-contradiction-scope-abandonment-draft-plan-2026-09-28.md`](../../decisions/DECISION-contradiction-scope-abandonment-draft-plan-2026-09-28.md).

#### `multi-pr-plan-routing`

Whether /execute runs multi-pr PLANs. Class: **policy**. Profiles: `execute-single-pr`, `execute-coordinated`. Settled by #545.

Statements:

- `skills/execute/SKILL.md#L47-L52`: multi-pr is out of scope; send the user to /work-on. Excerpt: `` 1. **Path to a PLAN doc** (`docs/plans/PLAN-*.md`, ``
- `skills/execute/SKILL.md#L125-L132`: no refusal before koto init except three listed cases. Excerpt: `**koto is the only judge of the arguments.**`

What runs:

- `skills/execute/scripts/execute-open.sh#L133-L153`: anything not coordinated, including multi-pr, runs on execute.md. Excerpt: `# The template, from the PLAN's execution_mode,`

Winner: decided by the policy owner (record linked below). Recommended: option 1, refuse multi-pr in execute-open.sh, and add it to the listed refusals.

- **Context.** /execute's SKILL.md says multi-pr PLANs are out of scope and belong to /work-on, and /deliver and /scope route them there; execute-open.sh runs any non-coordinated PLAN, multi-pr included, on the single-pr template, and plan-to-tasks.sh can build tasks for it.
- **Problem.** Choosing a side either adds a refusal (the run stops where it used to proceed) or blesses a path the rest of the skills route away from.
- **Option 1 (recommended): Refuse multi-pr in execute-open.sh, and add it to the listed refusals.** Matches /deliver's and /scope's routing and the meaning of multi-pr (one PR per issue, landed through /work-on).
- **Option 2: Correct SKILL.md to say /execute runs multi-pr PLANs on the shared-branch template.** No behavior change, but a multi-pr PLAN then lands as one shared-branch PR, which is not what the mode means elsewhere.
- **Why the recommendation.** Every other entry point already treats multi-pr as /work-on's; the refusal makes /execute agree with them.
- **Decided.** See [`docs/decisions/DECISION-contradiction-multi-pr-plan-routing-2026-09-28.md`](../../decisions/DECISION-contradiction-multi-pr-plan-routing-2026-09-28.md).

#### `worktree-intent-change-owner`

Who judges an intent-changing rebase under /scope. Class: **policy**. Profiles: `scope`. Settled by #586.

Statements:

- `skills/scope/SKILL.md#L373-L378`: an intent-changing rebase halts and goes to the author. Excerpt: `Before each child invocation the loop runs`
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L111-L121`: the team lead resolves it in place when intent still holds, and escalates to the author only otherwise. Excerpt: `- **Escalation phase.** None / Informational`
- `skills/scope/SKILL.md#L130-L132`: team-lead discipline is vacuous here, since /scope spawns nothing. Excerpt: `R19's Team-Lead Operating Discipline binds`

Winner: decided by the policy owner (record linked below). Recommended: option 1, always put an intent-changing rebase to the author.

- **Context.** When main moves under a /scope run in a way that changes something the chain relies on, SKILL.md says the run halts and asks the author; the Phase 2 reference lets the team lead, which under /scope is the same agent running the chain, decide intent still holds and fix the citation in place. SKILL.md also says there is no team lead under /scope.
- **Problem.** Whether the running agent may approve its own continuation after an upstream change is a question of who approves, and no code enforces either side.
- **Option 1 (recommended): Always put an intent-changing rebase to the author.** Keeps a person on every change that alters what the chain committed to; an --auto run stops there.
- **Option 2: The running agent resolves in place when it judges intent unchanged, and escalates otherwise.** Fewer stops, but the agent judging the change is the one whose work it would invalidate.
- **Why the recommendation.** The classification is itself the judgment that matters, and the agent making it is the party being checked; SKILL.md already says there is no separate team lead under /scope.
- **Decided.** See [`docs/decisions/DECISION-contradiction-worktree-intent-change-owner-2026-09-28.md`](../../decisions/DECISION-contradiction-worktree-intent-change-owner-2026-09-28.md).

### Mechanical items

#### `panel-round-counter`

Panel retry round counter. Class: **mechanical**. Profiles: `work-on`. PRD R2 item 3. Settled by #557.

Statements:

- `skills/work-on/references/phases/phase-4a-scrutiny.md#L34-L41`: round N, 1 on the first pass, incremented on each retry. Excerpt: `koto context add <WF> scrutiny_results.json`
- `skills/work-on/references/phases/phase-4b-review.md#L34-L38`: round is always the literal 1. Excerpt: `koto context add <WF> review_results.json`
- `skills/work-on/references/phases/phase-4c-qa.md#L33-L36`: no round field. Excerpt: `koto context add <WF> qa_results.json < /dev/stdin`

What runs:

- `skills/work-on/koto-templates/work-on.md#L725-L731`: the panel gates check key presence; nothing reads round. Excerpt: `scrutiny_results:`

Winner: `skills/work-on/references/phases/phase-4a-scrutiny.md#L34-L41`. 4a's definition is the only one that is true on a second round; carry it into 4b and 4c. The retry-caps decision kept prose caps until koto enforces them, so the field stays.

#### `panel-retry-fix-location`

Where a panel's blocking fix happens. Class: **mechanical**. Profiles: `work-on`. Settled by #557.

Statements:

- `skills/work-on/koto-templates/work-on.md#L1797`: scrutiny: submit blocking_retry once the implementation agent has addressed the findings. Excerpt: `` Submit `scrutiny_outcome: passed` when all ``
- `skills/work-on/koto-templates/work-on.md#L1805`: review: the same. Excerpt: `` Submit `review_outcome: passed` when all ``
- `skills/work-on/references/phases/phase-4a-scrutiny.md#L31`: spawn the coder agent and re-enter this phase. Excerpt: `` - If any `blocking_count > 0`: collect blocking ``
- `skills/work-on/references/phases/phase-4a-scrutiny.md#L75`: spawn all three reviewers again. Excerpt: `Then spawn all three reviewers again. When`
- `skills/work-on/references/phases/phase-4b-review.md#L31`: blocking_retry routes to implementation; no self-loop. Excerpt: `` - If any `blocking_count > 0`: collect blocking ``
- `skills/work-on/references/phases/phase-4c-qa.md#L30`: the same as 4b. Excerpt: `` - If `scenarios_failed > 0`: submit `qa_outcome: ``

What runs:

- `skills/work-on/koto-templates/work-on.md#L754-L756`: blocking_retry goes to implementation. Excerpt: `scrutiny_outcome: blocking_retry`

Winner: `skills/work-on/references/phases/phase-4b-review.md#L31`. The template routes blocking_retry to implementation; 4b and 4c describe that, the two directives and 4a do not.

#### `decision-recording-channel`

Where decisions are recorded. Class: **mechanical**. Profiles: `work-on`, `scope`. PRD R2 item 5. Settled by #557.

Statements:

- `references/decision-protocol.md#L40-L50`: write a decision block in the wip artifact. Excerpt: `### Step 3: Decide and record`
- `references/decision-protocol.md#L88-L101`: and an index row in wip/<workflow>_<topic>_decisions.md, the source of truth. Excerpt: `## Recording decisions`
- `skills/work-on/SKILL.md#L410-L416`: record with koto decisions record. Excerpt: `### Decision Capture`
- `skills/work-on/references/phases/phase-4-implementation.md#L102-L106`: record with koto decisions record. Excerpt: `If an AC is literally under-specified or`
- `skills/work-on/koto-templates/work-on.md#L1727`: analysis: put decisions in the evidence field. Excerpt: `` Capture non-obvious decisions in the `decisions` ``
- `skills/work-on/references/koto-context-conventions.md#L41-L43`: do not stage artifacts in wip/. Excerpt: `` - **Do not stage artifacts in `wip/`.** `wip/` ``

What runs:

- `skills/work-on/koto-templates/work-on.md#L513-L518`: a decisions evidence field nothing reads. Excerpt: `made during analysis.`

Winner: `skills/work-on/SKILL.md#L410-L416`. koto decisions record is what the deferral audit trail reads, and nothing in /work-on reads the wip index. decision-protocol.md is shared with skills that still use the wip index, so it gains a clause saying koto-driven skills record through koto rather than losing its recording section; the evidence field is dropped or declared an alias.

#### `commit-koto-context-artifacts`

Steps that commit files which moved into koto context. Class: **mechanical**. Profiles: `work-on`. PRD R2 item 6. Settled by #557.

Statements:

- `skills/work-on/references/phases/phase-1-setup.md#L66-L68`: commit the baseline. Excerpt: `` `docs: establish baseline for <short-description>` ``
- `skills/work-on/references/phases/phase-3-analysis.md#L49`: commit the plan. Excerpt: `` Commit: `docs: create implementation plan` ``
- `skills/work-on/references/phases/phase-5-finalization.md#L121-L123`: commit the summary. Excerpt: `` Commit summary: `docs: add implementation ``
- `skills/work-on/koto-templates/work-on.md#L1999-L2001`: the summary commit lands there. Excerpt: `` `HEAD` then is an ancestor of `HEAD` now. ``
- `skills/work-on/references/phases/phase-4-implementation.md#L74`: tick off steps in the plan. Excerpt: `` Mark step complete in the plan: `- [x] <step>`. ``
- `skills/work-on/references/koto-context-conventions.md#L9-L21`: no on-disk copy exists at any point. Excerpt: `## Preferred: pipe via stdin`

What runs:

- `skills/work-on/koto-templates/work-on.md#L200-L210`: gates are context-exists on the keys. Excerpt: `setup_issue_backed:`

Winner: `skills/work-on/references/koto-context-conventions.md#L9-L21`. The artifacts live only as koto context keys and the gates check the keys; there is nothing on disk to commit.

#### `scratch-file-path`

Where scratch files go. Class: **mechanical**. Profiles: `work-on`. Settled by #557.

Statements:

- `skills/work-on/references/phases/phase-3-analysis.md#L40-L42`: write the plan under a per-session tmp directory (phase-1 convention). Excerpt: `3. Write the plan to a local file under the`
- `skills/work-on/references/phases/phase-2-introspection.md#L14-L18`: write to a local file, never deleted. Excerpt: `Write findings to a local file, then store`
- `skills/work-on/references/phases/phase-0-context-injection.md#L27-L31`: the same. Excerpt: `If you updated the content, store it back:`
- `skills/work-on/references/koto-context-conventions.md#L9-L37`: stdin, or a mktemp file deleted after use. Excerpt: `## Preferred: pipe via stdin`

Winner: `skills/work-on/references/koto-context-conventions.md#L9-L37`. The conventions file is the stated rule and phase-1 has no tmp-directory convention to point at.

#### `panel-detail-files-in-wip`

Reviewer detail files versus wip hygiene. Class: **mechanical**. Profiles: `work-on`. PRD R2 item 4. Settled by #557.

Statements:

- `skills/work-on/references/phases/phase-4a-scrutiny.md#L15-L24`: each reviewer writes a research file, work-on_<panel>_<focus>_<WF>.md, in the work-in-progress directory. Excerpt: `` Each reviewer writes full findings to `w ``
- `skills/work-on/references/phases/phase-4b-review.md#L15-L24`: the same. Excerpt: `` Each reviewer writes full findings to `w ``
- `skills/work-on/references/phases/phase-4c-qa.md#L15-L23`: the same. Excerpt: `` esearch/work-on_qa_<WF>.md` and returns: ``
- `skills/work-on/references/koto-context-conventions.md#L41-L43`: do not stage artifacts in wip/. Excerpt: `` - **Do not stage artifacts in `wip/`.** `wip/` ``
- `references/wip-hygiene.md#L49-L61`: wip/ is cleaned before the PR opens. Excerpt: `## Cleanup is two operations`

What runs:

- `skills/work-on/koto-templates/work-on.md#L1022-L1031`: the cleanup_done enum has no wip cleanup; nothing removes the files. Excerpt: `cleanup_done:`

Winner: `skills/work-on/references/koto-context-conventions.md#L41-L43`. The no-wip rule is already decided; reviewers use per-reviewer koto keys or mktemp files removed after aggregation.

#### `implementation-escalate-outcome`

Which outcome escalates from implementation. Class: **mechanical**. Profiles: `work-on`. Settled by #557.

Statements:

- `skills/work-on/references/phases/phase-4-implementation.md#L159`: stop a failed clearing block with partial_tests_failing_escalate. Excerpt: `echo "To stop the run, submit implementation_status:`
- `skills/work-on/references/phases/phase-4-implementation.md#L176`: that is the only exit reaching a terminal state. Excerpt: `A note on the escalate outcome named above.`

What runs:

- `skills/work-on/koto-templates/work-on.md#L597-L606`: blocked also reaches done_blocked. Excerpt: `implementation_status: partial_tests_failing_escalate`

Winner: `skills/work-on/koto-templates/work-on.md#L597-L606`. The template routes blocked to done_blocked; use blocked and delete the apology note.

#### `plan-backed-init-mode`

How plan-backed children initialize. Class: **mechanical**. Profiles: `work-on`. Settled by #557.

Statements:

- `skills/work-on/SKILL.md#L214-L215`: plan-backed mode uses free-form init. Excerpt: `**Plan-backed mode** uses free-form init.`
- `skills/work-on/SKILL.md#L169`: mode: plan_backed. Excerpt: `` Submit entry evidence: `{"mode": "plan_backed", ``
- `skills/work-on/koto-templates/work-on.md#L1524-L1526`: entry routes plan-backed to plan_context_injection. Excerpt: `**Plan-backed mode**: you have an issue from`

What runs:

- `skills/work-on/koto-templates/work-on.md#L91-L123`: free_form never reaches plan_context_injection. Excerpt: `vars.ISSUE_SOURCE: plan_outline`

Winner: `skills/work-on/koto-templates/work-on.md#L1524-L1526`. The template routes by mode; the free-form sentence is stale.

#### `deferral-pr-body-pointer`

Deferral in the PR body points at a file that says nothing about it. Class: **mechanical**. Profiles: `work-on`. Settled by #557.

Statements:

- `skills/work-on/koto-templates/work-on.md#L1942-L1943`: surface the approved deferral in the PR body, see phase-6-pr.md. Excerpt: `` then submit `approval_decision: approved`. ``
- `skills/work-on/references/phases/phase-6-pr.md#L31-L45`: PR body rules, no mention of deferrals. Excerpt: `## Create PR`

Winner: `skills/work-on/koto-templates/work-on.md#L1942-L1943`. The directive is the only statement of the rule; add one line to phase-6-pr.md or drop the pointer so it does not send the agent to nothing.

#### `decision-point-ids-unresolvable`

Decision-point ids and the file that defines them. Class: **mechanical**. Profiles: `work-on`, `scope`. Settled by #557.

Statements:

- `skills/work-on/SKILL.md#L427-L431`: names decision points W1 to W4. Excerpt: `` **Execution mode:** check `$ARGUMENTS` for ``
- `references/decision-protocol.md#L54-L57`: read references/decision-points.md, which does not exist. Excerpt: `### For known decision points`

Winner: `skills/work-on/SKILL.md#L427-L431`. Name the four points inline in SKILL.md and fix the decision-protocol path to the file that exists.

#### `retention-doc-runtime-status`

Whether the retention reference loads at runtime. Class: **mechanical**. Profiles: `work-on`. Settled by #557.

Statements:

- `references/koto-session-retention.md#L4-L8`: no skill loads this at runtime. Excerpt: `skills, and the koto behaviour it rests on.`
- `skills/work-on/SKILL.md#L365-L368`: links to it from the runtime SKILL.md. Excerpt: `reaches its parent on that tick. Why the`
- `references/koto-session-retention.md#L24-L26`: describes a work-on CORRECTION block no file writes. Excerpt: `run accumulated goes with it at once —`

Winner: `references/koto-session-retention.md#L4-L8`. SKILL.md already states the rule inline; drop the links and fix the stale sentence.

#### `pr-body-check-count`

How many PR-body checks exist. Class: **mechanical**. Profiles: `work-on`, `execute-single-pr`. Settled by #557.

Statements:

- `references/pr-body-conformance.md#L36`: four checks, PB1 to PB4. Excerpt: `These four checks are objective — a machine`
- `references/pr-body-conformance.md#L133`: PB1-PB3. Excerpt: `` `exempt_authors` input; the rule itself (PB1–PB3) ``
- `references/pr-body-conformance.md#L142`: PB1-PB3. Excerpt: `rule, adding no checks of its own — PB1–PB3`

Winner: `references/pr-body-conformance.md#L36`. Four checks are defined; the later lines were not updated.

#### `pr-body-rule-restated-inline`

The PR-body rule restated where it says not to be. Class: **mechanical**. Profiles: `work-on`, `execute-single-pr`. Settled by #557, #545.

Statements:

- `references/pr-body-conformance.md#L5-L7`: state the rule here, do not restate it inline. Excerpt: `` what `shirabe validate --pr-body` enforces ``
- `skills/execute/koto-templates/execute.md#L1391`: restates it. Excerpt: `The **mechanical** title/body rule is single-sourced`
- `skills/work-on/references/phases/phase-6-pr.md#L33-L37`: restates it. Excerpt: `The **mechanical** title/body rule is single-sourced`

Winner: `references/pr-body-conformance.md#L5-L7`. The reference owns the rule by its own statement; cut the restatements to pointers.

#### `worktree-discipline-vs-drift-state`

worktree-discipline.md versus the state that already did its work. Class: **mechanical**. Profiles: `execute-single-pr`. PRD R2 item 7. Settled by #545.

Statements:

- `skills/execute/koto-templates/execute.md#L1317`: fetch, rebase and fact-finding already happened; do not fetch or rebase. Excerpt: `` Upstream drift check, once per run. `origin/main` ``
- `skills/work-on/references/phases/phase-2.5-worktree-discipline.md#L40-L41`: the same. Excerpt: `You don't fetch, rebase, or write any file`
- `references/worktree-discipline.md#L46-L53`: run git fetch and git rebase yourself. Excerpt: `## Rebase phase`
- `references/worktree-discipline.md#L103-L128`: on intent-changing, go to the team lead, then prompt the author. Excerpt: `## Escalation phase`
- `references/worktree-discipline.md#L130-L161`: record worktree_rebases and worktree_divergences in the state file. Excerpt: `## Recording`
- `skills/execute/koto-templates/execute.md#L1326`: points the agent at worktree-discipline.md. Excerpt: `` `drift_facts.json` says why you're being ``

What runs:

- `skills/execute/koto-templates/execute.md#L497-L527`: intent-changing passes to done_blocked in one tick; no prompt, no state file. Excerpt: `impact: informational`

Winner: `skills/execute/koto-templates/execute.md#L1317`. The drift and sync default actions do the fetch and rebase; the directive and phase-2.5 already state the two-class rule. Drop both pointers to the reference, which has no /execute row in its own binding table.

#### `phase-6-pr-shared-with-execute`

/execute's ci_monitor loads /work-on's PR phase file. Class: **mechanical**. Profiles: `execute-single-pr`. Settled by #545.

Statements:

- `skills/execute/koto-templates/execute.md#L1456`: ci_monitor points at phase-6-pr.md. Excerpt: `` AUDE_PLUGIN_ROOT}/skills/work-on/references/phases/phase-6-pr.md` ``
- `skills/work-on/references/phases/phase-6-pr.md#L41-L45`: Fixes #N is mandatory. Excerpt: `` `Fixes #<N>` in Part 2 — `pr_creation`'s ``
- `skills/execute/koto-templates/execute.md#L1403`: omit Fixes #N for outline children. Excerpt: `- **Part 2 — reviewer context** (deleted`
- `skills/work-on/references/phases/phase-6-pr.md#L59-L73`: evidence lists are /work-on's. Excerpt: `## Evidence (pr_creation)`

Winner: `skills/execute/koto-templates/execute.md#L1403`. The execute directive carries its own rules; the pointer imports /work-on's evidence and body rules that do not apply. Drop the pointer once force-push-after-rebase and retry-caps are decided.

#### `execute-pr-title-type`

/execute's PR title type. Class: **mechanical**. Profiles: `execute-single-pr`. PRD R2 item 8. Settled by #545.

Statements:

- `skills/execute/koto-templates/execute.md#L1395`: choose feat, fix, docs or chore. Excerpt: `` - `<type>` defaults to **`feat`** (a PLAN ``
- `skills/execute/koto-templates/execute.md#L1436`: the command hardcodes feat. Excerpt: `&& gh pr edit "$PR_NUMBER" --title "feat:`

What runs:

- `skills/execute/scripts/node-push.sh#L394`: commit titles hardcode feat. Excerpt: `--title "feat($SLUG): $NODE" --body-file`

Winner: `skills/execute/koto-templates/execute.md#L1436`. The command is what runs and every run gets feat; delete the type choice. Parameterizing the type is proposed as a follow-up, not settled here.

#### `execute-state-file-projection`

/execute's state-file projection and resume ladder. Class: **mechanical**. Profiles: `execute-single-pr`, `execute-coordinated`. Settled by #545.

Statements:

- `skills/execute/SKILL.md#L761-L825`: maintain the execute_<topic>_state.md state file with pointer, snapshots and sentinel. Excerpt: `` `/execute` maintains a per-session state ``
- `skills/execute/SKILL.md#L877-L886`: 7-day stale prompt, else resume at phase_pointer. Excerpt: `` On re-entry, `/execute` follows the universal ``
- `skills/execute/SKILL.md#L851-L875`: koto init attaches or replaces; no separate session check. Excerpt: `**On a re-entry, single-pr or coordinated,`

Winner: `skills/execute/SKILL.md#L851-L875`. No script or template under skills/execute reads or writes that file (checked by search). The koto session is the state; the projection is never written and the stale prompt breaks --auto. Record once in the pattern state schema that a koto-backed parent's session is its state.

#### `execute-sentinel-no-reader`

/execute's parent_orchestration sentinel has no reader. Class: **mechanical**. Profiles: `execute-single-pr`, `execute-coordinated`. Settled by #545.

Statements:

- `skills/execute/SKILL.md#L814-L819`: write the sentinel before a Skill-tool dispatch; the child reads it. Excerpt: `` - **`parent_orchestration:`** — the pattern-level ``
- `skills/execute/SKILL.md#L101-L104`: the autonomy decision reaches children through the sentinel. Excerpt: `` authorized-autonomous mode as `--auto`. Per ``
- `skills/execute/koto-templates/execute.md#L1377`: koto materializes children from tasks. Excerpt: `koto materializes one child per task using`

What runs:

- `skills/plan/scripts/plan-to-tasks.sh#L744-L751`: children get only task variables. Excerpt: `$issue_source, ARTIFACT_PREFIX: $artifact_prefix,`

Winner: `skills/execute/koto-templates/execute.md#L1377`. No /work-on file reads the sentinel; delete the sentinel prose. Whether children should get an autonomy variable is a follow-up, on #659.

#### `execution-children-described-as-prs`

Execution children described as PRs. Class: **mechanical**. Profiles: `execute-single-pr`, `execute-coordinated`. Settled by #545.

Statements:

- `skills/execute/SKILL.md#L1181-L1185`: a child is a PR, inspected by PR state and CI rollup. Excerpt: `` - For a `/work-on` execution child (a PR, ``
- `skills/execute/SKILL.md#L937-L940`: a plan-backed child opens no PR. Excerpt: `re-entries below rather than re-running issues.`
- `skills/execute/koto-templates/execute-coordinated.md#L418`: no child opens a PR. Excerpt: `` - `dispatch:<node>` — the node's predecessors ``

What runs:

- `skills/execute/koto-templates/execute.md#L1379`: child status comes from the batch gate. Excerpt: `**Tick 2 — complete**: once all children`

Winner: `skills/execute/SKILL.md#L937-L940`. Children commit to the shared branch; status comes from batch_done.

#### `execute-exit-artifacts-not-produced`

Exit artifacts /execute says it writes. Class: **mechanical**. Profiles: `execute-single-pr`, `execute-coordinated`. Settled by #545.

Statements:

- `skills/execute/SKILL.md#L971-L975`: on re-evaluation, write a Decision Record. Excerpt: `` - **`re-evaluation`** — an **upstream-must-change ``
- `skills/execute/SKILL.md#L962-L970`: abandonment leaves an abandonment-marked draft PR. Excerpt: `` - **`abandonment-forced`** — a **forced stop** ``

What runs:

- `skills/execute/koto-templates/execute.md#L506-L527`: the run passes to done_blocked; no state asks for a document. Excerpt: `escalate_upstream_drift:`
- `skills/execute/scripts/print-exit.sh#L128-L138`: maps the step to the exit line; writes nothing. Excerpt: `merged) EXIT=full-run ;;`

Winner: `skills/execute/koto-templates/execute.md#L506-L527`. Nothing writes a Decision Record or marks a PR; failure_reason is the record. Delete both claims.

#### `no-cleanup-on-child-ticks`

--no-cleanup on child ticks. Class: **mechanical**. Profiles: `execute-single-pr`. Settled by #557, #545.

Statements:

- `skills/work-on/references/phases/phase-2.5-worktree-discipline.md#L122-L126`: other /work-on phase files must not carry --no-cleanup. Excerpt: `` This file sits under `/work-on` but is read ``
- `references/koto-session-retention.md#L40`: every tick, root or child. Excerpt: `` `--no-cleanup` means only "keep the session", ``
- `skills/execute/SKILL.md#L302-L308`: children carry it too. Excerpt: `` **The per-issue `/work-on` children carry ``

Winner: `references/koto-session-retention.md#L40`. The retention reference is the normative rule.

#### `deliver-merged-claim`

/deliver says it ends merged; a default run pauses first. Class: **mechanical**. Profiles: `deliver`. Settled by #541.

Statements:

- `skills/deliver/SKILL.md#L5-L6`: the run ends merged where protection allows. Excerpt: `` `--intent=continue` and then `/execute` on ``
- `skills/deliver/SKILL.md#L62`: with no flag and no header the run is interactive. Excerpt: `` | `--auto` / `--interactive` | The execution ``
- `skills/deliver/SKILL.md#L228`: paused-for-review is a listed outcome. Excerpt: `` | `paused-for-review` | Interactive only: ``

What runs:

- `skills/execute/scripts/execute-open.sh#L190-L201`: interactive runs set PAUSE_BEFORE_FINALIZE. Excerpt: `HEADER_MODE=$(sed -n 's/^## Execution Mode:[[:space:]]*\([A-`

Winner: `skills/deliver/SKILL.md#L228`. A default /deliver pauses before the merge; qualify the intro.

#### `scope-reference-table-vs-lazy-load`

/scope's reference table versus its lazy-load rule. Class: **mechanical**. Profiles: `scope`. PRD R2 item 9. Settled by #586.

Statements:

- `skills/scope/SKILL.md#L713-L730`: three references load in all phases. Excerpt: `## Reference Files`
- `skills/scope/SKILL.md#L434-L437`: references are not required reading up front. Excerpt: `Directives name the reference file for the`

What runs:

- `skills/scope/koto-templates/scope.md#L2177-L2179`: directives name the phase file per state, and state-schema.md at setup. Excerpt: `` Procedure: `skills/scope/references/phases/phase-0-setup.md`. ``

Winner: `skills/scope/SKILL.md#L434-L437`. The template names what to read per state; the table's all-phases rows are what make an agent read about 27,000 tokens of plugin references the load manifest gives weight 0.

#### `scope-state-initial-values`

/scope's initial state-file values. Class: **mechanical**. Profiles: `scope`. PRD R2 item 13. Settled by #586.

Statements:

- `skills/scope/references/phases/phase-0-setup.md#L420-L432`: write phase_pointer: phase-0 and exit: UNSET. Excerpt: `topic: <slug>`
- `skills/scope/references/state-schema.md#L48-L58`: the pointer is the template's integer phase. Excerpt: `` - **`phase_pointer`** — the pattern-level ``
- `references/parent-skill-state-schema.md#L26-L32`: UNSET while in progress (literal or absent unstated). Excerpt: `` - **`phase_pointer`** — parent-phase enum ``

What runs:

- `skills/scope/scripts/resume-probe.sh#L205-L210`: accepts only 0-4. Excerpt: `pointer=$(sfield phase_pointer)`
- `skills/scope/scripts/resume-probe.sh#L212-L232`: treats only empty, null or ~ as unset. Excerpt: `exitv=$(sfield exit)`

Winner: `skills/scope/scripts/resume-probe.sh#L205-L210`. A state file written as phase-0 says routes to resume_malformed. Phase 0 writes 0 and an empty exit; the pattern schema says empty or absent; test fixtures and the eval move to the probe's shape.

#### `fc10-already-caught`

Mechanical writing-style terms said to be caught before the jury. Class: **mechanical**. Profiles: `scope`, `work-on`. PRD R2 item 19. Settled by #541.

Statements:

- `skills/writing-style/SKILL.md#L41-L43`: mechanical rules are enforced before a reviewer sees the draft. Excerpt: `The mechanical rules are enforced before`
- `skills/brief/references/phases/phase-4-validate.md#L244-L253`: the terms are already caught before you see the draft. Excerpt: `8. **Writing style.** Check the prose against`

What runs:

- `skills/scope/scripts/hop-complete.sh#L132`: the hop gate checks SCHEMA, FC01, FC03, FC04 only. Excerpt: `validates_structure() { is_clean "$1" SCHEMA,FC01,FC03,FC04;`
- `crates/shirabe-validate/src/validate.rs#L90-L104`: FC10 is notice-level. Excerpt: `fn is_intrinsic_notice(code: &str) -> bool`

Winner: `crates/shirabe-validate/src/validate.rs#L90-L104`. Nothing runs FC10 before the jury. Delete both claims and give the term scan back to the reviewer, whose prompt already points at the rules file.

#### `r6-verdicts-no-reader`

Phase 1's shape predicates have no consumer. Class: **mechanical**. Profiles: `scope`. Settled by #586.

Statements:

- `skills/scope/references/phases/phase-1-discovery.md#L185-L197`: the verdicts' one consumer is /design's decision roster. Excerpt: `## R6 Shape-Predicate Walk`
- `skills/scope/references/phases/phase-1-discovery.md#L113-L131`: a post-/prd re-evaluation gate. Excerpt: `` ## Post-`/prd` Re-evaluation Gate ``
- `references/parent-skill-pattern.md#L341-L345`: a parent adds no arguments or env vars to a child. Excerpt: `The per-parent prohibition still holds —`

What runs:

- `skills/scope/references/phases/phase-2-chain-orchestration.md#L192`: /design gets only the PRD path. Excerpt: `` | `/prd` | `docs/briefs/BRIEF-<topic>.md` ``

Winner: `references/parent-skill-pattern.md#L341-L345`. /design cannot receive the verdicts and no state asks for the gate; drop the consumer claim and the walk.

#### `phase1-undocumented-state-field`

Phase 1 writes a state field the schema does not have. Class: **mechanical**. Profiles: `scope`. Settled by #586.

Statements:

- `skills/scope/references/phases/phase-1-discovery.md#L88-L94`: record phase-1: empty-cold-start. Excerpt: `When the cold-start discovery yields empty`
- `skills/scope/references/state-schema.md#L102-L107`: fields with no reader are wrong. Excerpt: `` (`skills/scope/references/phases/phase-resume.md`), ``

Winner: `skills/scope/references/state-schema.md#L102-L107`. Nothing reads the field; delete the write.

#### `brief-upstream-legal-parents`

What a BRIEF's upstream may name. Class: **mechanical**. Profiles: `scope`. Settled by #541.

Statements:

- `skills/brief/references/phases/phase-0-setup.md#L99-L103`: a BRIEF's upstream holds nothing; the validator rejects any value. Excerpt: `` A BRIEF's `upstream:` field holds nothing ``
- `skills/brief/references/brief-format.md#L32-L54`: optional STRATEGY or VISION ancestor. Excerpt: `motivating_context: |`

What runs:

- `crates/shirabe-validate/src/checks.rs#L4820-L4822`: a brief may name a STRATEGY or VISION. Excerpt: `fn legality_lets_a_brief_name_the_roadmaps_durable_ancestor(`

Winner: `skills/brief/references/brief-format.md#L32-L54`. The validator accepts the ancestor and SKILL.md's Context Resolution records it; the phase-0 paragraph is stale.

#### `prd-format-schema-field`

The PRD format omits the schema field the gate requires. Class: **mechanical**. Profiles: `scope`. Settled by #541.

Statements:

- `skills/prd/references/prd-format.md#L19-L31`: frontmatter example has no schema field. Excerpt: `status: Draft`
- `skills/prd/references/prd-format.md#L37`: required fields: status, problem, goals. Excerpt: `` Required fields: `status`, `problem`, `goals`. ``

What runs:

- `skills/scope/scripts/hop-complete.sh#L132`: the hop gate checks SCHEMA. Excerpt: `validates_structure() { is_clean "$1" SCHEMA,FC01,FC03,FC04;`

Winner: `skills/scope/scripts/hop-complete.sh#L132`. A PRD written from the format reference fails /scope's hop gate; add schema: prd/v1 to the example.

#### `prd-complexity-routing`

Where /prd routes a simple PRD. Class: **mechanical**. Profiles: `scope`. Settled by #541.

Statements:

- `skills/prd/SKILL.md#L195-L198`: two rows: a simple or medium PRD goes to /plan, a complex one to /design. Excerpt: `| Complexity | Suggestion |`
- `skills/prd/references/phases/phase-4-validate.md#L248-L253`: three tiers: simple suggests direct implementation, medium a planning workflow, complex a design workflow first. Excerpt: `- **Simple** (few requirements, clear scope,`

Winner: `skills/prd/references/phases/phase-4-validate.md#L248-L253`. Phase 4 is the step that presents the routing, and its three tiers match /explore's routing table, where a simple change files an issue and runs /work-on. SKILL.md's Output table becomes three rows: simple, file an issue then /work-on; medium, /plan; complex, /design. Found while re-checking the internal-restatement spans during execution, after the inventory closed.

#### `prd-upstream-roadmap`

Which documents a PRD may name as its upstream. Class: **mechanical**. Profiles: `scope`. Settled by #660.

Statements:

- `skills/prd/references/phases/phase-3-draft.md#L31-L35`: the --upstream path typically points to a ROADMAP when the PRD is part of a multi-feature initiative. Excerpt: `` **Detect upstream:** Check `$ARGUMENTS` for ``
- `skills/prd/references/prd-format.md#L37-L41`: a BRIEF is a PRD's only legal upstream; with no brief, the field is omitted rather than naming the ROADMAP. Excerpt: `` Required fields: `status`, `problem`, `goals`. ``

What runs:

- `crates/shirabe-validate/src/formats.rs#L322`: the PRD format's legal upstream types are BRIEF, STRATEGY and VISION. Excerpt: `legal_upstream: vec![FormatId::Brief, FormatId::Strategy,`
- `crates/shirabe-validate/src/validate.rs#L266-L270`: R10/R11 reject an upstream of an illegal type or one that does not outlive the document. Excerpt: `` // 2c. (R10/R11) The `upstream` field names ``

Winner: `crates/shirabe-validate/src/formats.rs#L322`. The validator decides: a PRD may name a BRIEF, a STRATEGY or a VISION, and R11 rejects a durable PRD naming a ROADMAP, which the cascade deletes once its features land. Both statements lose: Phase 3's ROADMAP default is wrong, and prd-format.md's BRIEF-only rule is narrower than the code. Both now say a BRIEF normally, a STRATEGY or VISION when no brief exists, and never a ROADMAP. Found during execution, after the inventory closed; an earlier reading named prd-format.md the winner before the validator's type list was checked.

#### `plan-single-pr-draft-commit`

/plan commits a single-pr PLAN at Draft. Class: **mechanical**. Profiles: `scope`. PRD R2 item 10. Settled by #658.

Statements:

- `skills/plan/SKILL.md#L545-L547`: a single-pr PLAN stays at Draft. Excerpt: `- **single-pr**: Phase 4 agents produce structured`
- `skills/plan/SKILL.md#L620-L621`: output is the PLAN with status Draft. Excerpt: `**single-pr mode:**`
- `skills/plan/references/quality/plan-doc-structure.md#L132-L135`: stays at Draft until /work-on starts. Excerpt: `In single-pr mode, Phase 4 agents produce`
- `skills/plan/SKILL.md#L68-L77`: a committed PLAN at Draft is a violation. Excerpt: `PLAN docs use a unified Draft -> Active ->`
- `skills/plan/references/phases/phase-7-creation.md#L327-L341`: the single-pr PLAN is authored Active. Excerpt: `PLANs whose activation creates no GitHub`

What runs:

- `crates/shirabe-validate/src/lifecycle.rs#L862-L874`: single-pr posture requires Active; L01 is an error. Excerpt: `` // Single-pr mid-PR. The PLAN is at `Active`: ``

Winner: `skills/plan/SKILL.md#L68-L77`. L01 fails a Draft single-pr PLAN and /plan's own 7.4b check stops on it.

#### `plan-complexity-values`

PLAN complexity values and the FC11 message. Class: **mechanical**. Profiles: `scope`. PRD R2 item 11. Settled by #658.

Statements:

- `skills/plan/references/plan-format.md#L176`: trivial, simple, testable, complex. Excerpt: `` | Complexity | One of `trivial`, `simple`, ``
- `skills/plan/SKILL.md#L263`: simple, testable, critical. Excerpt: `Each issue gets a complexity (simple, testable,`
- `references/issues-table.md#L103`: simple, testable, critical. Excerpt: `` `simple`, `testable`, or `critical`. ``

What runs:

- `crates/shirabe-validate/src/checks.rs#L1072-L1085`: FC05 rejects anything but simple, testable, critical. Excerpt: `if let Some(complexity) = cells.get(2) {`
- `crates/shirabe-validate/src/checks.rs#L3468`: FC11's message sends the agent to plan-format.md. Excerpt: `"[FC11] '## Implementation Issues' section`

Winner: `crates/shirabe-validate/src/checks.rs#L1072-L1085`. An agent following FC11's pointer writes values FC05 rejects. Fix plan-format and point FC11 at references/issues-table.md.

#### `plan-required-sections`

PLAN required sections. Class: **mechanical**. Profiles: `scope`. PRD R2 item 12. Settled by #658.

Statements:

- `skills/plan/references/plan-format.md#L134-L157`: six sections, no Issue Outlines. Excerpt: `## Required Sections`
- `skills/plan/SKILL.md#L54-L62`: seven sections. Excerpt: `Quick summary of required sections:`
- `skills/plan/references/quality/plan-doc-structure.md#L112-L122`: seven sections. Excerpt: `## Required Sections`
- `skills/plan/references/phases/phase-7-creation.md#L363-L375`: single-pr requires a Dependency Graph. Excerpt: `` ip/plan_<topic>_decomposition.md` (walki ``

What runs:

- `crates/shirabe-validate/src/formats.rs#L218-L248`: per-mode map; single-pr needs five sections. Excerpt: `` /// Build the Plan profile's per-`execution_mode` ``
- `crates/shirabe-validate/src/checks.rs#L3854-L3864`: FC14 flags a single-pr Dependency Graph. Excerpt: `// The Dependency Graph exclusion is single-pr's`

Winner: `crates/shirabe-validate/src/formats.rs#L218-L248`. The validator's per-mode map and FC14 are what run; SKILL.md points at one per-shape list and phase 7 drops the graph for single-pr.

#### `design-spawned-from-shape`

/design's spawned_from shape. Class: **mechanical**. Profiles: `scope`. PRD R2 item 14. Settled by #637.

Statements:

- `skills/design/SKILL.md#L71-L77`: an object: issue, repo, parent_design. Excerpt: `` - `spawned_from` -- for child designs created ``
- `skills/design/references/design-format.md#L65-L68`: a path string to a parent DESIGN. Excerpt: `- **spawned_from** -- path to a parent DESIGN`

What runs:

- `skills/design/references/phases/phase-6-final-review.md#L239-L250`: the workflow reads it as issue-driven. Excerpt: `3. **Remove blocking label from source issue.**`

Winner: `skills/design/SKILL.md#L71-L77`. The issue-driven workflow uses the object; the main agent and the Phase 6 reviewer otherwise check different shapes in one run.

#### `design-superseded-location`

Where superseded designs go. Class: **mechanical**. Profiles: `scope`. PRD R2 item 15. Settled by #637.

Statements:

- `skills/design/SKILL.md#L131`: archive/. Excerpt: `` - Archived: `docs/designs/archive/DESIGN-<topic>.md` ``
- `skills/design/references/design-format.md#L227`: stays where it is. Excerpt: `| any -> Superseded | A successor DESIGN`

What runs:

- `crates/shirabe-validate/src/transition.rs#L453`: moves the file to docs/designs/archive. Excerpt: `("Superseded".to_string(), "docs/designs/archive".to_string(`

Winner: `crates/shirabe-validate/src/transition.rs#L453`. The transition moves the file.

#### `design-implementation-issues-owner`

Who adds Implementation Issues to a DESIGN. Class: **mechanical**. Profiles: `scope`. PRD R2 item 16. Settled by #637, #658.

Statements:

- `skills/design/SKILL.md#L133-L136`: /plan adds an Implementation Issues section. Excerpt: `### Sections Added During Lifecycle`
- `skills/design/SKILL.md#L240-L241`: do not merge; /plan will add that section. Excerpt: `` **"Plan":** suggest running `/plan <design-doc-path>` ``
- `skills/design/references/lifecycle.md#L56-L58`: added during /plan phase 6. Excerpt: `### During /plan phase-6 (after creating`
- `skills/plan/references/phases/phase-7-creation.md#L615-L619`: do not insert an Implementation Issues section. Excerpt: `**Important constraints** (implementation`
- `skills/design/references/design-format.md#L146-L159`: a DESIGN never carries that table. Excerpt: `## Implementation Issues Ownership`

Winner: `skills/plan/references/phases/phase-7-creation.md#L615-L619`. Phase 7 is what runs and nothing adds the section.

#### `design-planned-transition-uncommitted`

The DESIGN's Planned transition is never committed under /scope. Class: **mechanical**. Profiles: `scope`. Settled by #586, #658.

Statements:

- `skills/plan/references/phases/phase-1-analysis.md#L51-L58`: under the sentinel, transition the DESIGN to Planned. Excerpt: `` When the sentinel is present AND its `invoking_child:` ``
- `skills/plan/references/phases/phase-7-creation.md#L609-L613`: step 7.5 transitions it again. Excerpt: `Transition the upstream design doc from Accepted`
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L579-L593`: the plan hop stages only the PLAN path. Excerpt: `**One pathspec, and it is this hop's own`

What runs:

- `crates/shirabe-validate/src/lifecycle.rs#L862-L874`: an Active PLAN over an Accepted DESIGN fails L01. Excerpt: `` // Single-pr mid-PR. The PLAN is at `Active`: ``

Winner: `skills/scope/SKILL.md#L655-L664`. Both DESIGN paths are already in /scope's commit set; add the DESIGN path to the plan hop's commit, and keep 7.5 as the single statement of the transition.

### Dead prose

A span is dead prose when the agent would lose nothing by not reading it:
it contains no instruction, condition or value the agent uses at any state,
or it repeats an instruction the same profile already loads from a named
surviving copy. No span overlaps a statement of a policy item or the winner
of a mechanical item, and no dropped pointer unloads a file holding a policy
item's statement, unless the entry is marked blocked on that policy item; the
renderer that produced this list refuses one that does. None of the spans below is the only statement of a rule in
force; where a span restates a rule, its surviving statement is named.
Spans that a mechanical item already removes are counted here once, so the
totals are not added to anything in the contradictions list.

A re-check during execution found ten rules inside
`dp-<skill>-internal-restatements` spans that no other text states: six in
`dp-brief-internal-restatements`, two in `dp-prd-internal-restatements`, one in
`dp-plan-internal-restatements` and one in
`dp-review-plan-internal-restatements`. The lines carrying them were taken
out of those entries, by narrowing or splitting a span or by dropping it when
the rule was all of it, so they stay. One of the two `/prd` rules, which
routes a simple PRD to `/plan`, disagrees with the routing text in its Phase
4 file rather than repeating it. The same re-check raised four more rules
that turned out to be stated elsewhere in other words, and those spans are
unchanged.

#### Design rationale shipped as a prompt

##### `dp-work-on-pointer-loaded-docs`

Profiles: `work-on`. Size: 24710 bytes (about 6177 tokens). Settled by #557. Only statement of a rule in force: no.

Two authoring documents reached through one pointer each. Removing the pointer removes the load; the files stay for maintainers. Each rule they state is also stated in the directive or gate that enforces it.

- pointer `skills/work-on/koto-templates/work-on.md#L2031` (excerpt `` `gh pr create` stays with you, permanently: ``) loads the whole of `references/default-action-conversion.md`, 15746 bytes
- pointer `skills/work-on/SKILL.md#L365-L368` (excerpt `reaches its parent on that tick. Why the`) loads the whole of `references/koto-session-retention.md`, 8964 bytes

##### `dp-work-on-finishing-obligations-pointer`

Profiles: `work-on`. Size: 6352 bytes (about 1588 tokens). Settled by #557. Only statement of a rule in force: no.

Blocked on: `force-push-after-rebase`, `ci-fix-ends-run-unverified`.

An authoring document reached through one pointer. It states the /work-on side of two policy items, so removing the pointer waits on both decisions; the file stays for maintainers.

- pointer `skills/work-on/koto-templates/work-on.md#L2003-L2006` (excerpt `` `references/finishing-obligations.md` is ``) loads the whole of `skills/work-on/references/finishing-obligations.md`, 6352 bytes

##### `dp-work-on-rationale`

Profiles: `work-on`. Size: 6412 bytes (about 1603 tokens). Settled by #557. Only statement of a rule in force: no.

- `skills/work-on/SKILL.md#L96-L103`, 585 bytes, excerpt `` After verification passes, the `finalization` ``
- `skills/work-on/SKILL.md#L91-L92`, 147 bytes, excerpt `The gate carries no project-specific commands.`
- `skills/work-on/references/phases/phase-4-implementation.md#L36-L48`, 772 bytes, excerpt `On that last point, because it is the one`
- `skills/work-on/references/phases/phase-4-implementation.md#L108-L109`, 132 bytes, excerpt `This step is cheap (usually < 2 minutes)`
- `references/pr-body-conformance.md#L11-L20`, 584 bytes, excerpt `## Why a single source`
- `references/pr-body-conformance.md#L96-L143`, 2780 bytes, excerpt `PB4 moves one narrow, objective slice from`
- `skills/work-on/koto-templates/work-on.md#L2078-L2082`, 355 bytes, excerpt `Ask the finder for the path rather than searching`
- `skills/work-on/koto-templates/work-on.md#L2096-L2100`, 319 bytes, excerpt `The two are different kinds of thing and`
- `skills/work-on/references/koto-context-conventions.md#L1-L7`, 306 bytes, excerpt `# Koto Context Ingestion Conventions`
- `skills/work-on/koto-templates/work-on.md#L2133-L2138`, 432 bytes, excerpt `The workflow reached a blocking condition`

##### `dp-execute-skill-rationale`

Profiles: `execute-single-pr`, `execute-coordinated`. Size: 17414 bytes (about 4353 tokens). Settled by #545. Only statement of a rule in force: no.

L1052-L1137 is a maintainer procedure that docs/guides/execute-friction.md already covers.

- `skills/execute/SKILL.md#L24-L41`, 1320 bytes, excerpt `` `/execute` is the third parent skill in the ``
- `skills/execute/SKILL.md#L80-L89`, 734 bytes, excerpt `` The `single-pr` path makes no such call: ``
- `skills/execute/SKILL.md#L189-L195`, 423 bytes, excerpt `## Single-PR Execution Path`
- `skills/execute/SKILL.md#L255-L276`, 1470 bytes, excerpt `` `PLUGIN_ROOT` is passed for the same reason ``
- `skills/execute/SKILL.md#L292-L300`, 611 bytes, excerpt `` **Including the two ticks in `spawn_and_await`, ``
- `skills/execute/SKILL.md#L838-L847`, 692 bytes, excerpt `This is a *pointer to developer behavior*,`
- `skills/execute/SKILL.md#L1052-L1137`, 5723 bytes, excerpt `## Finalization-Not-Done Guard (R5)`
- `skills/execute/SKILL.md#L1278-L1288`, 686 bytes, excerpt `` Two `/execute`-specific surfaces are also ``
- `skills/execute/SKILL.md#L1290-L1338`, 5755 bytes, excerpt `## Team Shape`

##### `dp-execute-template`

Profiles: `execute-single-pr`. Size: 7992 bytes (about 1998 tokens). Settled by #545. Only statement of a rule in force: no.

Rationale and descriptions of what a script or gate does, inside directives; the instruction sentences around them stay.

- `skills/execute/koto-templates/execute.md#L1183`, 691 bytes, excerpt `` Every PR lookup goes through `adopt-or-create-pr.sh`, ``
- `skills/execute/koto-templates/execute.md#L1229`, 368 bytes, excerpt `` `gh pr create` stays here rather than moving ``
- `skills/execute/koto-templates/execute.md#L1256-L1261`, 458 bytes, excerpt `That name is written without braces here`
- `skills/execute/koto-templates/execute.md#L1269`, 393 bytes, excerpt `The default-branch refusal is the interesting`
- `skills/execute/koto-templates/execute.md#L1285`, 323 bytes, excerpt `This runs before the rebase because the rebase`
- `skills/execute/koto-templates/execute.md#L1303-L1305`, 715 bytes, excerpt `` The command is `git rebase origin/main`, ``
- `skills/execute/koto-templates/execute.md#L1359-L1370`, 762 bytes, excerpt `# The settled branch arrives as a capture`
- `skills/execute/koto-templates/execute.md#L1450`, 275 bytes, excerpt `` On a resume of a paused run, `/execute` re-enters ``
- `skills/execute/koto-templates/execute.md#L1479`, 560 bytes, excerpt `` **DIRTY-handling (#162).** If `gh pr view ``
- `skills/execute/koto-templates/execute.md#L1491`, 737 bytes, excerpt `The state runs two steps. The cascade script`
- `skills/execute/koto-templates/execute.md#L1500`, 401 bytes, excerpt `` `--session` makes the cascade's push record ``
- `skills/execute/koto-templates/execute.md#L1520-L1522`, 681 bytes, excerpt `Match the two good verdicts rather than testing`
- `skills/execute/koto-templates/execute.md#L1556`, 466 bytes, excerpt `` The three cascade values route to `ci_monitor` ``
- `skills/execute/koto-templates/execute.md#L1589`, 474 bytes, excerpt `` `merge_route` routes on the recorded verdict ``
- `skills/execute/koto-templates/execute.md#L1612`, 371 bytes, excerpt `This state is presented only when this invocation's`
- `skills/execute/koto-templates/execute.md#L1660`, 317 bytes, excerpt `` At the `/execute` SKILL layer this terminal ``

##### `dp-scope-history`

Profiles: `scope`. Size: 7140 bytes (about 1785 tokens). Settled by #586. Only statement of a rule in force: no.

Prose that narrates an earlier revision of the skill.

- `skills/scope/references/phases/phase-1-discovery.md#L18-L26`, 544 bytes, excerpt `That is the point of this phase's shape.`
- `skills/scope/references/phases/phase-1-discovery.md#L132-L138`, 436 bytes, excerpt `The gate records nothing in the state file.`
- `skills/scope/references/phases/phase-1-discovery.md#L170-L183`, 748 bytes, excerpt `**This is not a worth-producing judgment.**`
- `skills/scope/references/phases/phase-1-discovery.md#L193-L197`, 308 bytes, excerpt `The predicates do **not** decide whether`
- `skills/scope/references/phases/phase-1-discovery.md#L303-L331`, 1386 bytes, excerpt `## What Phase 1 Does Not Decide About the`
- `skills/scope/references/phases/phase-1-discovery.md#L486-L489`, 235 bytes, excerpt `That list is a constant, and now literally`
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L57-L58`, 118 bytes, excerpt `forms below. The summary form omitted it`
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L287-L293`, 312 bytes, excerpt `Invoking every child in its cold-start mode`
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L844-L847`, 231 bytes, excerpt `` `stage:` names where the verdict settled ``
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L926-L931`, 364 bytes, excerpt `The scope sentence is stated this way deliberately.`
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L968-L982`, 974 bytes, excerpt `` **`chain_ran:` is the reason the previous ``
- `skills/scope/references/state-schema.md#L188-L201`, 789 bytes, excerpt `` `stage:` names where the verdict settled: ``
- `skills/scope/references/phases/phase-3-exit-finalization.md#L403-L406`, 239 bytes, excerpt `is a restatement for readers working in this`
- `skills/scope/koto-templates/scope.md#L2198-L2203`, 456 bytes, excerpt `**The branch check ran before this state.**`

##### `dp-brief-history`

Profiles: `scope`. Size: 2632 bytes (about 658 tokens). Settled by #541. Only statement of a rule in force: no.

Prose that narrates an earlier revision of the skill.

- `skills/brief/SKILL.md#L273-L279`, 410 bytes, excerpt `- **Always produces a brief:** there is no`
- `skills/brief/references/phases/phase-0-setup.md#L20-L21`, 158 bytes, excerpt `` - Record the artifact decision as `produce`. ``
- `skills/brief/references/phases/phase-0-setup.md#L162-L167`, 415 bytes, excerpt `**This check carries more weight than it`
- `skills/brief/references/phases/phase-0-setup.md#L299-L319`, 1358 bytes, excerpt `**What changed and why.** An earlier revision`
- `skills/writing-style/SKILL.md#L29-L32`, 291 bytes, excerpt `This file does not restate that list. It`

##### `dp-plan-history`

Profiles: `scope`. Size: 422 bytes (about 105 tokens). Settled by #658. Only statement of a rule in force: no.

Prose that narrates an earlier revision of the skill.

- `skills/plan/references/phases/phase-7-creation.md#L557-L562`, 422 bytes, excerpt `A single earlier bash pre-flight used to`

##### `dp-scope-rationale`

Profiles: `scope`. Size: 14507 bytes (about 3626 tokens). Settled by #586. Only statement of a rule in force: no.

- `skills/scope/SKILL.md#L26-L52`, 1608 bytes, excerpt `` `/scope` is the second parent skill in the ``
- `skills/scope/SKILL.md#L61-L80`, 1299 bytes, excerpt `Two properties are what the workflow buys,`
- `skills/scope/SKILL.md#L82-L117`, 1784 bytes, excerpt `## Why Each Hop Is Taken`
- `skills/scope/references/phases/phase-0-setup.md#L334-L355`, 1302 bytes, excerpt `A private roadmap dropped here is dropped`
- `skills/scope/references/phases/phase-1-discovery.md#L38-L49`, 624 bytes, excerpt `**An author who wants a shorter conversation`
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L17-L22`, 341 bytes, excerpt `Two things make this phase different from`
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L221-L230`, 557 bytes, excerpt `` differently, and the run routes to `bail` ``
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L232-L262`, 1876 bytes, excerpt `**The roadmap travels to two children, for`
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L263-L278`, 884 bytes, excerpt `**Why the slug and the upstream travel separately.**`
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L615-L630`, 876 bytes, excerpt `Step 8 is where the artifact set shrinks.`
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L644-L660`, 975 bytes, excerpt `This is **stricter than "this run produced`
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L678-L682`, 317 bytes, excerpt `The restriction is repeated at the head of`
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L711-L720`, 629 bytes, excerpt `**What this buys, stated because the guard's`
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L754-L758`, 304 bytes, excerpt `Sourcing from the survivor is what makes`
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L880-L888`, 459 bytes, excerpt `### Manual-fallback boundary`
- `skills/scope/koto-templates/scope.md#L2272-L2277`, 426 bytes, excerpt `The ordering above is in the directive, and`
- `references/fixes/sub-agent-dispatch.md#L8-L11`, 246 bytes, excerpt `This file is dereferenced on-demand by each`

##### `dp-plan-rationale`

Profiles: `scope`. Size: 4141 bytes (about 1035 tokens). Settled by #658. Only statement of a rule in force: no.

- `skills/plan/SKILL.md#L86-L116`, 1656 bytes, excerpt `PLANs are ephemeral: when the work completes,`
- `skills/plan/references/phases/phase-7-creation.md#L249-L256`, 576 bytes, excerpt `A plan whose strategy section only points`
- `skills/plan/references/phases/phase-7-creation.md#L538-L543`, 427 bytes, excerpt `` `shirabe validate` is the reader here rather ``
- `skills/plan/references/phases/phase-7-creation.md#L596-L603`, 551 bytes, excerpt `**Worked example (the failure mode this step`
- `skills/plan/references/phases/phase-1-analysis.md#L72-L81`, 612 bytes, excerpt `This is the symmetric three-skill contract:`
- `skills/plan/references/quality/plan-doc-structure.md#L374-L380`, 319 bytes, excerpt `## Section Placement (Legacy Context)`

##### `dp-design-rationale`

Profiles: `scope`. Size: 597 bytes (about 149 tokens). Settled by #637. Only statement of a rule in force: no.

- `skills/design/SKILL.md#L39`, 316 bytes, excerpt `DESIGN is durable because the architectural`
- `skills/design/references/phases/phase-0-setup-prd.md#L54-L58`, 281 bytes, excerpt `then proceed past the hard-stop check. The`

#### Duplicated blocks

##### `dp-work-on-retry-rationale-copies`

Profiles: `work-on`. Size: 8378 bytes (about 2094 tokens). Settled by #557. Surviving statement: `skills/work-on/references/phases/phase-4a-scrutiny.md#L69-L73`.

Copies of the retry-clearing rationale and the orchestration restatement; 4a's copy is the one the verification directive already names.

- `skills/work-on/references/phases/phase-3-analysis.md#L96-L100`, 1211 bytes, excerpt `The block stops if **either** signal fires`
- `skills/work-on/references/phases/phase-4-implementation.md#L168-L172`, 1211 bytes, excerpt `The block stops if **either** signal fires`
- `skills/work-on/references/phases/phase-4b-review.md#L65-L69`, 1211 bytes, excerpt `The block stops if **either** signal fires`
- `skills/work-on/references/phases/phase-4c-qa.md#L64-L68`, 1211 bytes, excerpt `The block stops if **either** signal fires`
- `skills/work-on/references/phases/phase-5-finalization.md#L170-L174`, 1211 bytes, excerpt `The block stops if **either** signal fires`
- `skills/work-on/references/review-panel-orchestration.md#L20-L37`, 1237 bytes, excerpt `## A retry invalidates every verdict, and`
- `skills/work-on/references/phases/phase-5-finalization.md#L162-L168`, 1086 bytes, excerpt `` Two states gate on `summary.md`, and both ``

##### `dp-work-on-duplicates`

Profiles: `work-on`. Size: 4472 bytes (about 1118 tokens). Settled by #557. Only statement of a rule in force: no.

- `skills/work-on/SKILL.md#L180-L185`, 1078 bytes, excerpt `**Issue type classification**: the orchestrator`; survivor the issue_type_routing directive
- `skills/work-on/references/phases/phase-3-analysis.md#L51-L60`, 621 bytes, excerpt `## Already-Complete Detection`; survivor the analysis directive
- `skills/work-on/references/phases/phase-3-analysis.md#L62-L72`, 560 bytes, excerpt `## Issue Type Is Not Asked Here`; survivor the analysis directive
- `skills/work-on/references/agent-instructions/phase-3-analysis.md#L195-L199`, 347 bytes, excerpt `` Don't classify the issue as `code`, `docs`, ``; survivor the analysis directive
- `skills/work-on/SKILL.md#L308-L316`, 741 bytes, excerpt `### Branch Setup`; survivor `skills/work-on/references/phases/phase-1-setup.md#L14-L19`
- `skills/work-on/SKILL.md#L453-L457`, 339 bytes, excerpt `2. On a resumed workflow, apply the **Resume**`; survivor the Resume section of the same file
- `skills/work-on/references/agent-instructions/phase-3-analysis.md#L201-L210`, 380 bytes, excerpt `The plan is complete when:`; survivor Task 6 of the same file
- `skills/work-on/SKILL.md#L115-L119`, 406 bytes, excerpt `A finalization-checklist item disallows unapproved`; survivor `skills/work-on/references/phases/phase-5-finalization.md#L176-L180`

##### `dp-execute-skill-duplicates-template`

Profiles: `execute-single-pr`, `execute-coordinated`. Size: 31033 bytes (about 7758 tokens). Settled by #545. Surviving statement: the matching state directives in execute.md and execute-coordinated.md: takeover at execute.md#L1222-L1227, autonomy at execute.md#L1341-L1352, exit lines at the terminal directives, expected_head at execute.md#L1469.

Per-state mechanics, pause, merge, owned-PR takeover, coordinated states, outcome table and autonomy block, each also stated in the state that runs it.

- `skills/execute/SKILL.md#L310-L394`, 6157 bytes, excerpt `In autonomous mode, drive this loop continuously`
- `skills/execute/SKILL.md#L396-L427`, 2067 bytes, excerpt `#### Mode-driven pause before finalization`
- `skills/execute/SKILL.md#L429-L467`, 2537 bytes, excerpt `#### Merging`
- `skills/execute/SKILL.md#L469-L566`, 6400 bytes, excerpt `#### Owned-PR lookup`
- `skills/execute/SKILL.md#L630-L722`, 6478 bytes, excerpt `### Step 3 — Drive the envelope`
- `skills/execute/SKILL.md#L983-L1050`, 5332 bytes, excerpt `### Outcome versus exit, and the exit lines`
- `skills/execute/SKILL.md#L1139-L1172`, 2062 bytes, excerpt `` `/execute` honors an explicit autonomy mode — ``

##### `dp-scope-duplicates`

Profiles: `scope`. Size: 14772 bytes (about 3693 tokens). Settled by #586. Only statement of a rule in force: no.

- `skills/scope/references/phases/phase-3-exit-finalization.md#L397-L510`, 5374 bytes, excerpt `## Closed Write-Target Set`; survivor `skills/scope/SKILL.md#L606-L711`
- `skills/scope/references/phases/phase-4-cleanup.md#L88-L163`, 3885 bytes, excerpt `## Read-Back of Phase 3's Closed Write-Target`; survivor `skills/scope/SKILL.md#L606-L711`
- `skills/scope/references/phases/phase-3-exit-finalization.md#L511-L541`, 1351 bytes, excerpt `## State-File Enum Re-Validation Before Path`; survivor `skills/scope/references/phases/phase-2-chain-orchestration.md#L915-L986`
- `skills/scope/SKILL.md#L548-L573`, 1475 bytes, excerpt `## Consolidation Judgment`; survivor `skills/scope/references/phases/phase-2-chain-orchestration.md#L613-L848`
- `skills/scope/koto-templates/scope.md#L2208-L2213`, 396 bytes, excerpt `Ignore koto's discovery warnings about sessions`; survivor `skills/scope/SKILL.md#L442-L444`
- `skills/scope/SKILL.md#L333-L352`, 1094 bytes, excerpt `## Topic-Slug Constraint`; survivor `skills/scope/references/phases/phase-0-setup.md#L187-L212`
- `skills/scope/SKILL.md#L275-L295`, 1197 bytes, excerpt `## Upstream Flag`; survivor `skills/scope/references/phases/phase-0-setup.md#L256-L355`

##### `dp-plan-duplicates`

Profiles: `scope`. Size: 2793 bytes (about 698 tokens). Settled by #658. Only statement of a rule in force: no.

- `skills/plan/SKILL.md#L492-L496`, 306 bytes, excerpt `Phase 0 detection: if the parent-chain sentinel`; survivor `skills/plan/SKILL.md#L480-L481`
- `skills/plan/SKILL.md#L503-L508`, 378 bytes, excerpt `For roadmap input, populating the roadmap's`; survivor `skills/plan/references/phases/phase-7-creation.md#L35-L44`
- `skills/plan/SKILL.md#L611-L618`, 482 bytes, excerpt `**multi-pr mode (roadmap input):**`; survivor `skills/plan/references/phases/phase-7-creation.md#L35-L44`
- `skills/plan/references/phases/phase-7-creation.md#L7-L22`, 1021 bytes, excerpt `When the input is a roadmap, **do not** re-drive`; survivor `skills/plan/references/phases/phase-7-creation.md#L35-L44`
- `skills/plan/references/phases/phase-7-creation.md#L207-L208`, 127 bytes, excerpt `Write the PLAN artifact. (This phase no longer`; survivor `skills/plan/references/phases/phase-7-creation.md#L35-L44`
- `skills/plan/references/phases/phase-7-creation.md#L350-L361`, 479 bytes, excerpt `above: upstream: <design-doc-path>`; survivor `skills/plan/references/phases/phase-7-creation.md#L230-L241`

##### `dp-design-duplicates`

Profiles: `scope`. Size: 507 bytes (about 126 tokens). Settled by #637. Only statement of a rule in force: no.

- `skills/design/SKILL.md#L200-L204`, 306 bytes, excerpt `Phase 0 detection: if the parent-chain sentinel`; survivor `skills/design/SKILL.md#L187-L188`
- `skills/design/references/phases/phase-0-setup-prd.md#L40-L42`, 201 bytes, excerpt `glob keeps the branch forward-compatible`; survivor `skills/plan/references/phases/phase-1-analysis.md#L46-L48`

##### `dp-brief-internal-restatements`

Profiles: `scope`. Size: 20878 bytes (about 5219 tokens). Settled by #541. Only statement of a rule in force: no.

Text in /brief's own files that restates another of its own files, so it is redundant even when /brief runs standalone.

- `skills/brief/SKILL.md#L47-L49`, 314 bytes, excerpt `` **Lifecycle:** Durable. Stays in `docs/briefs/` ``; survivor `skills/brief/references/brief-format.md#L246-L256`
- `skills/brief/SKILL.md#L60-L63`, 246 bytes, excerpt `` BRIEF documents live at `docs/briefs/BRIEF-<topic>.md` ``; survivor `skills/brief/references/brief-format.md#L246-L256`
- `skills/brief/SKILL.md#L67-L73`, 368 bytes, excerpt `Before writing content, detect visibility`; survivor `skills/brief/references/phases/phase-0-setup.md#L274-L282`
- `skills/brief/SKILL.md#L75-L84`, 654 bytes, excerpt `BRIEF has no visibility-gated section — there`; survivor `skills/brief/references/phases/phase-0-setup.md#L284-L288`
- `skills/brief/SKILL.md#L120-L132`, 754 bytes, excerpt `A ROADMAP is the only document Input Mode`; survivor `skills/brief/references/phases/phase-0-setup.md#L174-L189`
- `skills/brief/SKILL.md#L144-L153`, 679 bytes, excerpt `**Both routes read the roadmap; neither records`; survivor `skills/brief/references/phases/phase-0-setup.md#L221-L272`
- `skills/brief/SKILL.md#L155-L162`, 529 bytes, excerpt `The flag is parsed before the positional`; survivor `skills/brief/references/phases/phase-0-setup.md#L57-L75`
- `skills/brief/SKILL.md#L166-L171`, 382 bytes, excerpt `` **Topic slug constraint.** The `<topic>` ``; survivor `skills/brief/references/phases/phase-0-setup.md#L113-L139`
- `skills/brief/SKILL.md#L173-L188`, 1128 bytes, excerpt `**Ground on the roadmap, record its ancestor.**`; survivor `skills/brief/references/phases/phase-0-setup.md#L221-L272`
- `skills/brief/SKILL.md#L190-L194`, 311 bytes, excerpt `**Path canonicalization.** Any user-supplied`; survivor `skills/brief/references/phases/phase-0-setup.md#L141-L160`
- `skills/brief/SKILL.md#L196-L199`, 223 bytes, excerpt `**Visibility detection.** Detect Public/Private`; survivor `skills/brief/references/phases/phase-0-setup.md#L274-L282`
- `skills/brief/SKILL.md#L201-L202`, 110 bytes, excerpt `` BRIEF has no scope (`project`/`org`) dimension. ``; survivor `skills/brief/references/phases/phase-0-setup.md#L29-L31`
- `skills/brief/SKILL.md#L208-L224`, 1312 bytes, excerpt `Phase 0: SETUP --> Phase 1: DISCOVER -->`; survivor `skills/brief/SKILL.md#L296-L314`
- `skills/brief/SKILL.md#L226-L239`, 746 bytes, excerpt `Phase 4 jury runs two reviewers in parallel:`; survivor `skills/brief/references/phases/phase-4-validate.md#L100-L110`
- `skills/brief/SKILL.md#L264-L272`, 511 bytes, excerpt `- **Topic-slug constraint:** Phase 0 rejects`; survivor `skills/brief/references/phases/phase-0-setup.md#L113-L160`
- `skills/brief/SKILL.md#L280-L284`, 326 bytes, excerpt `- **Conversational scoping:** Phase 1 is`; survivor `skills/brief/references/phases/phase-4-validate.md#L47-L51`
- `skills/brief/SKILL.md#L288-L292`, 313 bytes, excerpt `` - **Status convention:** the body `## Status` ``; survivor `skills/brief/references/brief-format.md#L73-L92`
- `skills/brief/SKILL.md#L322-L329`, 486 bytes, excerpt `After acceptance, suggest next steps:`; survivor `skills/brief/references/phases/phase-5-finalize.md#L194-L206`
- `skills/brief/SKILL.md#L342-L352`, 466 bytes, excerpt `## Reference Files`; survivor `skills/brief/SKILL.md#L296-L314`
- `skills/brief/references/phases/phase-1-discover.md#L61-L66`, 281 bytes, excerpt `### No Upstream-PRD Mode`; survivor `skills/brief/references/phases/phase-0-setup.md#L174-L189`
- `skills/brief/references/phases/phase-2-draft.md#L82-L85`, 261 bytes, excerpt `` The `problem` and `outcome` fields are paragraph-length ``; survivor `skills/brief/references/brief-format.md#L67-L71`
- `skills/brief/references/phases/phase-2-draft.md#L87-L96`, 696 bytes, excerpt `` **`upstream:` holds what Phase 0 step 0.3a ``; survivor `skills/brief/references/phases/phase-0-setup.md#L234-L256`
- `skills/brief/references/phases/phase-2-draft.md#L118-L121`, 308 bytes, excerpt `The bare status word goes alone on its own`; survivor `skills/brief/references/brief-format.md#L73-L92`
- `skills/brief/references/phases/phase-2-draft.md#L128-L134`, 339 bytes, excerpt `- Names something a user struggles with,`; survivor `skills/brief/references/brief-format.md#L403-L415`
- `skills/brief/references/phases/phase-2-draft.md#L138-L145`, 415 bytes, excerpt `- A solution wearing a problem's clothes.`; survivor `skills/brief/references/brief-format.md#L403-L415`
- `skills/brief/references/phases/phase-2-draft.md#L158-L160`, 171 bytes, excerpt `- Describes the user's experience: what they`; survivor `skills/brief/references/brief-format.md#L419-L424`
- `skills/brief/references/phases/phase-2-draft.md#L163-L171`, 413 bytes, excerpt `` - Matches (paraphrased) the frontmatter `outcome:` ``; survivor `skills/brief/references/brief-format.md#L419-L426`
- `skills/brief/references/phases/phase-3-structural-fill.md#L37-L48`, 739 bytes, excerpt `` - Each journey has a `###` heading naming ``; survivor `skills/brief/references/brief-format.md#L430-L443`
- `skills/brief/references/phases/phase-3-structural-fill.md#L56-L61`, 292 bytes, excerpt `**Common failure modes:**`; survivor `skills/brief/references/brief-format.md#L434-L440`
- `skills/brief/references/phases/phase-3-structural-fill.md#L79-L82`, 265 bytes, excerpt `- The out-list must contain genuine exclusions,`; survivor `skills/brief/references/brief-format.md#L450-L454`
- `skills/brief/references/phases/phase-3-structural-fill.md#L92-L94`, 215 bytes, excerpt `**Common failure mode:** an out-of-scope`; survivor `skills/brief/references/brief-format.md#L450-L454`
- `skills/brief/references/phases/phase-4-validate.md#L309`, 132 bytes, excerpt `| Reviewers disagree on the same issue |`; survivor `skills/brief/references/phases/phase-4-validate.md#L311-L314`
- `skills/brief/references/phases/phase-4-validate.md#L384-L388`, 114 bytes, excerpt `When fencing verdict bodies in this surfacing`; survivor `skills/brief/references/phases/phase-4-validate.md#L341-L346`
- `skills/brief/references/phases/phase-5-finalize.md#L42-L46`, 354 bytes, excerpt `prevent rendered-markdown injection — verdict`; survivor `skills/brief/references/phases/phase-4-validate.md#L341-L346`
- `skills/brief/references/phases/phase-5-finalize.md#L107-L109`, 224 bytes, excerpt `The subcommand updates both the frontmatter`; survivor `skills/brief/references/brief-format.md#L246-L251`
- `skills/brief/references/brief-format.md#L145-L168`, 1296 bytes, excerpt `- **Status.** First non-blank line is the`; survivor `skills/brief/references/brief-format.md#L403-L455`
- `skills/brief/references/brief-format.md#L197-L208`, 301 bytes, excerpt `## Section Matrix`; survivor `skills/brief/references/brief-format.md#L125-L195`
- `skills/brief/references/brief-format.md#L287-L294`, 189 bytes, excerpt `### Directory Mapping`; survivor `skills/brief/references/brief-format.md#L248-L256`
- `skills/brief/references/brief-format.md#L313-L315`, 196 bytes, excerpt `must be equal. Because the *whole* first`; survivor `skills/brief/references/brief-format.md#L73-L82`
- `skills/brief/references/brief-format.md#L321-L353`, 945 bytes, excerpt `` ### The `## Status` first-line convention ``; survivor `skills/brief/references/brief-format.md#L73-L92`
- `skills/brief/references/brief-format.md#L355-L362`, 339 bytes, excerpt `### During /brief (drafting)`; survivor `skills/brief/references/brief-format.md#L73-L92`
- `skills/brief/references/brief-format.md#L371-L381`, 480 bytes, excerpt `### During /brief finalization (approval)`; survivor `skills/brief/references/brief-format.md#L430-L455`
- `skills/brief/references/brief-format.md#L391-L396`, 216 bytes, excerpt `### Status consistency`; survivor `skills/brief/references/brief-format.md#L73-L92`
- `skills/brief/references/brief-format.md#L457-L473`, 692 bytes, excerpt `### Open Questions (optional, Draft only)`; survivor `skills/brief/references/brief-format.md#L181-L195`
- `skills/brief/references/brief-format.md#L475-L491`, 958 bytes, excerpt `### Common Pitfalls`; survivor `skills/brief/references/brief-format.md#L403-L455`
- `skills/brief/references/brief-format.md#L496-L498`, 189 bytes, excerpt `- **Drifting into requirements.** A brief`; survivor `skills/brief/references/brief-format.md#L403-L455`

##### `dp-prd-internal-restatements`

Profiles: `scope`. Size: 3413 bytes (about 853 tokens). Settled by #541. Only statement of a rule in force: no.

Text in /prd's own files that restates another of its own files, so it is redundant even when /prd runs standalone.

- `skills/prd/SKILL.md#L90-L93`, 298 bytes, excerpt `` **Upstream:** check `$ARGUMENTS` for `--upstream ``; survivor `skills/prd/references/phases/phase-3-draft.md#L31-L35`
- `skills/prd/SKILL.md#L97-L98`, 205 bytes, excerpt `Detect visibility (Private/Public) from CLAUDE.md`; survivor `skills/prd/SKILL.md#L52`
- `skills/prd/SKILL.md#L104-L118`, 933 bytes, excerpt `Phase 0: SETUP --> Phase 1: SCOPE --> Phase`; survivor `skills/prd/SKILL.md#L150-L188`
- `skills/prd/SKILL.md#L133-L135`, 213 bytes, excerpt `` rd_<topic>_scope.md` row is a partial-ru ``; survivor `skills/prd/references/phases/phase-1-scope.md#L19-L21`
- `skills/prd/SKILL.md#L137-L141`, 306 bytes, excerpt `Phase 0 detection: if the parent-chain sentinel`; survivor `skills/prd/SKILL.md#L123-L124`
- `skills/prd/SKILL.md#L145-L146`, 156 bytes, excerpt `- **Conversational First**: Phase 1 is a`; survivor `skills/prd/references/phases/phase-1-scope.md#L23-L61`
- `skills/prd/SKILL.md#L211-L219`, 354 bytes, excerpt `## Reference Files`; survivor `skills/prd/SKILL.md#L150-L188`
- `skills/prd/references/phases/phase-3-draft.md#L108-L109`, 134 bytes, excerpt `- **Acceptance Criteria**: Derive from requirements.`; survivor `skills/prd/references/prd-format.md#L229-L233`
- `skills/prd/references/phases/phase-4-validate.md#L178`, 121 bytes, excerpt `| Agents disagree on same issue | Present`; survivor `skills/prd/references/phases/phase-4-validate.md#L180-L183`
- `skills/prd/references/phases/phase-4-validate.md#L316-L319`, 248 bytes, excerpt `current branch and is the durable observable`; survivor `skills/prd/references/phases/phase-4-validate.md#L223-L227`
- `skills/prd/references/prd-format.md#L196-L200`, 245 bytes, excerpt `### During /prd finalization (approval)`; survivor `skills/prd/references/prd-format.md#L227-L233`
- `skills/prd/references/prd-format.md#L242-L244`, 200 bytes, excerpt `- Mixing "what" and "how" -- save technical`; survivor `skills/prd/references/prd-format.md#L227-L230`

##### `dp-design-internal-restatements`

Profiles: `scope`. Size: 3947 bytes (about 986 tokens). Settled by #637. Only statement of a rule in force: no.

Text in /design's own files that restates another of its own files, so it is redundant even when /design runs standalone.

- `skills/design/SKILL.md#L127-L130`, 196 bytes, excerpt `Directory structure makes lifecycle state`; survivor `skills/design/references/lifecycle.md#L14-L19`
- `skills/design/SKILL.md#L170-L182`, 846 bytes, excerpt `Phase 0: SETUP --> Phase 1: DECOMPOSE -->`; survivor `skills/design/SKILL.md#L245-L257`
- `skills/design/SKILL.md#L211-L212`, 180 bytes, excerpt `- **Security is mandatory**: Phase 5 always`; survivor `skills/design/references/phases/phase-5-security.md#L3-L8`
- `skills/design/SKILL.md#L274-L285`, 590 bytes, excerpt `## Reference Files`; survivor `skills/design/SKILL.md#L245-L257`
- `skills/design/references/phases/phase-0-setup-prd.md#L65-L74`, 619 bytes, excerpt `This is the symmetric three-skill contract:`; survivor `skills/design/references/phases/phase-0-setup-prd.md#L45-L63`
- `skills/design/references/phases/phase-0-setup-prd.md#L200-L202`, 232 bytes, excerpt `` The `upstream` field creates a machine-readable ``; survivor `skills/design/references/phases/phase-0-setup-prd.md#L150-L153`
- `skills/design/references/phases/phase-6-final-review.md#L326-L327`, 86 bytes, excerpt `the current branch and is the durable observable`; survivor `skills/design/references/phases/phase-6-final-review.md#L223-L227`
- `skills/design/references/lifecycle.md#L36-L37`, 156 bytes, excerpt `- **Design accepted (Phase 6):** Remove whatever`; survivor `skills/design/references/phases/phase-6-final-review.md#L239-L243`
- `skills/design/references/lifecycle.md#L46-L50`, 218 bytes, excerpt `### During /design or /explore (drafting)`; survivor `skills/design/references/phases/phase-6-final-review.md#L130-L139`
- `skills/design/references/lifecycle.md#L69-L71`, 227 bytes, excerpt `Organized by decision question. Each gets`; survivor `skills/design/references/quality/considered-options-structure.md#L7-L8`
- `skills/design/references/lifecycle.md#L76-L82`, 439 bytes, excerpt `The Security Considerations section must`; survivor `skills/design/references/phases/phase-5-security.md#L53-L64`
- `skills/design/references/lifecycle.md#L86-L87`, 158 bytes, excerpt `- Strawman options -- alternatives that exist`; survivor `skills/design/references/phases/phase-5-security.md#L123-L127`

##### `dp-plan-internal-restatements`

Profiles: `scope`. Size: 13469 bytes (about 3367 tokens). Settled by #658. Only statement of a rule in force: no.

Text in /plan's own files that restates another of its own files, so it is redundant even when /plan runs standalone.

- `skills/plan/SKILL.md#L64-L66`, 218 bytes, excerpt `` Frontmatter includes `schema: plan/v1`, `status`, ``; survivor `skills/plan/references/quality/plan-doc-structure.md#L61-L76`
- `skills/plan/SKILL.md#L130-L131`, 143 bytes, excerpt `The skeleton issue comes first in the dependency`; survivor `skills/plan/references/phases/phase-3-decomposition.md#L149-L160`
- `skills/plan/SKILL.md#L149-L156`, 514 bytes, excerpt `` When the input is a roadmap (`input_type: ``; survivor `skills/plan/references/phases/phase-3-decomposition.md#L299-L323`
- `skills/plan/SKILL.md#L160-L163`, 317 bytes, excerpt `This is a separate decision from the Decomposition`; survivor `skills/plan/references/phases/phase-3-decomposition.md#L5-L21`
- `skills/plan/SKILL.md#L195-L202`, 595 bytes, excerpt `The value-confirmation step (Phase 3.5a)`; survivor `skills/plan/references/phases/phase-3-decomposition.md#L406-L480`
- `skills/plan/SKILL.md#L204-L225`, 1329 bytes, excerpt `**Split mode.** Whether the work splits is`; survivor `skills/plan/references/phases/phase-3-decomposition.md#L562-L605`
- `skills/plan/SKILL.md#L229-L240`, 847 bytes, excerpt `` `coordinated` is the third execution mode. ``; survivor `skills/plan/references/quality/plan-doc-structure.md#L141-L160`
- `skills/plan/SKILL.md#L248-L257`, 781 bytes, excerpt `Mechanically, each coordinated work item`; survivor `skills/plan/references/quality/plan-doc-structure.md#L169-L276`
- `skills/plan/SKILL.md#L267-L276`, 301 bytes, excerpt `## Placeholder Conventions`; survivor `skills/plan/references/templates/agent-prompt.md#L65-L78`
- `skills/plan/SKILL.md#L307-L308`, 135 bytes, excerpt `` Store the detected `input_type` in the Phase ``; survivor `skills/plan/references/phases/phase-1-analysis.md#L29`
- `skills/plan/SKILL.md#L514-L526`, 1194 bytes, excerpt `Seven sequential phases, plus an execution`; survivor `skills/plan/SKILL.md#L556-L587`
- `skills/plan/SKILL.md#L528-L543`, 1029 bytes, excerpt `#### Value Confirmation and Execution Mode`; survivor `skills/plan/references/phases/phase-3-decomposition.md#L406-L605`
- `skills/plan/SKILL.md#L592-L593`, 194 bytes, excerpt `- Design doc status transitions: Accepted`; survivor `skills/plan/references/phases/phase-7-creation.md#L605-L638`
- `skills/plan/SKILL.md#L599`, 126 bytes, excerpt `` - **Input Type**: store the detected `input_type` ``; survivor `skills/plan/references/phases/phase-1-analysis.md#L29`
- `skills/plan/SKILL.md#L643-L652`, 452 bytes, excerpt `1. Parse flags from arguments, rejecting`; survivor `skills/plan/SKILL.md#L296-L364`
- `skills/plan/SKILL.md#L672-L678`, 421 bytes, excerpt `` | `references/phases/phase-1-analysis.md` ``; survivor `skills/plan/SKILL.md#L556-L587`
- `skills/plan/references/phases/phase-1-analysis.md#L110`, 56 bytes, excerpt `Do NOT proceed with planning unless status`; survivor `skills/plan/references/phases/phase-1-analysis.md#L103`
- `skills/plan/references/phases/phase-3-decomposition.md#L67-L70`, 243 bytes, excerpt `This is the work-slicing decision: walking`; survivor `skills/plan/references/phases/phase-3-decomposition.md#L5-L21`
- `skills/plan/references/phases/phase-3-decomposition.md#L306-L311`, 441 bytes, excerpt `A roadmap input also lands multi-pr at step`; survivor `skills/plan/references/phases/phase-3-decomposition.md#L423-L425`
- `skills/plan/references/phases/phase-3-decomposition.md#L504-L513`, 582 bytes, excerpt `` **The surfaced rule** (`skills/plan/SKILL.md`, ``; survivor `skills/plan/SKILL.md#L165-L193`
- `skills/plan/references/phases/phase-3-decomposition.md#L515-L518`, 251 bytes, excerpt `The branch this step selects is not bookkeeping:`; survivor `skills/plan/SKILL.md#L185-L188`
- `skills/plan/references/phases/phase-3-decomposition.md#L630-L636`, 456 bytes, excerpt `` `### Gate: <name>` block under `## Issue ``; survivor `skills/plan/references/quality/plan-doc-structure.md#L212-L220`
- `skills/plan/references/phases/phase-4-agent-generation.md#L111-L115`, 467 bytes, excerpt `5. Build execution mode context string:`; survivor `skills/plan/references/phases/phase-4-agent-generation.md#L22-L30`
- `skills/plan/references/phases/phase-4-agent-generation.md#L208-L213`, 309 bytes, excerpt `The grep procedure is documented in the agent`; survivor `skills/plan/references/phases/phase-4-agent-generation.md#L203-L206`
- `skills/plan/references/phases/phase-4-agent-generation.md#L230-L243`, 475 bytes, excerpt `**Agent output instructions** (include in`; survivor `skills/plan/references/templates/agent-prompt.md#L118-L131`
- `skills/plan/references/phases/phase-4-agent-generation.md#L290`, 248 bytes, excerpt `**Validation differs by execution mode and`; survivor `skills/plan/references/phases/phase-4-agent-generation.md#L27-L28`
- `skills/plan/references/phases/phase-4-agent-generation.md#L380-L383`, 233 bytes, excerpt `above: **Front matter validation** (same as multi-pr):`; survivor `skills/plan/references/phases/phase-4-agent-generation.md#L332-L335`
- `skills/plan/references/phases/phase-4-agent-generation.md#L488-L492`, 263 bytes, excerpt `Phase 4 produces these artifacts:`; survivor `skills/plan/references/phases/phase-4-agent-generation.md#L226`
- `skills/plan/references/phases/phase-6-review.md#L14-L16`, 192 bytes, excerpt `Read both file paths before proceeding. If`; survivor `skills/plan/references/phases/phase-6-review.md#L8-L12`
- `skills/plan/references/phases/phase-7-creation.md#L46`, 46 bytes, excerpt `above: subcommand's default.`; survivor `skills/plan/references/phases/phase-7-creation.md#L48`
- `skills/plan/references/quality/plan-doc-structure.md#L357-L362`, 380 bytes, excerpt `**Feature-by-feature planning** maps each`; survivor `skills/plan/references/phases/phase-3-decomposition.md#L299-L323`
- `skills/plan/references/templates/agent-prompt.md#L155-L157`, 231 bytes, excerpt `**Critical complexity** (multi-pr mode only):`; survivor `skills/plan/references/templates/agent-prompt.md#L84-L96`

##### `dp-review-plan-internal-restatements`

Profiles: `scope`. Size: 7460 bytes (about 1865 tokens). Settled by #534. Only statement of a rule in force: no.

Text in /review-plan's own files that restates another of its own files, so it is redundant even when /review-plan runs standalone.

- `skills/review-plan/SKILL.md#L78-L79`, 167 bytes, excerpt `` Without `--adversarial`, the skill runs fast-path ``; survivor `skills/review-plan/SKILL.md#L68-L71`
- `skills/review-plan/SKILL.md#L81-L90`, 419 bytes, excerpt `## Execution Mode Detection`; survivor `skills/review-plan/references/phases/phase-0-setup.md#L73-L85`
- `skills/review-plan/SKILL.md#L151-L157`, 388 bytes, excerpt `` From `$ARGUMENTS` (after stripping flags): ``; survivor `skills/review-plan/references/phases/phase-0-setup.md#L12-L21`
- `skills/review-plan/SKILL.md#L159-L182`, 1031 bytes, excerpt `## Phase Execution Sequence`; survivor `skills/review-plan/SKILL.md#L204-L217`
- `skills/review-plan/SKILL.md#L186-L192`, 334 bytes, excerpt `Phase 5 writes exactly one file per review`; survivor `skills/review-plan/references/phases/phase-5-verdict.md#L55-L107`
- `skills/review-plan/references/phases/phase-1-scope-gate.md#L112-L113`, 163 bytes, excerpt `` The `correction_hint` field is left empty ``; survivor `skills/review-plan/references/templates/review-result-schema.md#L128-L129`
- `skills/review-plan/references/phases/phase-1-scope-gate.md#L117-L119`, 78 bytes, excerpt `## Loop-Back Target`; survivor `skills/review-plan/references/templates/review-result-schema.md#L43-L49`
- `skills/review-plan/references/phases/phase-2-design-fidelity.md#L24`, 77 bytes, excerpt `` For `topic` and `roadmap` inputs, skip all ``; survivor `skills/review-plan/references/phases/phase-2-design-fidelity.md#L21-L22`
- `skills/review-plan/references/phases/phase-2-design-fidelity.md#L86-L88`, 202 bytes, excerpt `` The `correction_hint` field is left empty ``; survivor `skills/review-plan/references/templates/review-result-schema.md#L128-L129`
- `skills/review-plan/references/phases/phase-2-design-fidelity.md#L98-L100`, 73 bytes, excerpt `## Loop-Back Target`; survivor `skills/review-plan/references/templates/review-result-schema.md#L43-L49`
- `skills/review-plan/references/phases/phase-3-ac-discriminability.md#L30`, 74 bytes, excerpt `` For `roadmap` input types, this phase returns ``; survivor `skills/review-plan/references/phases/phase-3-ac-discriminability.md#L28`
- `skills/review-plan/references/phases/phase-3-ac-discriminability.md#L39-L45`, 404 bytes, excerpt `trigger**: the AC text contains any of these terms`; survivor `skills/review-plan/references/templates/ac-discriminability-taxonomy.md#L28-L34`
- `skills/review-plan/references/phases/phase-3-ac-discriminability.md#L51-L57`, 419 bytes, excerpt `**Detection trigger**: scan the *entire issue`; survivor `skills/review-plan/references/templates/ac-discriminability-taxonomy.md#L99-L104`
- `skills/review-plan/references/phases/phase-3-ac-discriminability.md#L64-L72`, 547 bytes, excerpt `trigger**: the AC text contains any of these phrases`; survivor `skills/review-plan/references/templates/ac-discriminability-taxonomy.md#L253-L262`
- `skills/review-plan/references/phases/phase-3-ac-discriminability.md#L111-L113`, 204 bytes, excerpt `- Pattern 3 triggers but the issue has at`; survivor `skills/review-plan/references/templates/ac-discriminability-taxonomy.md#L106-L107`
- `skills/review-plan/references/phases/phase-3-ac-discriminability.md#L128-L133`, 389 bytes, excerpt `**Category C findings must include a non-empty`; survivor `skills/review-plan/references/templates/review-result-schema.md#L121-L136`
- `skills/review-plan/references/phases/phase-3-ac-discriminability.md#L137-L139`, 81 bytes, excerpt `## Loop-Back Target`; survivor `skills/review-plan/references/templates/review-result-schema.md#L43-L49`
- `skills/review-plan/references/phases/phase-4-sequencing.md#L27`, 74 bytes, excerpt `` For `roadmap` input types, this phase returns ``; survivor `skills/review-plan/references/phases/phase-4-sequencing.md#L25`
- `skills/review-plan/references/phases/phase-4-sequencing.md#L96-L98`, 235 bytes, excerpt `` The `correction_hint` field is left empty ``; survivor `skills/review-plan/references/templates/review-result-schema.md#L128-L129`
- `skills/review-plan/references/phases/phase-4-sequencing.md#L102-L110`, 431 bytes, excerpt `## Loop-Back Targets for Category D Findings`; survivor `skills/review-plan/references/templates/review-result-schema.md#L43-L62`
- `skills/review-plan/references/phases/phase-5-verdict.md#L29-L34`, 260 bytes, excerpt `if B findings exist`; survivor `skills/review-plan/references/templates/review-result-schema.md#L56-L62`
- `skills/review-plan/references/phases/phase-5-verdict.md#L39-L40`, 157 bytes, excerpt `When a single verdict contains both D-structural`; survivor `skills/review-plan/references/templates/review-result-schema.md#L51-L62`
- `skills/review-plan/references/templates/review-result-schema.md#L84-L87`, 200 bytes, excerpt `The review skill's confidence in the verdict.`; survivor `skills/review-plan/references/phases/phase-5-verdict.md#L42-L53`
- `skills/review-plan/references/templates/review-result-schema.md#L89`, 80 bytes, excerpt `- Roadmap input type (B, C, D return empty`; survivor `skills/review-plan/references/phases/phase-5-verdict.md#L42-L53`
- `skills/review-plan/references/templates/review-result-schema.md#L145-L148`, 227 bytes, excerpt `` - `"Review passed. No critical findings across ``; survivor `skills/review-plan/references/phases/phase-5-verdict.md#L111-L116`
- `skills/review-plan/references/templates/ac-discriminability-taxonomy.md#L6-L10`, 256 bytes, excerpt `Phase 3 runs two passes:`; survivor `skills/review-plan/references/phases/phase-3-ac-discriminability.md#L3-L11`
- `skills/review-plan/references/phases/phase-0-setup.md#L91-L96`, 490 bytes, excerpt `| input_type | Category A | Category B |`; survivor the input-type tables in review-plan phases 1 to 4

#### Steps naming files or mechanisms that no longer exist

##### `dp-work-on-missing-files`

Profiles: `work-on`. Size: 722 bytes (about 180 tokens). Settled by #557. Only statement of a rule in force: no.

Removed by commit-koto-context-artifacts and the sentinel row that cannot fire; counted here once.

- `skills/work-on/references/phases/phase-1-setup.md#L66-L69`, 64 bytes, excerpt `` `docs: establish baseline for <short-description>` ``
- `skills/work-on/references/phases/phase-3-analysis.md#L49-L50`, 44 bytes, excerpt `` Commit: `docs: create implementation plan` ``
- `skills/work-on/references/phases/phase-5-finalization.md#L121-L124`, 64 bytes, excerpt `` Commit summary: `docs: add implementation ``
- `skills/work-on/koto-templates/work-on.md#L2000-L2001`, 124 bytes, excerpt `commit convention is checked only here, because`
- `skills/work-on/SKILL.md#L402-L408`, 426 bytes, excerpt `Phase 0 detection: if the parent-chain sentinel`

##### `dp-execute-skill-dead-mechanisms`

Profiles: `execute-single-pr`, `execute-coordinated`. Size: 12723 bytes (about 3180 tokens). Settled by #545. Only statement of a rule in force: no.

The state projection, sentinel and child-as-PR prose removed by execute-state-file-projection, execute-sentinel-no-reader and execution-children-described-as-prs.

- `skills/execute/SKILL.md#L144-L187`, 2913 bytes, excerpt `## Workflow Phases`
- `skills/execute/SKILL.md#L761-L825`, 4458 bytes, excerpt `` `/execute` maintains a per-session state ``
- `skills/execute/SKILL.md#L876-L936`, 3592 bytes, excerpt `` On re-entry, `/execute` follows the universal ``
- `skills/execute/SKILL.md#L1174-L1194`, 1317 bytes, excerpt `## Child Inspection`
- `skills/execute/SKILL.md#L1259-L1264`, 443 bytes, excerpt `` 4. **Stale `parent_orchestration:` self-heal.** ``

##### `dp-execute-pointer-loaded-refs`

Profiles: `execute-single-pr`. Size: 11058 bytes (about 2764 tokens). Settled by #545. Surviving statement: the execute.md directives.

Removed by worktree-discipline-vs-drift-state: dropping the pointer unloads the file for /execute; it stays for its other callers.

- pointer `skills/execute/koto-templates/execute.md#L1326` (excerpt `` `drift_facts.json` says why you're being ``) loads the whole of `references/worktree-discipline.md`, 8482 bytes
- `skills/work-on/references/phases/phase-2.5-worktree-discipline.md#L1-L36`, 1712 bytes, excerpt `# Phase 2.5: Worktree Discipline Check (Plan-Orchestrator`
- `skills/work-on/references/phases/phase-2.5-worktree-discipline.md#L128-L144`, 864 bytes, excerpt `## Why This Phase Exists`

##### `dp-execute-phase-6-pointer`

Profiles: `execute-single-pr`. Size: 2735 bytes (about 683 tokens). Settled by #545. Surviving statement: the execute.md directives.

Blocked on: `force-push-after-rebase`, `retry-caps`.

Removed by phase-6-pr-shared-with-execute. The file holds /execute's side of two policy items, so dropping the pointer waits on both decisions.

- pointer `skills/execute/koto-templates/execute.md#L1456` (excerpt `` AUDE_PLUGIN_ROOT}/skills/work-on/references/phases/phase-6-pr.md` ``) loads the whole of `skills/work-on/references/phases/phase-6-pr.md`, 2735 bytes

##### `dp-scope-no-reader`

Profiles: `scope`. Size: 5791 bytes (about 1447 tokens). Settled by #586. Only statement of a rule in force: no.

The shape-predicate walk and the post-/prd gate, removed by r6-verdicts-no-reader.

- `skills/scope/references/phases/phase-1-discovery.md#L113-L131`, 890 bytes, excerpt `` ## Post-`/prd` Re-evaluation Gate ``
- `skills/scope/references/phases/phase-1-discovery.md#L185-L192`, 284 bytes, excerpt `## R6 Shape-Predicate Walk`
- `skills/scope/references/phases/phase-1-discovery.md#L198-L301`, 4617 bytes, excerpt `At Phase 1 the PRD does not exist yet, so`

#### Text describing what koto or a script already does

##### `dp-work-on-koto-restated`

Profiles: `work-on`. Size: 1636 bytes (about 409 tokens). Settled by #557. Surviving statement: the evidence schema koto returns with each directive.

- `skills/work-on/references/phases/phase-0-context-injection.md#L33-L37`, 199 bytes, excerpt `` Submit `status: completed` after the context ``
- `skills/work-on/references/phases/phase-3-analysis.md#L104-L110`, 387 bytes, excerpt `` - `plan_outcome: plan_ready` — plan complete ``
- `skills/work-on/references/phases/phase-5-finalization.md#L130-L139`, 645 bytes, excerpt `` - `finalization_status: ready_for_pr` — every ``
- `skills/work-on/koto-templates/work-on.md#L1657-L1658`, 171 bytes, excerpt `` When `SHARED_BRANCH` is set, submit `status: ``
- `skills/work-on/koto-templates/work-on.md#L1921-L1923`, 234 bytes, excerpt `Reaching this state means verification ran`

##### `dp-execute-skill-koto-restated`

Profiles: `execute-single-pr`, `execute-coordinated`. Size: 824 bytes (about 206 tokens). Settled by #545. Surviving statement: the koto init call in skills/execute/scripts/execute-open.sh.

- `skills/execute/SKILL.md#L228-L238`, 824 bytes, excerpt `The call it makes is`

##### `dp-deliver-skill`

Profiles: `deliver`. Size: 6901 bytes (about 1725 tokens). Settled by #541. Surviving statement: the deliver.md directives and the exit script.

- `skills/deliver/SKILL.md#L35-L56`, 1272 bytes, excerpt `## How the Run Is Held Together`
- `skills/deliver/SKILL.md#L197-L216`, 1111 bytes, excerpt `` There is no resume state in `/deliver` itself. ``
- `skills/deliver/SKILL.md#L218-L227`, 579 bytes, excerpt `## Final States`
- `skills/deliver/SKILL.md#L229-L237`, 1148 bytes, excerpt `` | `scoped` | The author declined the confirmation; ``
- `skills/deliver/SKILL.md#L239-L249`, 606 bytes, excerpt `## Write Targets`
- `skills/deliver/SKILL.md#L251-L270`, 1289 bytes, excerpt `## Security Considerations`
- `skills/deliver/SKILL.md#L272-L280`, 573 bytes, excerpt `## Reference Files`
- `skills/deliver/koto-templates/deliver.md#L1107-L1111`, 323 bytes, excerpt `This is the only question /deliver itself`

##### `dp-scope-koto-restated`

Profiles: `scope`. Size: 7255 bytes (about 1813 tokens). Settled by #586. Surviving statement: skills/scope/scripts/resume-probe.sh and the intake, branch_check and resume_route states.

- `skills/scope/SKILL.md#L127-L129`, 235 bytes, excerpt `The declarator is prose per the pattern's`
- `skills/scope/references/phases/phase-0-setup.md#L12-L19`, 508 bytes, excerpt `Argument checking is not a prose step here`
- `skills/scope/references/phases/phase-0-setup.md#L158-L185`, 1471 bytes, excerpt `## The Intake and Branch Checks Are States,`
- `skills/scope/references/phases/phase-0-setup.md#L376-L391`, 792 bytes, excerpt `## Slug Re-Validation on Resume`
- `skills/scope/SKILL.md#L446-L500`, 2905 bytes, excerpt `## Resume Logic`
- `skills/scope/koto-templates/scope.md#L2181-L2190`, 684 bytes, excerpt `**The argument checks ran before this state.**`
- `skills/scope/references/phases/phase-2-chain-orchestration.md#L212-L221`, 660 bytes, excerpt `` The `plan_mode_consistent` gate on `hop_plan`'s ``

##### `dp-plan-koto-restated`

Profiles: `scope`. Size: 806 bytes (about 201 tokens). Settled by #658. Surviving statement: skills/scope/scripts/resume-probe.sh and the intake, branch_check and resume_route states.

- `skills/plan/references/phases/phase-7-creation.md#L545-L555`, 806 bytes, excerpt `What the two invocations check between them:`

### Per-profile totals

Every figure in this document is regenerated by one command from committed
files: `python3 docs/designs/contradiction-settlement/measure.py`, run from
any directory inside the repository. It reads each cited file as it is at `662f6ec`, checks every
location and excerpt, recomputes every byte count, total and share, rebuilds
this document from `docs/designs/contradiction-settlement/design.md.tmpl` and
`docs/designs/contradiction-settlement/inventory.json`, and exits non-zero if
the result differs from the committed file. The raw loads and the load
manifest's file list are copied into the data file from the baseline pin
(#488), and are that pin's figures rather than this script's.

Tokens are bytes divided by four, the baseline pin's method. Overlapping
spans are counted once per profile, a pointer-loaded file counts in full, and
a span loaded by several profiles counts toward each. The `scope` figure
leaves out the plugin references its table tells the agent to read; those
have weight 0 in the load manifest and are handled by
`scope-reference-table-vs-lazy-load`.

| Profile | Raw load at the pin (tokens) | Dead prose (bytes) | Dead prose (tokens) | Share of raw |
|---|---:|---:|---:|---:|
| `work-on` | 46,671 | 52,682 | 13,170 | 28.2% |
| `execute-single-pr` | 41,083 | 83,779 | 20,944 | 51.0% |
| `execute-coordinated` | 24,844 | 61,994 | 15,498 | 62.4% |
| `deliver` | 6,181 | 6,901 | 1,725 | 27.9% |
| `scope` | 226,407 | 110,234 | 27,558 | 12.2% |

**Why the `scope` share is lower than a whole-load estimate would suggest.**
The table counts only text that can be deleted. Four more parts of `/scope`'s
raw load are prose the agent does not need at runtime, and each is left out
of the figure for a stated reason:

- *Parent-skill references with no runtime role under `/scope`* (the five
  `references/parent-skill-*.md` files and `references/worktree-discipline.md`):
  108,128 bytes, 27,032 tokens or 11.9% of raw. The load manifest counts
  them in raw at weight 0. `scope-reference-table-vs-lazy-load` removes the
  instruction to read them; the files stay for `/charter` and for
  maintainers, so this is a loading change, not a deletion, and the re-count (#665)
  re-count reports it separately.
- *Child-skill text restating a file from another skill or from `/scope`*:
  not measured span by span, so no figure is given. Each copy is needed
  when that child runs standalone, so removing it is per-caller loading, a
  separate feature. Restatements inside one child's own files are redundant
  standalone too, and are counted above as the
  `dp-<skill>-internal-restatements` entries.
- *Summary sections in child phase files* (Goal, Quality Checklist, Artifact
  State, Success Criteria): not measured span by span. They repeat their
  phase body, but a checklist also asks the agent to check its
  work before moving on, so they are not treated as strictly redundant.
- *Child text restating an open policy item's behavior*: 4,466 bytes
  over 14 spans, listed in `held_for_policy` in the inventory data.
  These spans went with those items once they were decided, in the pull
  requests that applied each decision.

Counting the parent-skill references alongside the table's figure puts
`scope` at 24.1% of raw.

### Withholding candidates (out of this feature)

Each of these is the only loaded statement of a rule still in force. No work
item in this feature deletes or moves them; they are inputs to the ablation
feature.

- `wh-work-on-retry-clearing-blocks` (`work-on`; 4821 bytes). Each of the seven executable retry-clearing blocks is the only statement of its state's key list and escalate outcome. Consolidating them into one script, or koto clearing keys on the back edge, is what would make them removable; retry-clearing_test.sh extracts every copy. Spans: `skills/work-on/references/phases/phase-3-analysis.md#L78-L92`, `skills/work-on/references/phases/phase-4-implementation.md#L150-L164`, `skills/work-on/references/phases/phase-4a-scrutiny.md#L47-L61`, `skills/work-on/references/phases/phase-4b-review.md#L45-L59`, `skills/work-on/references/phases/phase-4c-qa.md#L44-L58`, `skills/work-on/koto-templates/work-on.md#L1836-L1850`, `skills/work-on/references/phases/phase-5-finalization.md#L146-L160`.
- `wh-work-on-introspection-evidence` (`work-on`; 257 bytes). The only statement of what introspection submits. Spans: `skills/work-on/references/phases/phase-2-introspection.md#L20-L24`.
- `wh-execute-d5-rule` (`execute-single-pr`, `execute-coordinated`; 955 bytes). The only statements of the rules the surrounding rationale explains. Spans: `skills/execute/SKILL.md#L829-L836`, `skills/execute/SKILL.md#L872-L875`.
- `wh-deliver-leg-contract` (`deliver`; 3453 bytes). The only statement of the caller leg contract a coordinator relies on; it could move to a reference coordinators load. Spans: `skills/deliver/SKILL.md#L78-L133`.
- `wh-scope-no-floor-guard` (`scope`; 957 bytes). A maintainer rule (do not add a guard that forces keep) with no other statement; it could move out of the runtime file. Spans: `skills/scope/references/phases/phase-2-chain-orchestration.md#L849-L869`.

### Follow-ups

Found while reading, outside this feature's scope or after the inventory
closed. Three were settled by the work items: Phase 3's pointer to a missing
Phase 4 file (#637), /prd's ROADMAP upstream (#660), and /charter's `exit:
UNSET` literal, which the shared state schema now allows as a parent's own
placeholder (#586). The rest were tracked on issue #659, with every other
follow-up from this feature, and settled by the pull request that closed it,
except two that need a person's decision: who removes `needs-design` under
`/scope` (#666) and the autonomy variable below (#667). A sweep of working
files on a single-pr `/execute` run is #668.

- Let `/execute`'s PR title take the type the directive describes, limited to
  `feat`, `fix`, `docs` and `chore` (see `execute-pr-title-type`).
- Decide whether `/execute`'s children should receive an autonomy variable
  (see `execute-sentinel-no-reader`; #667).
- `skills/plan/references/quality/plan-doc-examples.md` nests
  `### Dependency Graph` under Implementation Issues, which FC04 cannot see.
- `docs/specs/decision-points.md` has stale line locators into
  `/work-on`'s phase files.
- A `/scope` phase file names `cmd/shirabe/`, which does not exist; the
  binary is built from `crates/shirabe`.
- The resume rows in the `/brief`, `/prd`, `/plan` and `/design` SKILL.md
  files cite `references/fixes/sub-agent-dispatch.md`, and the `--auto` notes
  in `/prd`'s, `/plan`'s and `/design`'s cite `references/decision-protocol.md`,
  relative to the skill, where neither file exists; both are at the plugin
  root.

## Implementation Approach

**Outcome.** The approach below ran as planned, batched into one pull request
per skill so that each policy decision landed with the skill it edits. The ten
decisions were recorded first (#531); the work items then landed in #534
(/review-plan), #541 (/deliver, /brief and /prd), #557 (/work-on), #545
(/execute, with the baseline manifest change in #579), #586 (/scope and
/charter), #637 (/design), #658 (/plan) and #660 (/brief's and /prd's policy
share). Two contradictions found during execution, `prd-complexity-routing`
and `prd-upstream-roadmap`, were added to the inventory, so it holds 48 items.
The re-count is in `docs/measurement/contradiction-settlement-recount/` (#665),
with the command that reproduces its figures. The steps below are the plan as
written before execution.

1. **Wait for the baseline pin.** No work item that touches `skills/`,
   `references/`, `scripts/` or `crates/` starts before pull request #488
   merges.
2. **Mechanical work items, one per skill.** `/work-on`, `/execute`,
   `/deliver`, `/scope`, `/brief`, `/prd`, `/plan`, `/design` and
   `/review-plan`. A
   mechanical item whose losing statement sits inside a policy statement
   moves into that policy item. Each re-finds its spans by excerpt, stops and
   reports an identifier whose excerpt is missing or found twice, applies the
   winners and the dead-prose deletions it owns, and runs the skill's tests
   and evals where the repository has them.
3. **Policy work items, one per decision.** Each waits on its recorded
   decision under `docs/decisions/`, then edits the losing statements to the
   chosen option and applies the same excerpt and result checks.
4. **Re-count.** A final item re-runs the baseline pin's count for all five
   profiles and records before and after figures beside the estimates above,
   explaining any shortfall over 10%.

## Security Considerations

This feature edits instructions an agent follows, so the risks are about
what those instructions permit, not about data or credentials.

- **Push, filing and approval permissions.** Several policy items change
  whether a run force-pushes, files GitHub issues, opens pull requests or
  approves its own continuation. Carrying them as decisions for a person,
  and blocking their edits on a recorded decision, keeps an agent from
  widening its own permissions by rewriting its instructions.
- **Who records a decision.** A decision record carries the policy owner's
  answer and is merged by a person. An agent may draft one but never merges
  it, so no run with merge permission can unblock a policy edit by writing
  and landing its own decision.
- **Withholding.** Deleting the only statement of a safety rule would let an
  agent act without it until a gate fails. The withholding list keeps every
  such span in place for this feature.
- **Public content.** Every path cited is repository-relative and public; the
  inventory names no private repository, local path, session or job.

No new code paths, inputs or dependencies are introduced by this design.

## Consequences

As written before execution; the outcome is under Implementation Approach.

**Positive.** Each rule these skills load has one authoritative statement
after execution, and the ones where choosing that statement is a real choice
go to a person first. The loaded prose shrinks by a measured amount, and
later gate work can cite individual identifiers.

**Negative.** The inventory is a snapshot; anything that lands on `main`
before execution can move or remove a span, and the excerpt check will stop
those items. Policy items may wait a long time for decisions, leaving some
contradictions in place.

**Mitigations.** Items stop individually rather than failing the plan, and a
stopped item is re-inventoried against the new text. The policy decisions
are sent together, each with a recommendation, so they can be answered in
one sitting.
