---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-kept-plan.md
milestone: "Kept Plan"
issue_count: 6
---

# PLAN: Kept plan

## Status

Active

A placeholder for the execution to come. It was written as plan/v1 because the
installed release's `/scope` can't yet forward a plan version to `/plan`; the
execution regenerates it as a plan/v2 step plan before any work starts.

## Scope Summary

Keep a plan on the default branch at Done once its work merges, with a Run
Record of each step's PRs, proof and recorded decisions written by the
delivery run, links from the plan to its PRs and back, the validator rules
changed so a kept plan and a design that names it validate, and every
reference stating one lifecycle. The design is
`docs/designs/DESIGN-kept-plan.md`; its requirements are
`docs/prds/PRD-kept-plan.md`.

## Decomposition Strategy

**Horizontal.** One issue per step of the design's Implementation Approach,
in its order, each leaving the tree passing. The validator lands first, so
nothing that writes a kept plan meets a rule that rejects it. The lookups land
before any Done plan exists. The record writer lands before the cascade keeps
the plan, so a Done plan always carries a Run Record by the time `FC23`
checks it. The checker and the reference sweep come last.

## Issue Outlines

### Issue 1: feat(validate): accept a kept plan as a durable document

**Complexity**: critical

**Goal**: The validator treats a plan as a durable document, expects a plan at Done where it expected none, and checks a design's `plan:` field. finalize-chain's transition and `FC23` wait for Issue 4.

**Acceptance Criteria**:
- [ ] `shirabe validate` reports no `R11` for a design, PRD or brief whose `upstream:` names a plan; still reports `R11` for a design naming a roadmap and for a Done plan naming a roadmap; and reports none for an Active plan naming a roadmap.
- [ ] Lifecycle tests cover each row of PRD R16's posture table with the result it gives, including a Done plan whose design is Superseded and a chain with no plan file and its design at Current.
- [ ] A Current design whose `plan:` names its Done plan validates; one whose `plan:` names a missing file, a path outside `docs/plans/`, or a plan whose `upstream:` names another design fails `R12` naming both documents.
- [ ] `references/rule-registry.json` carries `docs/plan-link` for `R12`, and `cargo test` passes.

**Dependencies**: None.

---

---

### Issue 2: feat(lookups): skip Done plans and treat a Done plan as executed

**Complexity**: testable

**Goal**: Every lookup that resolves work from `docs/plans/` skips a Done plan, and `/scope` and `/deliver` treat a topic whose plan is Done as executed.

**Acceptance Criteria**:
- [ ] With a Done plan and an Active plan both naming issue `#N`, `find-anchor-plan.sh` resolves the Active one; with only the Done plan it reports no anchor plan.
- [ ] `drift-facts.sh` and `execute-open.sh` each have a test with one Done and one Active plan for the same work that resolves to the Active plan.
- [ ] `resume-probe.sh` routes a topic whose plan is Done to `executed_report` with `--intent=continue` and `--intent=stop`, and to the refusal naming the topic as executed with no intent; `deliver-probe.sh` reports the topic as executed.
- [ ] The changed scripts' tests pass under bash 3.2.

**Dependencies**: Blocked by Issue 1.

---

---

### Issue 3: feat(plan): write each step's run record into the plan and its PR

**Complexity**: critical

**Goal**: Delivery runs write a `## Run Record` entry per step or issue into the plan, and a `Plan:` line and a `Run record` part into the PR body, rendered by `plan-record.sh` from the session logs and filtered for private and secret content. This issue builds all four `plan-record.sh` subcommands, `landing` included; Issue 4 wires `landing` into `cascade_entry`.

**Acceptance Criteria**:
- [ ] For a fixture run whose Step 1 session recorded two decisions, whose Step 2 session recorded none and whose owning session recorded one, `plan-record.sh entry` prints the two under `### Step 1` with `<session>#<seq>` citations and verbatim text, `Decisions: none recorded.` under `### Step 2`, and the one under `### Plan`.
- [ ] `plan-record.sh pr-part` prints the `Decisions:` lines byte for byte as the plan holds them.
- [ ] A decision naming a private issue, a GitHub token or a home path renders as `withheld (private content)`; with the validator missing, every free-text line is withheld.
- [ ] A token inside a `Proof:` result line is withheld; a token that straddles the 500-character cap is withheld rather than truncated; a decision holding a URL, an `@` mention and a bidirectional control character is written with all three removed.
- [ ] `plan-record.sh entry` refuses, with a non-zero exit and no write, when the default branch's copy of the plan is already Done.
- [ ] In a `coordinated` fixture, the coordination PR's diff holds an entry for every node, and a node PR in a second repository carries `Plan: owner/repo:docs/plans/PLAN-<topic>.md (<entry key>)` in Part 1.
- [ ] A session name, `seq`, entry key or PR reference outside the allowed patterns is refused before any koto, git or gh call.
- [ ] In the `/execute` single-pr and `/work-on` multi-pr fixtures, each entry appears in a commit on the branch of the PR it names before that PR's ready event, and Part 1 of each PR body carries `Plan: docs/plans/PLAN-<topic>.md (<entry key>)`.

**Dependencies**: Blocked by Issue 1.

---

---

### Issue 4: feat(cascade): keep the plan at Done in its landing PR

**Complexity**: critical

**Goal**: The completion cascade marks the plan Done and keeps it, rewrites a roadmap upstream to the roadmap's parent, writes the design's `plan:` field and repoints the plan's design upstream, runs only in the landing PR, and `FC23` checks the Run Record.

**Acceptance Criteria**:
- [ ] `run-cascade_test.sh` has a scenario per execution mode and plan version in which the plan is present at `status: Done` after the cascade and no cascade commit deletes it; a second run makes no commit.
- [ ] `verify-cascade-commit.sh` passes on a kept Done plan and fails on a deleted one.
- [ ] `shirabe finalize-chain` JSON for a chain rooted at a plan lists the plan with `transition_plan` to `Done` and no `delete_plan` action, and `run-cascade.sh` accepts it.
- [ ] A coordinated fixture whose cascade has pushed, with the plan kept at Done, does not run the cascade again (`coord-common.sh` reads `run/cascade`, not the plan file's presence).
- [ ] With a dropped step and an issue closed with a `no-change` outcome, `landing` for the last open issue exits 0 and the landing run writes `PRs: none (dropped)` and `PRs: none (no-change)` for them; `### Plan` is never counted.
- [ ] After the cascade on a fixture plan naming a roadmap, its `upstream:` names the roadmap's strategy, its Status prose names the roadmap, the design at Current has `plan:` naming the plan, and after the roadmap is deleted the plan validates.
- [ ] In a three-issue `multi-pr` fixture the plan is Active after the first two PRs and Done in the third PR's diff; `plan-record.sh landing` exits 2 on an unreadable plan and `cascade_entry` routes that to `done_blocked`.
- [ ] With issue 2's entry still missing from the default branch, `landing` for issue 3 exits 1 and the cascade does not run.
- [ ] In an in-flight fixture whose issues 1 and 2 were closed before the change with no entries, `landing` for issue 3 exits 0, the landing run writes entries for issues 1 and 2 citing each closing PR with `Decisions: none recorded.`, and the plan ends Done.
- [ ] `FC23` fails a Run Record line outside the entry grammar on an Active or Done plan, and every eval and test that asserted deletion now asserts the kept plan.

**Dependencies**: Blocked by Issue 2, Issue 3.

---

---

### Issue 5: feat(plan): check a kept plan's record against its PRs and sessions

**Complexity**: testable

**Goal**: `check-plan-record.sh <plan>` compares every recorded decision with its PR copy and, where the session is retained, with the cited event.

**Acceptance Criteria**:
- [ ] Exits 0 on the Issue 3 fixture plan.
- [ ] Exits 1 naming the entry when a plan reason is edited, when a citation's `seq` points at another event, or when a `PRs:` line holds a bare `#N`.
- [ ] Prints `session not retained: <session>` and still exits 0 when the cited session is absent; exits 2 when a named PR can't be read.
- [ ] Prints only citations and entry keys for a mismatch, never PR body text.
- [ ] Exits 1 when a line holding a token was hand-edited into both the plan and the PR copy, because it re-runs the filters.
- [ ] Reports, and still exits 0 for, a decision in a retained session that the plan does not carry.

**Dependencies**: Blocked by Issue 3.

---

---

### Issue 6: docs: state the kept-plan lifecycle everywhere

**Complexity**: simple

**Goal**: Every document PRD R19 lists states the kept lifecycle in its one sentence, and none says a plan is deleted at completion.

**Acceptance Criteria**:
- [ ] Each document PRD R19 lists contains the R19 sentence (`grep -F`), and none matches `-> DELETED` or `git rm` followed on the same line by `PLAN`.
- [ ] `skills/design/references/design-format.md` documents the `plan:` field and who writes it.
- [ ] `docs/designs/current/DESIGN-completion-cascade.md` carries a dated note pointing to the kept-plan design.

**Dependencies**: Blocked by Issue 4, Issue 5.

## Implementation Sequence

Issue 1 first. Issues 2 and 3 follow in either order; both need only Issue 1.
Issue 4 needs both, because the cascade only marks a plan Done once the record
writer exists and the lookups already skip Done plans. Issue 5 follows Issue
3, and Issue 6 closes the plan once Issues 4 and 5 have landed, so the
references describe behaviour that exists. The critical path is 1, 3, 4, 6.
