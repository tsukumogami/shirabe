---
schema: plan/v1
status: Active
execution_mode: single-pr
tracking_level: none
upstream: docs/designs/DESIGN-scope-then-execute.md
milestone: "Scope-then-execute delivery"
issue_count: 12
---

# PLAN: scope-then-execute

## Status

Active

Authored at Active: tracking level `none`, so activation creates no GitHub
artifacts. All twelve issues land in one pull request.

## Scope Summary

This PLAN implements `docs/designs/DESIGN-scope-then-execute.md`: a caller
declares intent when launching the tactical chain, and every run under that
intent ends in a named state. `/plan` gains `--intent` and the coordination
flags and emits `coordinated` on a split when the caller will continue into
execution; coordinated mode works inside one repository with a branch and PR
per PR node; `/scope --intent` publishes one PR and prints machine-readable
exit lines; `/execute --merge` merges only what the repository's own rules
would let an ordinary contributor merge, confirmed by a live read; and a new
stateless `/deliver` skill runs `/scope --intent=continue` then `/execute`.
Plain `/scope`, `/plan`, and `/execute` runs without the new flags behave as
today apart from corrected next-step advice and wording.

## Decomposition Strategy

Horizontal, following the DESIGN's provider-first Implementation Approach:
shared references first (Issue 1), then `/plan` (Issues 2-3), the `/execute`
merge scripts and single-pr merge path (Issues 4-5), the coordinated path in
one repository (Issue 7), the wording pass written against both final
`/execute` texts (Issue 6), the validator tests (Issue 8), `/scope` intent and
publish (Issues 9-10), and finally `/deliver` (Issue 11) and the user guides
(Issue 12). Components share explicit, stable interfaces (flags going down,
`key=value` exit lines coming back), so building each layer fully before its
consumers is lower risk than a thin skeleton across five skills. Each issue
ships its own eval scenarios naming the PRD requirement IDs it covers.

Grouping rules: one issue per skill surface or script pair, split where a
DESIGN phase held independent deliverables (`/plan` flags vs
`plan-to-tasks.sh`, merge scripts vs koto wiring, `/scope` intent vs publish).

## Issue Outlines

### Issue 1: docs(references): update shared contracts for intent, single-repo coordinated, and opt-in merge

**Goal**: Update the shared references (coordination strategy, parent-skill state schema, parent-skill pattern, child inspection) and the draft/ready discipline design so they state the scope-then-execute contracts every later issue reads: coordinated in one or more repositories, the four-level split-mode precedence, a single coordinated-by-default header definition, a branch per PR node, an opt-in agent merge, and a parent-of-the-parent binding.

**Context**: This is Phase 1 (Shared contracts) of the design, and the Components > Shared references list under Solution Architecture. Every other skill change in the plan binds to these files, so they change first.

Today the references contradict the feature in five places:

- `references/coordination-strategy.md` says a coordinated effort "spans more than one repository" (line 27), is titled "The Coordinated Multi-Repo Contract", groups "one PR per repository" by default, has the lifecycle create the coordination PR up front in all cases, says the coordination PR "stays draft until it merges last", and its body-template blockquote reads "for a coordinated multi-repo effort". PRD R6 drops the multi-repo-only restriction. PRD R9 has intent runs open the coordination PR at `/scope` exit instead of up front. PRD R19-R22 add an agent merge and a `paused-awaiting-merges` pause.
- No file pins which `## PR Grouping Policy:` / `## Reviewability Ceiling:` values mean "coordinated by default". `skills/scope/SKILL.md` (Coordination Intent) names the headers but not their values; `docs/guides/coordinated-multi-repo.md` shows `coarsest-legal` and `default` as examples only. Design Decision 1 assumes one definition in `coordination-strategy.md` that both `/scope` and `/plan` read.
- `references/parent-skill-state-schema.md` lists `plan_execution_mode` values as `single-pr | multi-pr` (Field Semantics, around line 90, and again in the chain-tracking paragraph around line 234). PRD R25 requires `coordinated`.
- `docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md` (The Discipline) says "The agent marks ready; the human merges" with no opt-in exception, and its coordination-PR exception says the PR stays draft until it merges last. The design's Decision 3 adds `/execute --merge`, and the coordinated loop marks the coordination PR ready once every indexed PR has merged.
- `references/parent-skill-pattern.md` mentions the parent-of-the-parent only in the team-shape material; nothing binds a skill that sequences two parents. `references/parent-skill-child-inspection.md`'s Per-Parent Surface Table has no row for a parent dispatched by that driver. Design Decision 4 makes `/deliver` fill that slot, reading only frontmatter and printed exit lines.

The Rust validator matches only the fixed prefix `This is a **coordination PR**` (`COORDINATION_DECLARATION_MARKER` in `crates/shirabe-validate/src/coordination.rs`), so the blockquote wording can change after that prefix without a code change. Test fixtures that embed the old blockquote (`crates/shirabe/tests/coordination_body.rs`, `coordination.rs` tests) belong to Issue 8, not here.

**Acceptance Criteria**:

*`references/coordination-strategy.md`*

- [ ] `grep -in 'multi-repo\|more than one repository' references/coordination-strategy.md` returns no match. The title, the opening paragraph, and The Coordinated Mode section describe a coordinated effort as spanning one or more repositories (PRD R6, R8).
- [ ] The Coordination PR Body Template blockquote begins with the unchanged prefix `> This is a **coordination PR**` and no longer contains "multi-repo" (PRD R6; PRD AC "the body's declaration marker doesn't say multi-repo").
- [ ] The Coarsest-Legal-Grouping Rule states that in a single-repository coordinated PLAN each split unit is its own `pr_group`, so the unit of grouping is the `(repo, pr_group)` node rather than the repository, while a multi-repo PLAN with `Group: default` still gets one PR per repository (PRD R6, R8).
- [ ] A section states the split-mode precedence in this exact order: explicit `--coordinated` / `--no-coordinated`, then `--intent` (`continue` resolves to `coordinated`; `stop` or absent resolves to `multi-pr`), then a coordinated-by-default CLAUDE.md header, then the default `multi-pr`. It states that precedence applies only when the work splits, and that an unsplit PLAN is `single-pr` regardless of intent or flags (PRD R4, R5, Interfaces precedence rule).
- [ ] The same file holds the single definition of which `## PR Grouping Policy:` and `## Reviewability Ceiling:` header values mean coordinated by default, as an explicit list of header/value pairs, and says any other value or an absent header does not. The file says `/scope` and `/plan` both read this definition and neither restates it (design Decision 1 key assumption).
- [ ] A Branches paragraph states: one branch per PR node, named `impl/<slug>-<node-id>`, cut from the default branch (never from the coordination branch or a predecessor's branch), with one PR per node (PRD R6; design Decision 2).
- [ ] The Lifecycle section's "Create up front" phase states that when `--intent` is set the coordination PR is not created up front but opened by `/scope` at exit once the PLAN's mode is known, and that runs without intent keep today's up-front creation (PRD R9, R2).
- [ ] The Lifecycle section includes a merge step: with `--merge`, `/execute` merges each node PR only after all its merge-order predecessors have merged, and the coordination PR last (PRD R21).
- [ ] The Lifecycle section defines the `paused-awaiting-merges` pause: the run ends with the coordination PR left open, and a later `/execute` or `/deliver` on the same PLAN resumes from the coordination PR's index and merge-order block (PRD R22).
- [ ] The draft rule for the coordination PR matches the amended draft/ready design: it stays draft until every indexed PR has merged, then `/execute` marks it ready. The phrase "stays draft until it merges last" no longer appears in this file.

*`references/parent-skill-state-schema.md`*

- [ ] Every place that lists `plan_execution_mode` values reads `single-pr | multi-pr | coordinated` (both the Field Semantics bullet and the chain-tracking paragraph); every line matched by `grep -n 'single-pr | multi-pr' references/parent-skill-state-schema.md` also contains `coordinated` (PRD R25).
- [ ] The Parent-specific conditional fields section adds a note that a parent may declare an always-present invocation-intent field (such as `/scope`'s `intent: continue|stop|none`), and says that field is exempt from conditional-field gating because it is always present (PRD R3).

*`docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md`*

- [ ] The Discipline section gains an "Opt-in agent merge" paragraph stating that the agent merges only when the caller passes `--merge` to `/execute` (on by default under `/deliver`, off with `--no-merge`), only when the repository's own protection allows it, and never with an administrator or bypass option. It says direct `/execute` without `--merge` keeps "the agent marks ready; the human merges" (PRD R19, R20; design D3).
- [ ] The coordination-PR exception is amended so the coordination PR stays draft until every indexed PR has merged, after which `/execute` marks it ready. The phrase "stays draft until it merges last" no longer appears in this file.
- [ ] The file's frontmatter `status:` stays `Current`, and `shirabe validate` on the file exits 0.

*`references/parent-skill-pattern.md`*

- [ ] A subsection titled "Parent-of-the-Parent Binding" states that a driver skill may sequence two parent skills through inline Skill calls. The driver keeps no koto template or state file, passes each parent only flags that parent documents for direct use, reads only what the child-inspection surface table allows, and makes no parent invoke another parent (design D1, Decision 4; PRD R13).

*`references/parent-skill-child-inspection.md`*

- [ ] The Per-Parent Surface Table gains a row for a parent dispatched by the parent-of-the-parent. Its status surface is the parent's terminal artifact frontmatter plus its printed `key=value` exit lines. The row states the dispatched parent's state file is internals (design Decision 4).

*Downstream deliverables*

- [ ] Must deliver: the split-mode precedence and the coordinated-by-default header/value definition in `references/coordination-strategy.md` (required by Issue 2).
- [ ] Must deliver: the Branches paragraph and "one or more repositories" wording that defines a PR node as `(repo, pr_group)` with its own branch, which the `REPO` / `PR_GROUP` / `ISSUES` node vars describe (required by Issue 3).
- [ ] Must deliver: the "Opt-in agent merge" paragraph and the amended coordination-PR exception in the draft/ready design (required by Issue 4).
- [ ] Must deliver: the coordination body template blockquote without "multi-repo" after the unchanged prefix, which single-repo validator tests use as their fixture text (required by Issue 8).

**Dependencies**: None

**Type**: docs

### Issue 2: feat(plan): add --intent and coordination flags and emit coordinated on a split

**Goal**: Give `/plan` its own `--intent=continue|stop`, `--coordinated`, and `--no-coordinated` flags, resolve a split's mode (`coordinated` or `multi-pr`) by precedence in a new step 5a backed by a deterministic `resolve-split-mode.sh`, tag coordinated issues with Repo/Group rows, file them through a coordinated creation branch with an explicit filing approval, and route next-step advice by mode.

**Context**: Today `/plan` never writes `execution_mode: coordinated`. Step 3.6 of `references/phases/phase-3-decomposition.md` has only two outcomes, `/plan` doesn't parse `--coordinated`/`--no-coordinated` or read the CLAUDE.md coordination headers, and `references/phases/phase-7-creation.md` has no coordinated branch. `/scope` hands the `/plan` hop only the DESIGN path and `--upstream`, so neither caller intent nor the coordination flags can influence the mode. And `/plan`'s closing advice for a `single-pr` PLAN still names `/work-on` (phase-7 steps 7.2 and 7.7).

The design keeps the split question exactly as it is (does the work split, and on which branch, recorded in `split_branch`/`split_rationale`) and adds a second question that runs only when the work splits: step 5a picks the mode by the precedence explicit coordination flag > `--intent` > coordinated-by-default CLAUDE.md header > `multi-pr`, recording `split_mode_source: flag|intent|header|default`. Because the split is decided before intent is consulted, intent can't change the split reason (R4). The flags are child-owned and documented for direct use, which is what lets `/scope` forward them without breaking the parent-skill rule (D1). A no-intent, no-flag run must behave as today (D2, R2).

This issue covers the `/plan` surface only. The `plan-to-tasks.sh` node vars (`REPO`, `PR_GROUP`, `ISSUES`) belong to Issue 3; the shared precedence and header definition come from Issue 1.

Design: `docs/designs/DESIGN-scope-then-execute.md` (Considered Options > Decision 1; Solution Architecture > Components > `/plan`; Implementation Approach > Phase 2)
PRD: `docs/prds/PRD-scope-then-execute.md` (R4, R5, R6, R7, R8, R23, R26, R27)

**Acceptance Criteria**:

*Flags and rejection (`skills/plan/SKILL.md`)*

- [ ] `skills/plan/SKILL.md` Context Resolution > "1. Parse Flags" documents `--intent=continue|stop`, `--coordinated`, and `--no-coordinated` as flags usable on a direct `/plan` run, and the frontmatter `argument-hint` lists all three (R5).
- [ ] The Parse Flags text states that an `--intent` value other than `continue` or `stop`, a repeated `--intent` (e.g. `--intent=stop --intent=continue`), or `--coordinated` together with `--no-coordinated` is rejected with an error naming the offending flag before any `/plan` working file for the topic is written (Interfaces table, `/plan` row).
- [ ] The `### Coordinated Mode (multi-repo)` heading in `skills/plan/SKILL.md` is renamed to `### Coordinated Mode`, and neither that subsection nor the "Execution Mode Decision" section states that coordinated requires, or is the generalization for, more than one repository (R6; PRD AC "coordination-strategy.md and /plan's coordinated-mode section contain no statement that coordinated requires more than one repository").
- [ ] `skills/plan/SKILL.md` "Execution Mode Decision" gains a "Split mode" rule that names the four-level precedence (explicit `--coordinated`/`--no-coordinated` > `--intent` > coordinated-by-default header > `multi-pr`), states `continue` resolves to `coordinated` and `stop`/none to `multi-pr`, states a non-split is `single-pr` regardless of intent or flags, and binds to `${CLAUDE_PLUGIN_ROOT}/references/coordination-strategy.md` for the header values rather than restating them (R5, R8).
- [ ] `skills/plan/SKILL.md` "### Output" lists a coordinated-mode entry (PLAN with `execution_mode: coordinated`, per-PR-group issues filed with Repo/Group rows).

*Step 5a and group rows (`references/phases/phase-3-decomposition.md`)*

- [ ] Step 3.6's procedure keeps steps 1-5 (split decision, `split_branch`, `split_rationale`) unchanged in meaning, and a new step labelled 5a runs only when step 4 recommended a split; it resolves `coordinated` or `multi-pr` by the precedence rule and writes `split_mode_source: flag|intent|header|default` to the decomposition frontmatter next to `execution_mode` (R4, R5).
- [ ] Step 5a gets the mode by running `skills/plan/scripts/resolve-split-mode.sh` and copying its output; the phase text says the agent must not resolve the precedence itself and must not override the script's answer except through the step 6 interactive override, which re-runs the script with the override as `--split yes|no`.
- [ ] `resolve-split-mode.sh --split <yes|no> [--intent <continue|stop|none>] [--coordinated|--no-coordinated] [--claude-md <path>]` prints exactly two lines, `execution_mode=<single-pr|multi-pr|coordinated>` and `split_mode_source=<none|flag|intent|header|default>`, and exits 0. `--split no` always prints `single-pr` with source `none`, whatever the other arguments (R5's no-split clause).
- [ ] With `--split yes`, the script applies explicit flag > `--intent` > coordinated-by-default header > `multi-pr`, reading the header values from the definition Issue 1 writes into `references/coordination-strategy.md` (the script carries the same value list as a constant, and its test fails if the two lists differ).
- [ ] The script rejects, with a non-zero exit, an empty stdout, and a stderr line naming the argument: a missing or invalid `--split`, an `--intent` value outside `continue|stop|none`, a repeated flag, both coordination flags together, and a `--claude-md` path that doesn't exist. It never reads the network or `gh`, and runs under the repo's bash 3.2 floor.
- [ ] `skills/plan/scripts/resolve-split-mode_test.sh` covers every row of the precedence as a table: `--split no` with each combination of intent and flags; `--split yes` with an explicit flag beating a contrary intent and header (`--no-coordinated --intent continue`, and `--coordinated --intent stop` with a non-coordinated header); intent beating a coordinated header (`--intent stop` with a coordinated-by-default header gives `multi-pr`, source `intent`); a header alone (source `header`); and nothing at all (`multi-pr`, source `default`). It also covers each rejection case. The test is wired into the CI workflow that runs the other `skills/plan/scripts/*_test.sh` files.
- [ ] Step 3.6 states explicitly that `--intent` and the coordination flags are not read by steps 1-5, so `split_branch` for a given DESIGN is identical under `--intent=continue`, `--intent=stop`, and no intent (R4).
- [ ] Step 5a also runs after the interactive override in step 6 (when the confirmed mode is a split) and on roadmap input (whose split branch is Incremental Value), resolving the mode by the same precedence.
- [ ] The step-8 frontmatter example and the step 3.5/3.R4 templates show `execution_mode: <single-pr | multi-pr | coordinated>`, and the step-6 AskUserQuestion text lists `coordinated` as an option when the work splits.
- [ ] When step 5a resolves `coordinated`, phase-3 instructs that every issue outline carries `_Repo: <owner/repo> | Group: <unit-slug>_`, with `<owner/repo>` the current repository and one distinct group slug per split unit, so a single-repo split yields at least two groups (R6).

*Issue bodies and creation (phases 4 and 7)*

- [ ] `references/phases/phase-4-agent-generation.md` "## Execution Mode" and step 4.4 list `coordinated`, and state that coordinated issues get full issue bodies (same as multi-pr), with step 4.7's multi-pr validation applied to them.
- [ ] `references/phases/phase-7-creation.md` gains a coordinated-mode section (listed in its Table of Contents) that files issues by reusing `${CLAUDE_SKILL_DIR}/scripts/create-issues-batch.sh`, and writes the PLAN with `execution_mode: coordinated`, `split_mode_source`, and the Repo/Group annotation rows in the Implementation Issues table (R7).
- [ ] The coordinated section runs an explicit filing approval before the first `gh issue create`: interactively it asks via AskUserQuestion; under `--auto` it resolves by `references/decision-protocol.md` and records a decision block in `/plan`'s decisions file without blocking (R7).
- [ ] The existing multi-pr creation branch (steps 7.1-7.4) is unchanged in behavior; the approval step exists only in the coordinated branch (D2).
- [ ] Phase-7 step 7.2 "Suggest Next Steps" and the 7.7 single-pr summary name `/execute docs/plans/PLAN-<topic>.md`; the 7.7 summary for coordinated names `/execute docs/plans/PLAN-<topic>.md`; the multi-pr summary names `/work-on` with the first dependency-free issue (R23).

*gh shim and evals*

- [ ] A new executable `skills/plan/evals/fixtures/bin/gh` exists that serves canned responses per `EVAL_SCENARIO` and appends every invocation's arguments, one per line, to a call log (path from an env var such as `GH_CALL_LOG`), so a scenario can count `issue create` calls (R26).
- [ ] Fixtures exist under `skills/plan/evals/fixtures/`: a forced-split single-repo DESIGN (split forced by a Hard Constraint stated in the DESIGN), a no-split DESIGN small enough that no branch fires, and a multi-repo DESIGN (R26).
- [ ] `skills/plan/evals/evals.json` gains scenarios, each naming the requirement IDs it covers in its name or expectations, asserting:
  - [ ] `/plan <forced-split> --intent=continue` produces `execution_mode: coordinated` with every group's `Repo` equal to the one repository and at least two distinct `Group` values; `--intent=stop` produces `multi-pr` (R5, R6).
  - [ ] On the forced-split DESIGN, `split_branch` is the same for `--intent=continue`, `--intent=stop`, and no intent (R4).
  - [ ] On the no-split DESIGN, `--intent=continue`, `--intent=stop`, and no intent all produce `single-pr` (R5).
  - [ ] `--intent=continue --no-coordinated` on the forced-split DESIGN produces `multi-pr` with `split_mode_source: flag`; `--intent=stop --coordinated` on the multi-repo DESIGN produces `coordinated` with `split_mode_source: flag` (R5, R8).
  - [ ] With a CLAUDE.md fixture whose coordination header resolves to coordinated, the forced-split DESIGN with `--intent=stop` produces `multi-pr` and with no intent produces `coordinated` (`split_mode_source: header`) (R5, R8).
  - [ ] `--auto --intent=continue` on the forced-split DESIGN logs one `issue create` per issue across the PR groups in the shim log and the transcript contains no approval question (R7).
  - [ ] Interactive `--intent=continue` on the forced-split DESIGN asks the filing-approval question before the first `issue create` line appears in the shim log (R7).
  - [ ] `/plan <design> --intent=bogus`, `--intent=stop --intent=continue`, and `--coordinated --no-coordinated` each end with an error naming the flag and leave no `/plan` working file for the topic (Interfaces).
  - [ ] Closing advice names `/execute` for a `single-pr` and a `coordinated` PLAN and `/work-on` for a `multi-pr` PLAN (R23).
- [ ] Existing eval 5 (`single-pr-execution-mode`) and eval 7 (`auto-mode-non-interactive`) still pass unchanged; eval 26 (`coordinated-rule-surface-binds-not-restates`) and eval 24 (`coordinated-mode-per-repo-grouping-two-node-dag`) are edited only where they assert "Coordinated Mode (multi-repo)" or "multi-repo generalization" text, and all existing `/plan` evals pass (R27).
- [ ] Each new scenario passes with `--runs 3` (R26).

*Downstream deliverables*

- [ ] Must deliver: `/plan` accepts `--intent=continue|stop`, `--coordinated`, `--no-coordinated`, and `--auto` in any order after the DESIGN path, documented in `skills/plan/SKILL.md` as direct-use flags, so `/scope` can forward them verbatim (required by Issue 9).
- [ ] Must deliver: an invalid or repeated `--intent`, or both coordination flags together, produces an error naming the flag before any `wip/` write, so a forwarded bad value surfaces as a `/plan` refusal (required by Issue 9).
- [ ] Must deliver: a no-intent, no-coordination-flag `/plan` invocation produces the same mode and artifacts as today, so `/scope`'s unchanged no-intent hop keeps its behavior (required by Issue 9).

**Dependencies**: Issue 1

**Type**: code

### Issue 3: feat(plan): emit repo, group, and issue vars per PR node in plan-to-tasks

**Goal**: Make `skills/plan/scripts/plan-to-tasks.sh` emit `REPO`, `PR_GROUP`, and `ISSUES` for every coordinated PR node, reword its unschedulable refusal to "atomicity across PR groups", and cover a single-repo, two-group coordinated PLAN in `plan-to-tasks_test.sh` and `references/plan-to-tasks-contract.md`.

**Context**: Decision 2 of the design makes the PR node, not the repository, the unit of branching for a coordinated PLAN, so a coordinated PLAN can live in one repository with one PR group per split unit (PRD R6). `plan-to-tasks.sh` already keys PR nodes on `(repo, pr_group)` in `process_coordinated`, so two groups in one repo are already two nodes and contraction, Kahn ordering, and `split_repo_at_seam` work unchanged. What's missing is the data a consumer needs per node: today each node entry carries only `vars.NODE_KIND`, so `/execute`'s coordinated loop would have to re-parse the PLAN's Implementation Issues table to learn which repository to branch in, which group the node is, and which issues to dispatch. The design's Components list for `/plan` asks for exactly three new node vars (`REPO`, `PR_GROUP`, `ISSUES`) plus refusal text saying "atomicity across PR groups", since "cross-repo atomicity" is wrong once all groups can sit in one repository.

This is part of Phase 2 ("`/plan` emits both multi-PR modes"), whose deliverables include `plan-to-tasks.sh`, its test, and the contract doc. The coordinated loop that consumes these vars (per-node `impl/<slug>-<node-id>` branches, PRs, merges in merge order) comes later and must not need to read the PLAN table itself. Multi-repo PLANs with `Group: default` must keep one node per repo and behave as today (R8), and the single-pr and multi-pr output shapes must not change (R27).

**Acceptance Criteria**:

Coordinated node vars:

- [ ] In `process_coordinated`, every entry with `vars.NODE_KIND == "pr"` also carries `vars.REPO` (the full `owner/repo` string from the issue's `^_Repo:` annotation, owner kept), `vars.PR_GROUP` (the `Group:` tag as written), and `vars.ISSUES` (the node's GitHub issue numbers as a comma-separated string with no spaces or `#`, in Implementation Issues table order, e.g. `"1,2"`). All three values are JSON strings.
- [ ] Entries with `vars.NODE_KIND == "gate"` carry none of `REPO`, `PR_GROUP`, or `ISSUES`.
- [ ] A node produced by `split_repo_at_seam` (name `pr-<repo-name>-<group>-i<N>`) carries the `REPO` and `PR_GROUP` of the node it was split from and `ISSUES` equal to its single issue number `"N"`.
- [ ] The `ISSUES` sets across all PR nodes partition the PLAN's issues: every issue number in the Implementation Issues table appears in exactly one PR node's `ISSUES`.
- [ ] Node `name` values, the `waits_on` arrays, and the serialized node order are byte-identical to today's output for every existing coordinated fixture in `plan-to-tasks_test.sh` (`test_coordinated_basic`, `test_coordinated_contraction_cycle_resolved`, `test_coordinated_gate_node`); only the added vars differ.

Refusal wording:

- [ ] The `die_schema` message and the preceding `log` line on the irreducible-cycle path in `process_coordinated` say "atomicity across PR groups" and no longer say "cross-repo atomicity"; the message still contains "compatible-intermediate sequence" and still names `references/coordination-strategy.md`. Exit code stays 2 with empty stdout.
- [ ] `grep -n "cross-repo atomicity" skills/plan/scripts/plan-to-tasks.sh skills/plan/references/plan-to-tasks-contract.md` returns no matches (header comment block, exit-code comment, and inline comments included).
- [ ] `test_coordinated_atomicity_refused_pr_nodes` greps the diagnostic for "atomicity across PR groups" and "compatible-intermediate sequence" instead of "cross-repo atomicity".

Unchanged modes:

- [ ] single-pr, multi-pr (`tracking_level` issues/absent), and issueless multi-pr (`tracking_level: none`) output is unchanged: every existing non-coordinated test in `plan-to-tasks_test.sh` passes without edits.

Tests:

- [ ] A new `test_coordinated_single_repo_two_groups` in `plan-to-tasks_test.sh`, registered in the run list at the bottom of the file, uses a coordinated PLAN whose three issues all carry `acme/repo-a` with two groups (for example issues #1 and #2 in `Group: core`, #3 in `Group: cli` depending on #2) and asserts: exit 0; exactly two entries; names `pr-repo-a-core` and `pr-repo-a-cli`; `pr-repo-a-cli.waits_on == ["pr-repo-a-core"]` and `pr-repo-a-core.waits_on == []`; `REPO == "acme/repo-a"` on both; `PR_GROUP` equal to `core` and `cli`; `ISSUES` equal to `"1,2"` and `"3"`.
- [ ] `test_coordinated_basic` also asserts `REPO`, `PR_GROUP`, and `ISSUES` on both nodes (`acme/repo-a`/`default`/`"1"` and `acme/repo-b`/`default`/`"2"`), covering the multi-repo `Group: default` shape (R8).
- [ ] `test_coordinated_gate_node` also asserts the gate entry has no `REPO`, `PR_GROUP`, or `ISSUES` key (`jq 'has("REPO")'` on its `vars` is `false`).
- [ ] `test_coordinated_contraction_cycle_resolved` also asserts each split node's `ISSUES` is its single issue number and its `REPO`/`PR_GROUP` match the original node.
- [ ] `bash skills/plan/scripts/plan-to-tasks_test.sh` exits 0.

Contract doc:

- [ ] The "coordinated vars" table in `skills/plan/references/plan-to-tasks-contract.md` lists `REPO`, `PR_GROUP`, and `ISSUES` with their exact formats, states they appear on PR nodes only, and states the split-node values.
- [ ] The contract's Frontmatter Requirements exit-2 bullet and the "coordinated Mode" processing steps say "atomicity across PR groups" rather than "cross-repo atomicity", and the coordinated section states that the PR groups of one PLAN may all be in one repository.
- [ ] The contract's Examples section gains a coordinated example showing the single-repo two-group input rows and the resulting JSON with all four vars.
- [ ] The contract states that multi-pr entries are emitted in Implementation Issues table order, and that this ordering is part of the contract.

Downstream deliverables:

- [ ] Must deliver: per-PR-node `vars.REPO`, `vars.PR_GROUP`, and `vars.ISSUES` in `plan-to-tasks.sh` coordinated output, documented in the contract, so the coordinated loop can cut `impl/<slug>-<node-id>` and dispatch the node's issues without re-parsing the PLAN (required by Issue 7).
- [ ] Must deliver: an unchanged, documented multi-pr output shape (`name: issue-<N>`, `vars.ISSUE_NUMBER`, `waits_on`) emitted in PLAN table order, so a wrapper can list root issues (`waits_on == []`) in PLAN order (required by Issue 10).

**Dependencies**: Issue 1

**Type**: code

### Issue 4: feat(execute): add merge-verdict and merge-exec scripts

**Goal**: Add `skills/execute/scripts/merge-verdict.sh`, a read-only script that applies the design's merge decision table to one live GitHub snapshot and prints one verdict line, and `skills/execute/scripts/merge-exec.sh`, which recomputes that verdict and makes the repository's single fixed-text `gh pr merge` call, each with a table-driven `_test.sh` that runs on the bash 3.2 floor.

**Context**: Decision 3 puts `/execute`'s opt-in merge behind two scripts so that the check and the action can disagree: `merge-verdict.sh` only reads, and `merge-exec.sh` only merges after a fresh verdict it computed itself says the PR is mergeable at the exact commit the run expects. The PRD's R19 and R20 define when a merge is allowed, and the design turns them into the 19-row decision table under Key Interfaces. The Security Considerations section depends on these scripts being the whole enforcement surface at skill level: one merge call site, no `--admin` or `--auto`, closed-pattern validation of every value, `--match-head-commit` on the call, and `merged` reported only after a live read says `MERGED`. Rows 12 to 14 read the base's requirements directly rather than trusting `mergeStateStatus`, so a token that could bypass protection still can't merge what an ordinary contributor couldn't.

The interface is pinned in Key Interfaces > Script interfaces and must be implemented exactly: both scripts take everything they decide on as command-line arguments, and neither reads koto context, a state file, or stdin. The caller (`/execute`) reads the expected head from its own durable record (see Expected-head record) and computes the combined merge intent before calling. Because the scripts hold no state, the CI deadline and the no-checks grace window are anchored on a GitHub-sourced time, the head commit's `committedDate` from the same PR snapshot, so a resumed run never depends on bookkeeping the script can't see.

This issue delivers only the scripts and their tests. Wiring them into the single-pr koto template, the write-set declaration, and the eval `gh` shim is Issue 5's; calling them per node on the coordinated path is Issue 7's.

**Acceptance Criteria**:

Interface and input handling:

- [ ] `merge-verdict.sh` accepts exactly `--repo <owner/repo> --pr <n> --merge <true|false> --expected-head <sha|none> [--confirm]` in any order; a missing required flag, an unknown flag, a repeated flag, or a value outside its pattern exits non-zero with empty stdout, a usage message on stderr, and no `gh` call logged.
- [ ] Closed patterns, applied in both scripts before any `gh` call: repository `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`, PR `^[1-9][0-9]*$`, `--merge` exactly `true` or `false`, expected head `^[0-9a-f]{40}$` or the literal `none`, method `squash`, `merge`, or `rebase`. Tests cover `0`, `012`, `1;rm`, a 39-character sha, an uppercase sha, and `owner/repo/extra`, each rejected.
- [ ] Neither script reads stdin, koto context, or any file under `wip/` or `~/.koto`: a test runs each with stdin closed (`</dev/null`) and with `koto` absent from `PATH` and gets the same verdicts, and `grep -E 'koto|wip/|read -|/dev/stdin'` over both scripts' non-comment lines finds nothing.
- [ ] On success, `merge-verdict.sh` prints exactly one line to stdout, the verdict, and exits 0; every diagnostic goes to stderr.
- [ ] `EXECUTE_CI_WAIT_LIMIT_SECS` is honored only when it matches `^[0-9]+$` and lies in 1..86400; any other value (empty, `abc`, `-5`, `0`, `99999999`) falls back to 1800 s, and a test shows each fallback.

Decision table (one test case per row, first match wins, each asserted against the exact verdict string):

- [ ] Row 1: `state MERGED` prints `merged`.
- [ ] Row 2: `state CLOSED` prints `error:execute:pr-closed`.
- [ ] Row 3: `isDraft true` prints `error:execute:ready`.
- [ ] Row 4: `mergeStateStatus DIRTY` prints `awaiting:merge-state:DIRTY`, even when checks are failing (row 4 outranks row 5).
- [ ] Row 5: any check in the `fail` or `cancel` bucket prints `error:execute:ci`, with `--merge false` and with `--merge true`.
- [ ] Row 6, check buckets follow `scripts/ci-gate-expression_test.sh`: `pass` and `skipping` count as succeeded; `pending` and any unrecognized bucket (a test uses `weird`) count as pending, never as passed. A pending check within the deadline prints `pending:checks`.
- [ ] Row 6, required-but-unreported: with `--merge true` and a base whose rules require a check named `build` that is absent from `gh pr checks` output while every reported check passed, the verdict is `pending:checks`.
- [ ] Row 6, grace window: zero checks and a head `committedDate` 60 s old prints `pending:checks`.
- [ ] Row 6, deadline: a pending check with a head `committedDate` older than the wait limit prints `error:execute:ci-timeout`; with `EXECUTE_CI_WAIT_LIMIT_SECS=300` and a 400 s-old head the same fires, and with a 200 s-old head it prints `pending:checks`.
- [ ] Row 7: `--merge false` on an otherwise mergeable PR prints `awaiting:merge-not-requested`, and the call log shows no read of `repos/<repo>/branches/<base>`, `repos/<repo>/rules/branches/<base>`, or the repository's allowed merge methods.
- [ ] Row 8: `--expected-head none`, and separately an expected head that differs from `headRefOid`, each print `awaiting:head-moved`.
- [ ] Row 9: zero checks and a head `committedDate` older than 120 s print `awaiting:no-checks`.
- [ ] Row 10: `mergeStateStatus UNKNOWN` prints `pending:merge-state` within the deadline and `awaiting:merge-state:UNKNOWN` past it.
- [ ] Row 11: `BLOCKED`, `BEHIND`, `UNSTABLE`, and `HAS_HOOKS` each print `awaiting:merge-state:<S>`; `BLOCKED` with `reviewDecision REVIEW_REQUIRED` prints `awaiting:merge-state:BLOCKED:review=REVIEW_REQUIRED`; `CLEAN` with `reviewDecision CHANGES_REQUESTED` prints `awaiting:merge-state:CLEAN:review=CHANGES_REQUESTED`.
- [ ] Row 12: with both protection sources empty (classic endpoint reports `protected: false`, rules endpoint returns `[]`), the verdict is `awaiting:base-unprotected`; with the classic endpoint returning 404 and the rules endpoint failing, the verdict is also `awaiting:base-unprotected` (an unreadable source counts as unprotected, not as an error).
- [ ] Row 13: a rules-endpoint `pull_request` rule with `required_approving_review_count >= 1` on a `CLEAN` PR whose `reviewDecision` is empty prints `awaiting:review` (a `REVIEW_REQUIRED` decision never reaches this row, because row 11 catches it first).
- [ ] Row 14: a PR on a checks-only base whose files include a path under `.github/workflows/`, and separately `.github/actions/`, and separately `CODEOWNERS`, `.github/CODEOWNERS`, or `docs/CODEOWNERS`, with `reviewDecision` not `APPROVED`, prints `awaiting:workflow-change`; the same PR with `APPROVED` reaches row 16.
- [ ] Row 15: when the repository's allowed-method read fails or reports no method allowed, the verdict is `awaiting:merge-method-unresolved`.
- [ ] Row 16 method choice: only rebase allowed gives `mergeable:rebase:<sha>`; only merge commits gives `mergeable:merge:<sha>`; squash plus merge gives `mergeable:squash:<sha>`; merge plus rebase (no squash) gives `mergeable:merge:<sha>`. `<sha>` is the live `headRefOid`.
- [ ] Row 12 protection sources, each alone sufficient: (a) a base protected only by classic branch protection's required status checks (`repos/<repo>/branches/<base>` reports `protected: true` with a non-empty `protection.required_status_checks` context or check list, rules endpoint returns `[]`) prints `mergeable:<method>:<sha>` on an otherwise mergeable PR; the same fixture with the classic endpoint changed to `protected: false` prints `awaiting:base-unprotected`. (b) a base protected only by a ruleset's `required_status_checks` rule with a non-empty `parameters.required_status_checks` list (classic endpoint `protected: false`, and in a second case a 404) prints `mergeable:<method>:<sha>`; the same fixture with the rules endpoint returning `[]` prints `awaiting:base-unprotected`.
- [ ] A PR view or checks read that fails on every attempt (the script may retry up to 3 times) prints `error:execute:status-read`. A `gh pr checks` exit that means "no checks reported" is read as zero checks, and its pending exit code (8) with valid JSON is read as the JSON says, not as a read failure; tests cover both.

Confirm mode (rows 17 to 19):

- [ ] `--confirm` reads only the PR state, re-reading until `MERGED` or until a 20 s window elapses. It prints `merged` if a read reports `MERGED` and `not-merged:merge-not-observed` otherwise; it evaluates no other row. Tests may shorten the window through `MERGE_CONFIRM_WAIT_SECS`, honored only in 0..20 (it can narrow the window, never widen it).
- [ ] A shim that reports `OPEN` twice and then `MERGED` gives `merged`; one that reports `OPEN` throughout gives `not-merged:merge-not-observed`.

`merge-exec.sh`:

- [ ] Usage is exactly `merge-exec.sh <owner/repo> <pr> <expected-head>`; any other argument count, or a value outside the closed patterns, exits non-zero with empty stdout and no `gh pr merge` logged. There is no flag parsing and no pass-through of extra arguments.
- [ ] It runs `merge-verdict.sh --repo <repo> --pr <pr> --merge true --expected-head <expected-head>`, locating that script by its own directory (not `PATH`), so a `merge-verdict.sh` placed earlier on `PATH` in a test is never run.
- [ ] Unless the fresh verdict is exactly `mergeable:<method>:<expected-head>`, it prints `merge-refused:<verdict>` and exits 0 without calling `gh pr merge`. Tests cover a fresh `awaiting:head-moved`, `awaiting:base-unprotected`, `pending:checks`, `merged`, and a `mergeable:squash:<other-sha>` whose sha doesn't equal the expected head.
- [ ] On a mergeable verdict it makes exactly one call, byte-for-byte `gh pr merge <pr> --repo <repo> --<method> --match-head-commit <expected-head>`, and prints `merge-called:<method>:<expected-head>` when that call exits 0.
- [ ] When the merge call exits non-zero it prints `merge-refused:not-merged:merge-call-failed`, logs exactly one `pr merge` call, and makes no second attempt with another method or option.
- [ ] End-to-end: merge-exec's `gh pr merge` exits 0 but the following `merge-verdict.sh --confirm` read still reports `OPEN`; merge-exec prints `merge-called:<method>:<sha>` and the confirm prints `not-merged:merge-not-observed`. The test asserts that neither output line is `merged`.
- [ ] No logged `pr merge` call in any test carries `--admin`, `--auto`, or `--delete-branch`.
- [ ] A grep test asserts the string `gh pr merge` appears on exactly one non-comment line across every `*.sh` file (excluding `*_test.sh`), every `.github/workflows/*.yml`, and every `command:` or `default_action` line in `skills/*/koto-templates/*.md`, and that line is in `skills/execute/scripts/merge-exec.sh`.

Tests and CI:

- [ ] `skills/execute/scripts/merge-verdict_test.sh` and `merge-exec_test.sh` drive the scripts through a test-local `gh` stub on `PATH` that serves per-case JSON fixtures and appends every invocation to a call log; cases are table-driven, one row per verdict above.
- [ ] Date arithmetic uses `jq` (`fromdateiso8601`, `now`), not `date -d` or `date -j`, and fixture timestamps are generated relative to the test's own clock, so cases don't depend on wall time.
- [ ] Both tests pass under `scripts/check-bash-floor.sh --backend system execute` (the `execute` suite lists them) and are run on both legs of `.github/workflows/check-execute-scripts.yml`; both scripts use `set -uo pipefail` and no bash 4 features (no associative arrays, `mapfile`, `${var,,}`, or `|&`).
- [ ] Each script's header comment documents usage, every verdict it can print, its exit codes, and the exact `gh` invocations it makes (endpoint and `--json` field list), matching the style of `record-settled-branch.sh`.

Downstream deliverables:

- [ ] Must deliver: `merge-verdict.sh --repo --pr --merge <true|false> --expected-head <sha|none> [--confirm]` printing exactly the verdict strings in the decision table, and `merge-exec.sh <owner/repo> <pr> <expected-head>` printing `merge-called:<method>:<sha>` or `merge-refused:<verdict>`, both reading only arguments and GitHub (required by Issue 5).
- [ ] Must deliver: the same two scripts usable per node PR and for the coordination PR with no per-mode variant or flag, where a caller passing an index-recorded `head=<sha>` or `none` gets row 8 behavior identical to single-pr (required by Issue 7).
- [ ] Must deliver: the header's list of exact `gh` invocations, so the eval `gh` shim can route each read to its own fixture (required by Issue 5, Issue 7).

**Dependencies**: Issue 1

**Type**: code

### Issue 5: feat(execute): add opt-in --merge to the single-pr path

**Goal**: Wire an opt-in `--merge` into `/execute`'s single-pr path: four new koto states (`merge_readiness`, `merge_route`, `merge_attempt`, `merge_confirm`) and two terminals (`merged`, `ready_awaiting_merge`) after `ci_monitor`, with merge intent checked per invocation, a durable expected-head record, ownership-filtered PR lookups, and an exit summary that always prints `outcome=`, `repos=`, and the PR lines.

**Context**: Today the single-pr template ends `plan_completion -> ci_monitor -> done`, nothing merges, and `ci_monitor`'s `failing_fixed` edge reaches `done` with no gate. Decision 3 adds the merge after `ci_monitor` as koto states backed by the two scripts Issue 4 ships: the read-only `merge-verdict.sh` and `merge-exec.sh`, which holds the only `gh pr merge` call. This issue does the wiring. It covers how `/execute` calls the scripts, where the values it passes come from, how the states route on the verdict, and what the run prints at the end.

The design's Key Interfaces fix the contracts this issue has to honor:

- **Script interfaces.** `merge-verdict.sh --repo <owner/repo> --pr <n> --merge <true|false> --expected-head <sha|none> [--confirm]` and `merge-exec.sh <owner/repo> <pr> <expected-head>`. The caller computes `--merge` as the AND of the session's `MERGE` variable and this invocation's own `--merge` flag. `merge-called` is never read as merged; only a `--confirm` read reporting `merged` is.
- **Merge intent per invocation.** `MERGE` is a template variable set at `koto init` from `--merge`, never agent evidence. A `merge_requested` context value is written at the start of every invocation from that invocation's flags, defaulting to false, and can only narrow `MERGE` (PRD R17).
- **Expected-head record.** For single-pr it's the commit `/execute` last pushed to the home PR, kept in koto context. `/execute` reads it itself and never takes it from the live PR. With no record it passes `none`, and the verdict fires the `head-moved` row.
- **PR ownership.** Every lookup by head branch keeps only PRs with `isCrossRepository` false, the authenticated user as author, and the expected base. Zero or several matches after the filter is `execute:pr-adopt`, never a pick. The write set of repositories is fixed at start.
- **Outcome versus exit.** `exit:` and `outcome=` aren't one-to-one. A DIRTY PR ends `abandonment-forced` with `outcome=ready-awaiting-merge`.
- **Exit lines.** `/execute` prints `outcome=<token>`, `step=<step>` on error, `repos=<comma-separated owner/repo list>`, and `pr=<url> waiting=human|predecessor reason=<condition>` for each unmerged PR.

The existing eval that pins `ci_monitor -> escalate_dirty_merge_state -> done_blocked` must keep passing (R27). The "merged" wording fixes (R24) and `check-merged-wording.sh` belong to Issue 6, and the coordinated loop's use of these pieces belongs to Issue 7.

**Acceptance Criteria**:

*Flag parsing and merge intent*

- [ ] `skills/execute/SKILL.md`'s flags section documents `--merge` (boolean, default off, never remembered across runs). Step 2's `koto init` passes `--var MERGE=true|false` from it. A repeated or valued `--merge` (for example `--merge=yes`) is rejected before any `koto init` or state-file write.
- [ ] `koto-templates/execute.md` declares a `MERGE` variable with default `"false"`, so a `koto init` without it (a legacy caller) can't merge.
- [ ] At the start of every invocation, fresh or resumed, `/execute` writes a `merge_requested` koto context value from this invocation's own `--merge` flag (`true` or `false`, defaulting to `false`). This happens before any state that calls `merge-verdict.sh` is ticked.
- [ ] Resuming a non-terminal session never re-runs `koto init` to change `MERGE`. A session started without `--merge` keeps `MERGE=false` whatever the resume passes.
- [ ] Every `merge-verdict.sh` call `/execute` makes passes `--merge true` only when `MERGE` is `true` and the `merge_requested` context value is `true`. Otherwise it passes `--merge false`. SKILL.md or the directive states this AND rule in one place.

*Expected-head record*

- [ ] Right after the push that `run-cascade.sh --push` makes in `plan_completion`, and after any follow-up push the agent makes from `ci_monitor`, `/execute` writes an `expected_head` koto context value equal to the pushed commit's full 40-hex sha. It checks the value against `^[0-9a-f]{40}$` before writing.
- [ ] No directive derives `expected_head` from `gh pr view --json headRefOid` or any other live PR read. `grep -n headRefOid skills/execute/koto-templates/execute.md skills/execute/SKILL.md` shows no line that writes it to `expected_head`.
- [ ] When the `expected_head` context value is absent, `merge_readiness` passes `--expected-head none`.

*Koto states and terminals*

- [ ] `ci_monitor`'s `passing` and `failing_fixed` edges target `merge_readiness`. No transition anywhere in `execute.md` targets `done`. `ci_monitor`'s gates (`ci_passing`, `merge_state_clean`) keep their pass conditions, and its `dirty_merge_state -> escalate_dirty_merge_state -> done_blocked` route is unchanged.
- [ ] `ci_monitor`'s directive no longer tells the agent to wait on pending checks with no limit. It says CI waiting is bounded by `merge_readiness`'s per-head-commit deadline, and it names the evidence that moves a run whose checks are still pending on to `merge_readiness`.
- [ ] `merge_readiness` calls `merge-verdict.sh --repo <repo> --pr <n> --merge <AND value> --expected-head <expected_head|none>`. `<repo>` is the start-time repository record and `<n>` comes from the ownership-filtered lookup. It stores the single verdict line in a `merge_verdict` koto context value. No CI wait bookkeeping is stored: the deadline is anchored by the script on the head commit's `committedDate`, per Issue 4.
- [ ] `merge_route`'s transitions key on gates over the `merge_verdict` context value, not on agent evidence alone:
  - `pending:*` goes back to `merge_readiness`.
  - `mergeable:<method>:<sha>` goes to `merge_attempt`.
  - `merged` goes to `merged`.
  - `awaiting:*` goes to `ready_awaiting_merge`.
  - `error:execute:<step>` goes to `done_blocked` with the step recorded.
  - An unparseable verdict goes to `done_blocked` with `execute:status-read`.
- [ ] No transition into `merge_attempt` resolves on agent-submitted evidence alone.
- [ ] `merge_attempt` declares no `default_action` (the default-action policy bars irreversible calls). Its directive runs exactly `merge-exec.sh <repo> <pr> <expected-head>`, with `<expected-head>` read from the `expected_head` context value, and passes no other arguments or flags.
- [ ] `merge_confirm` runs `merge-verdict.sh ... --confirm` and reaches `merged` only when that read returns `merged`. `merge-called:*` output from `merge-exec.sh` is never treated as merged. `not-merged:merge-call-failed` and `not-merged:merge-not-observed` reach `ready_awaiting_merge`.
- [ ] `merged` and `ready_awaiting_merge` are declared `terminal: true` without `failure: true`, and each has a directive section.
- [ ] Every edge into `done_blocked` records the step the exit summary prints (for example through a `context_assignments` key):
  - `ci_monitor`'s `failing_unresolvable` records `execute:ci`.
  - Verdict errors record their own step (`execute:ci`, `execute:ci-timeout`, `execute:ready`, `execute:pr-closed`, `execute:status-read`).
  - A failed ownership lookup records `execute:pr-adopt`.
  - Every other existing blocker records `execute:<state>`, named by the state that routed there.
  - The DIRTY route records that it came from DIRTY.
- [ ] `koto-templates/execute.mermaid.md` is regenerated from the template. It shows `ci_monitor --> merge_readiness` for `passing` and `failing_fixed`, no `--> done` edge, and the new states and terminals. `scripts/validate-template-mermaid.sh`, `scripts/check-template-directives.sh`, and `scripts/check-template-interpolation.sh` pass on it.
- [ ] Every new `koto next` in `execute.md` and `SKILL.md` carries `--no-cleanup`. `scripts/terminal-retention_test.sh` passes, and it gains engine-backed cases that walk declared edges to `merged` and to `ready_awaiting_merge` and assert each keeps its context (including `merge_verdict`), each with a no-flag control.
- [ ] A shell test (in `terminal-retention_test.sh` or a new `skills/execute/scripts/*_test.sh` wired into `.github/workflows/check-execute-scripts.yml`) asserts three things: `merge_attempt` has no `default_action`, no transition targets `done`, and `escalate_dirty_merge_state` still routes to `done_blocked`.

*PR ownership filter*

- [ ] A script under `skills/execute/scripts/` (for example `owned-pr.sh`) resolves a PR by head branch with the ownership filter. It takes the repository, head branch, and expected base. It keeps only `isCrossRepository == false`, `author.login ==` the login from `gh api user`, and `baseRefName ==` the expected base. On exactly one match it prints that PR's number and URL. When `gh` lists no PR on the branch, it prints nothing and exits 0. When PRs exist but zero or several survive the filter, it exits non-zero and names `execute:pr-adopt`. Every value is checked against a closed pattern before use.
- [ ] Its `_test.sh`, run from `check-execute-scripts.yml`, uses a stub `gh` to cover six cases: one owned PR, a fork PR only, another author's PR only, a wrong-base PR only, two owned PRs, and no PR.
- [ ] Every PR lookup in `execute.md` goes through that filter: the `ci_passing` gate, `orchestrator_setup`'s prose check and its creation script, `pr_finalization`'s `PR_NUMBER`, and `plan_completion`'s `gh pr ready`. `grep -n "gh pr list" skills/execute/koto-templates/execute.md` shows no line ending in a bare `.[0]` pick. `merge_state_clean`'s `gh pr view` reads the PR by the resolved number rather than by the current branch.
- [ ] In `orchestrator_setup`, a branch where PRs exist but none is owned ends `done_blocked` with `execute:pr-adopt`. It doesn't adopt the PR and it doesn't create a second one. The same holds on `impl/<slug>` before `gh pr create`.
- [ ] The Resume section's `gh pr list --state open --search "<topic> in:title"` becomes a head-branch lookup through the same filter, over the checked-out branch, `impl/<slug>`, and `docs/<slug>`. `grep -n 'in:title' skills/execute/SKILL.md` returns no match.

*Repositories and exit summary*

- [ ] At start, `/execute` records its write set of repositories: the current repository's `owner/repo`, checked against `^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$`. It passes only that value as `<repo>` to both merge scripts and to the ownership lookup.
- [ ] Every `/execute` exit prints, one `key=value` per line: `outcome=<token>`, `step=<step>` when the outcome is `error`, and `repos=<comma-separated owner/repo list>`. This covers `merged`, `ready-awaiting-merge`, `paused-for-review`, `error`, and a DIRTY stop.
- [ ] A `merged` exit prints `pr=<url>` for the merged PR. A `ready-awaiting-merge` exit prints `pr=<url> waiting=human reason=<condition>`, where `<condition>` is the verdict with its `awaiting:` or `not-merged:` prefix removed (for example `merge-not-requested`, `head-moved`, `merge-state:DIRTY`). A `paused-for-review` exit prints `pr=<url>` and the resume command.
- [ ] A `merge-not-observed` exit also prints a line saying the PR may still be queued and may merge later.
- [ ] SKILL.md's Exit Paths section carries one outcome-versus-exit table with the single-pr rows from the design:
  - `merged` terminal: `exit: full-run`, `outcome=merged`.
  - `ready_awaiting_merge` terminal, or a session found at legacy `done`: `full-run`, `ready-awaiting-merge`.
  - `paused_for_review`: `exit:` unset, `paused-for-review`.
  - `done_blocked` via DIRTY: `abandonment-forced`, `ready-awaiting-merge` with `reason=merge-state:DIRTY`.
  - `done_blocked` via anything else: `abandonment-forced`, `error` with the recorded step.
  - `re-evaluation`: `error`, `execute:re-evaluation`.
- [ ] The State section's `phase_pointer` enum lists the four new states. The Resume section's retained-session check names `merged` and `ready_awaiting_merge` alongside `done_blocked` and `paused_for_review` as terminals whose record is read and then cleared.

*Write set (R28)*

- [ ] SKILL.md's closed write-target set (Security Considerations point 2) lists `gh pr merge`, reached only through `scripts/merge-exec.sh`. It also lists the new koto context keys (`merge_requested`, `expected_head`, `merge_verdict`, CI wait bookkeeping). It states that `gh pr review` is outside the set.
- [ ] `bash scripts/check-skill-requires.sh` passes. If the new scripts' `gh`/`git`/`jq` calls need `requires.tsv` records, those records are added.

*gh shim and evals*

- [ ] `skills/execute/evals/fixtures/bin/gh` appends every invocation's full argument list, one call per line, to the file named by `GH_CALL_LOG` when it's set. It serves per-scenario fixtures for these calls, and existing scenarios (including `plan-orchestrator`'s DIRTY fixture) behave byte-for-byte as before:
  - `pr list` with the ownership fields;
  - `pr view` with the verdict's JSON fields;
  - `pr checks`;
  - `pr ready`, including a failing variant;
  - `pr merge`, with success, failure, and "accepted but still OPEN" variants;
  - `api user`;
  - branch protection and rules reads;
  - the merge-method read.
- [ ] `skills/execute/evals/evals.json` gains scenarios. Each names the requirement IDs it covers in its name or expectations, runs against the shim, and asserts on the shim's call log and the printed exit lines:
  - [ ] Mergeable scenario with `--merge`: exactly one logged `pr merge` call containing `--match-head-commit <expected_head>`, then `outcome=merged`, `exit: full-run`, and `pr=` and `repos=` lines (R19).
  - [ ] Mergeable scenario without `--merge`: no `pr merge` logged, then `outcome=ready-awaiting-merge` with `reason=merge-not-requested` (R20).
  - [ ] With `--merge` on a review-required merge state, and separately on a conflicting (DIRTY) state: no `pr merge` logged, and each ends `outcome=ready-awaiting-merge` with a `reason=` naming the condition. The DIRTY case still goes through `escalate_dirty_merge_state` (R19, R20).
  - [ ] With `--merge` on a failing non-required check: `outcome=error step=execute:ci`. On a check still pending past a small `EXECUTE_CI_WAIT_LIMIT_SECS`: `step=execute:ci-timeout`. On a draft PR whose `pr ready` fails: `step=execute:ready`. None logs a `pr merge` call (R19).
  - [ ] Every pre-check passes but `pr merge` exits non-zero: exactly one `pr merge` logged, then `outcome=ready-awaiting-merge` with `reason=merge-call-failed`, and no `outcome=merged` anywhere in the transcript (R20).
  - [ ] `pr merge` exits 0 but every later `pr view` returns `state: OPEN`: `outcome=ready-awaiting-merge` with `reason=merge-not-observed`, a line saying the PR may still be queued, and no `outcome=merged` anywhere in the transcript (R19, R20).
  - [ ] Base with no protection, no check ever reporting, and a PR head that differs from `expected_head`: no `pr merge` logged, ending `ready-awaiting-merge` with `reason=base-unprotected`, `reason=no-checks`, and `reason=head-moved` respectively (R19).
  - [ ] Base requiring a review with no approval, and a checks-only base with a PR that edits `.github/workflows/`: no `pr merge` logged, ending `ready-awaiting-merge` with `reason=review` and `reason=workflow-change` (R19).
  - [ ] A same-named PR from a fork, and separately one by another author, on the head branch: not adopted, not edited, not readied, and the run ends `outcome=error step=execute:pr-adopt` (R19).
  - [ ] A session started with `--merge`, interrupted before `merge_readiness`, and resumed without `--merge`: no `pr merge` logged, ending `ready-awaiting-merge` with `reason=merge-not-requested` (R17, R19).
  - [ ] A session started without `--merge` and resumed with `--merge` on the mergeable scenario: no `pr merge` logged, ending `ready-awaiting-merge` with `reason=merge-not-requested` (R17, R19).
  - [ ] A repository allowing merge and squash: the logged call uses `--squash`. A repository allowing only rebase: it uses `--rebase` (R19).
  - [ ] Standing on the branch a single-pr `/scope --intent=continue` run pushed, with one owned open draft PR whose title contains the slug, `/execute` adopts that PR. The log has no `pr create` call and no push to or checkout of `impl/<slug>` (R9, R13).
  - [ ] Across every new scenario's call log, no `pr merge` line contains `--admin` or `--auto` (R19).
- [ ] Each new scenario passes with `scripts/run-evals.sh --runs 3 execute` (R26).
- [ ] The existing `/execute` evals pass. Eval 21's DIRTY route assertions are unchanged, and no existing eval assertion changes except for R24 text owned by Issue 6 (R27).

*Downstream deliverables*

- [ ] Must deliver: the `merged` and `ready_awaiting_merge` terminals, the outcome-versus-exit table in SKILL.md's Exit Paths, and the exit-line spelling, so the "merged" wording can be checked against them (required by Issue 6).
- [ ] Must deliver: `--merge` parsing, the `MERGE` AND `merge_requested` computation, the ownership-filter script, the `repos=` write-set record, and the outcome/`pr=`/`waiting=`/`reason=` printing. Each must be something the coordinated loop can call or reuse, not inline to the single-pr template (required by Issue 7).
- [ ] Must deliver: stable exit lines `outcome=`, `step=`, `pr=<url> waiting=... reason=...`, and `repos=`, each pinned by an eval, so the driver can relay them by anchored key (required by Issue 11).

**Dependencies**: Issue 4

**Type**: code

### Issue 6: fix(execute): describe only merged runs as merged

**Goal**: Make "merged" in `/execute`'s and `/work-on`'s SKILL.md describe only the `merged` final state, and enforce that with a new `scripts/check-merged-wording.sh` (plus `_test.sh` and allowlist) wired into CI.

**Context**: Both skills promise more than they do. `/execute`'s description says it drives a plan "all the way to merged code", its opening says it "drives the plan's issues to merged code", and its Exit Paths define `full-run` as the "merged-PR done-signal" ("the single PR merges", "the merged home PR is it", `exit_artifacts:` records "the merged PR(s)"), with the same phrase in the paused-for-review paragraph and in Slot 6 ("did not reach its merged-PR terminal"). `/work-on`'s description says "to a merged pull request" and its Output section says "A merged PR with passing CI", though `/work-on` never merges. After Issue 5, a single-pr run without `--merge` ends `ready-awaiting-merge` with `exit: full-run`, so the current text is false for the default run.

PRD R24 requires that, in these two SKILL.md files' descriptions, output sections, and exit definitions, "merged" describe only the `merged` final state, and that `full-run` be defined by the Final States. The PRD's acceptance criterion asks for a script, added with this change, that checks `grep -n merged` over both files. R27 requires existing evals that assert this text to be updated in the same change and otherwise left alone.

This issue runs after Issue 5 (single-pr merge states, the outcome-to-exit table, `outcome=` printing) and Issue 7 (the rewritten Coordinated Execution Path, which adds its own "merged" prose about node PRs, merge order, and the coordination PR merging last). The wording pass and the allowlist are written against the final text of both, so the check passes on the tree as it stands after Issues 5, 7, and 6 together. Some "merged" lines legitimately describe GitHub's PR state rather than a run outcome (for example, the coordinated loop reading each indexed PR's live merged/open status, or a PR node being satisfied when its PR has merged); those are what the allowlist is for.

Design: `docs/designs/DESIGN-scope-then-execute.md` (Solution Architecture > Components > `/execute`, R24 wording; `/work-on`; Key Interfaces > Outcome versus exit; Implementation Approach > Phase 3a)

**Acceptance Criteria**:

Wording in `skills/execute/SKILL.md`:

- [ ] The frontmatter `description` no longer says the skill drives a plan "to merged code" unconditionally; any "merged" left in it is qualified by `--merge` (for example "ready pull requests, merged when run with `--merge`").
- [ ] The opening paragraph no longer says `/execute` "drives the plan's issues to merged code" unconditionally.
- [ ] The `full-run` bullet under Exit Paths is defined by reference to the Final States and the outcome-to-exit table from Issue 5: it states that `full-run` ends with `outcome=merged` or `outcome=ready-awaiting-merge`, and contains none of the phrases "merged-PR done-signal", "the merged home PR is it", or "the single PR merges" as an unconditional claim.
- [ ] `exit_artifacts:` for `full-run` is described as recording the run's PR(s) and finalized docs, not "the merged PR(s)".
- [ ] The paused-for-review paragraph and Slot 6 no longer use "merged-PR done-signal" or "merged-PR terminal"; Slot 6 names `/work-on`'s actual terminal instead.
- [ ] The Coordinated Execution Path as rewritten by Issue 7 uses "merged" only for GitHub PR state (a node or coordination PR that GitHub reports merged) or for the `merged` final state, never for `ready-awaiting-merge` or `paused-awaiting-merges`.

Wording in `skills/work-on/SKILL.md`:

- [ ] The frontmatter `description` no longer says `/work-on` takes work "to a merged pull request"; it names a ready PR with passing CI (or equivalent) instead.
- [ ] The `## Output` section no longer says "A merged PR"; it describes the PR `/work-on` actually leaves (ready, CI passing, referencing the source issue).

The check, `scripts/check-merged-wording.sh`:

- [ ] Scans exactly `skills/execute/SKILL.md` and `skills/work-on/SKILL.md`, listed in one variable at the top of the script, and flags every line containing the word "merged" case-insensitively.
- [ ] Auto-accepts, without an allowlist record, an occurrence that is the final-state token (`` `merged` ``, `outcome=merged`, `pr_state=merged`) or a negation (`unmerged`, `not-merged`). Any other occurrence needs a record.
- [ ] Reads `scripts/check-merged-wording.allow`: tab-separated records `<file>`, `<fixed-string line match>`, `<reason>`, with blank lines and `#` comments ignored and a header comment documenting the format, modeled on `scripts/check-template-directives.allow`.
- [ ] Exits 1 and names `file:line` for any flagged line no record covers.
- [ ] Exits 1 naming the record for a record whose fixed string matches zero lines in its file, and for a record that matches more than one line.
- [ ] Exits 1 naming the record for a record whose single matched line contains no flagged occurrence (a stale record), and for a record with an empty reason field or a file outside the scanned list.
- [ ] Exits 0 on the tree after Issues 5, 7, and 6, and every allowlist record's reason says why that line describes GitHub PR state rather than a run outcome.
- [ ] Runs under bash 3.2 (no associative arrays, no `mapfile`, no `${var,,}`).

Tests, `scripts/check-merged-wording_test.sh`:

- [ ] Runs the script against temporary fixture copies (via an env var or argument that overrides the repo root) and covers, each as a separate case with an asserted exit code: a clean file passes; an unallowlisted "merged" line fails; `` `merged` ``, `outcome=merged`, `unmerged`, and `not-merged` pass with no record; a record matching zero lines fails; a record matching two lines fails; a stale record fails; a record with an empty reason fails; the real repository passes.

CI wiring:

- [ ] `.github/workflows/check-execute-scripts.yml` runs `bash scripts/check-merged-wording_test.sh` and `bash scripts/check-merged-wording.sh` on the Linux leg, and its `paths:` filter includes `scripts/check-merged-wording.sh`, `scripts/check-merged-wording_test.sh`, and `scripts/check-merged-wording.allow` (both SKILL.md files are already covered by `skills/**`).
- [ ] Both scripts are listed in the `execute` suite of `scripts/check-bash-floor.sh`'s registry, so the macOS leg runs them on the bash 3.2 floor, and `bash scripts/check-bash-floor_test.sh` still passes.

Templates and evals (R27):

- [ ] In `skills/execute/koto-templates/execute.md`, the directive text of the `ready_awaiting_merge`, `done_blocked`, and `paused_for_review` states contains no "merged" other than `unmerged` or `not-merged`.
- [ ] In `skills/execute/evals/evals.json`, no `expected_output` or assertion of a scenario whose prompt lacks `--merge` says the run reaches a merged PR (the `single-pr-plan-to-merged-pr-unchanged` scenario's "to a single merged PR" / "to one merged PR" text is changed to the ready PR and `ready-awaiting-merge` outcome if Issues 5 and 7 left it); scenario names and all other fields are unchanged.
- [ ] The existing `/execute` and `/work-on` eval suites pass, and this issue's diff to them touches only assertions about R24 text.

Downstream:

- [ ] Must deliver: `/execute`'s Exit Paths define `full-run` through the `outcome=` tokens (`merged`, `ready-awaiting-merge`), so a caller reads the outcome line rather than inferring a merge from `exit: full-run` (required by Issue 11).
- [ ] Must deliver: `scripts/check-merged-wording.sh` keeps its scanned-file list in one variable, so a later skill can be added with a one-line change (required by Issue 11).

**Dependencies**: Issue 5, Issue 7

**Type**: code

### Issue 7: feat(execute): run coordinated PLANs in one repository with per-node branches and merges

**Goal**: Rewrite `/execute`'s coordinated loop so a coordinated PLAN runs in one repository (or several) with one `impl/<slug>-<node-id>` branch and PR per PR node, merges node PRs in merge order and the coordination PR last through `merge-verdict.sh` and `merge-exec.sh`, records each pushed head as a `head=` field in the coordination index, runs the finalization cascade on the coordination branch before marking it ready, and pauses and resumes from the coordination PR.

**Context**: Today `skills/execute/SKILL.md`'s "Coordinated Execution Path" assumes more than one repository, cuts one branch per repository, and waits for merges it never performs. PRD R6 lets a coordinated PLAN put every PR group in one repository, so two groups in one repository would share a branch under the current loop. Design Decision 2 makes the PR node the unit of branching: `/execute` reads `REPO`, `PR_GROUP`, and `ISSUES` from each `plan-to-tasks.sh` node (Issue 3), cuts `impl/<slug>-<node-id>` from the default-branch tip in its own worktree, dispatches the node's issues to `work-on.md` with that branch as `SHARED_BRANCH` (the child commits to it and submits `pr_status: shared`; the orchestrator owns the PR), then pushes and opens one draft PR per node. Nodes are never cut from the coordination branch, so no node PR carries the PLAN to the default branch ahead of the coordination PR.

Decision 3 has the coordinated loop call the same two scripts the single-pr path uses (Issue 5, built on the scripts from Issue 4), per node in merge order and on the coordination PR last. The Key Interfaces section pins how: `merge-verdict.sh --repo <owner/repo> --pr <n> --merge <true|false> --expected-head <sha|none> [--confirm]` and `merge-exec.sh <owner/repo> <pr> <expected-head>`, with the expected head read by `/execute` from the node's `head=<sha>` field in the coordination index (never from the live PR), `merge-called` never read as merged, and only a `--confirm` read of `MERGED` counting. PR ownership filtering applies to every head-branch lookup and every PR number read from the index, and `/execute` fixes its repository write set at start. The Outcome versus exit table maps coordinated stop points to `merged`, `ready-awaiting-merge`, and `paused-awaiting-merges`. PRD R21 (merge order, coordination PR last) and R22 (the pause leaves the coordination PR open; a later run resumes from it without re-scoping) are the requirements this issue closes, alongside the R6 `/execute` half.

Multi-repo PLANs with `Group: default` keep one node per repository and must behave as today apart from the added merge step.

**Acceptance Criteria**:

*Coordinated Execution Path text (`skills/execute/SKILL.md`)*

- [ ] The section no longer says a coordinated PLAN "spans more than one repository" or that there is "one branch per repo"; it says a coordinated PLAN spans one or more repositories and that the unit of branching is the PR node `(repo, pr_group)`.
- [ ] The section states that each node's `REPO`, `PR_GROUP`, and `ISSUES` come from `plan-to-tasks.sh` output and that `/execute` doesn't re-parse the PLAN's Implementation Issues table to find them.
- [ ] Step 2 is rewritten as the passes refresh, dispatch, evaluate, merge, and pause, and names `merge-verdict.sh` and `merge-exec.sh` with exactly the argument shapes in the design's Script interfaces; the section contains no `gh pr merge` command of its own (merging goes only through `merge-exec.sh`).
- [ ] The section states the expected head for a node PR comes from that node's `head=` field in the coordination index, and for the coordination PR from its own `head=` record, and never from a live `gh pr view` read.
- [ ] The section defines `--merge` for `merge-verdict.sh` as this invocation's `--merge` flag (a run started or resumed without `--merge` passes `--merge false`).
- [ ] Every use of "merged" in the rewritten section refers either to the `merged` final state or to a PR GitHub reports as `MERGED`; no sentence calls a pause, a `ready-awaiting-merge` end, a `merge-called` result, or the coordination PR being marked ready "merged".
- [ ] The section contains a table or list mapping each coordinated stop point to `exit:` and `outcome=` that matches the design's Outcome versus exit rows: coordination PR `MERGED` -> `full-run` / `merged`; nothing left to start with something unmerged -> `full-run` / `ready-awaiting-merge`; a node waiting on an unmerged predecessor -> `exit:` unset with `paused_awaiting_merges: true` / `paused-awaiting-merges`.
- [ ] The State section lists `paused_awaiting_merges:` as a conditional field present only while a coordinated run is paused, and states that no CI-deadline bookkeeping is stored (the deadline is anchored on each head commit's `committedDate` by `merge-verdict.sh`).

*Branches and worktrees*

- [ ] For each unblocked PR node, `/execute` fetches the default branch and cuts `impl/<slug>-<node-id>` from the default-branch tip at that moment (not from the coordination branch, a predecessor's branch, or `HEAD`), in a dedicated `git worktree`, with `<slug>` validated against `^[a-z0-9-]+$` and `<node-id>` taken from the `plan-to-tasks.sh` node name.
- [ ] Each node's issues (from `ISSUES`, in that order) are dispatched to `work-on.md` with `SHARED_BRANCH=impl/<slug>-<node-id>`; no child opens a PR (each submits `pr_status: shared`).
- [ ] Node pushes use `git push origin HEAD:refs/heads/impl/<slug>-<node-id>` with no force option, and refuse when `HEAD` is detached or the target is the remote's default branch.
- [ ] Before `gh pr ready` on a node PR, the node branch runs the same `wip/` sweep single-pr finalization runs, and `git ls-files wip/` on the pushed node head is empty.
- [ ] Each node PR is opened as a draft against the default branch with title `feat(<slug>): <node-id>` and a body built from a fixed template (node id, issue numbers, coordination PR link) passed with `--body-file`; the body contains no free-text PLAN or state-file prose.
- [ ] A node PR is marked ready only after its checks pass, then evaluated with `merge-verdict.sh`.

*Coordination index and expected-head record*

- [ ] After each node push, `/execute` rewrites that node's PR Index line to carry `head=<sha>` (the full 40-hex sha it just pushed) and posts the body with `gh pr edit`; the rewritten body passes `shirabe validate --coordination-body` before posting.
- [ ] After the finalization cascade push on the coordination branch, `/execute` records that sha as the coordination PR's `head=` in the index before evaluating the coordination PR.
- [ ] A node PR that is indexed but has no `head=` field is evaluated with `--expected-head none` and reports `head-moved`; no `pr merge` call is logged for it.

*PR ownership and write set*

- [ ] At start, `/execute` fixes its repository write set from the PLAN's node `REPO` values and prints it as `repos=<owner/repo,...>`; the set doesn't change during the run.
- [ ] Every PR number read from the coordination index, and every `gh pr list --head impl/<slug>-<node-id>` lookup, keeps only PRs with `isCrossRepository == false`, author equal to the authenticated user, base equal to the default branch, and head branch equal to `impl/<slug>-<node-id>` for that node's id.
- [ ] A node with no indexed PR whose head-branch lookup returns no PR at all gets a new PR; a lookup that returns one or more PRs of which zero or several pass the filter ends the run `outcome=error` `step=execute:pr-adopt`.
- [ ] The coordination PR itself is located by an ownership-filtered head-branch lookup on the coordination branch, not by a title search, and must carry the `This is a **coordination PR**` marker.
- [ ] `skills/execute/SKILL.md`'s closed write-target set lists pushes to `impl/<slug>-<node-id>` branches, `gh pr create` for node PRs, `gh pr ready` for node PRs and the coordination PR, and `gh pr merge` through `merge-exec.sh` only.

*Merge order, pause, and cascade*

- [ ] A node PR is opened only after every predecessor in the merge-order DAG reports `MERGED` on a `merge-verdict.sh --confirm` read; a predecessor with `merge-called` but no confirmed `MERGED` doesn't unblock anything.
- [ ] When no unblocked node remains and some node waits on an unmerged predecessor, the run ends `outcome=paused-awaiting-merges`, leaves the coordination PR open (no `gh pr close`), writes `paused_awaiting_merges: true`, prints one `pr=<url> waiting=human|predecessor reason=<condition>` line per unmerged PR, the `repos=` line, and a `resume=/execute docs/plans/PLAN-<topic>.md` line (with ` --merge` appended when this run had `--merge`).
- [ ] The chain-finalization cascade runs exactly once, on the coordination branch, after every node PR reports `MERGED` and before the coordination PR is marked ready; the coordination PR is then marked ready, evaluated, and merged through `merge-exec.sh` only after `shirabe validate --merge-gate --mode=ready` passes.
- [ ] A resumed run reads node state from the coordination index and live `gh`, doesn't re-dispatch issues of a node whose PR is `MERGED`, and makes no scoping commit (no commit touching `docs/briefs/`, `docs/prds/`, `docs/designs/`, or `docs/plans/` outside the cascade).

*Eval scenarios (`skills/execute/evals/evals.json`, `gh` shim with call log)*

Each scenario names the requirement IDs it covers and passes with `--runs 3`. The single-repo coordinated fixture is a PLAN with every issue carrying the same `_Repo:` and at least two groups, at least one root node and at least one node with a predecessor.

- [ ] Single-repo, mergeable scenario, `--merge` (R6, R21): every node PR has a distinct head branch `impl/<slug>-<node-id>`; the shim's log shows exactly one `pr create` per node plus none for the coordination PR; the merge log orders each node PR after all its predecessors and the coordination PR last; every `pr merge` carries `--match-head-commit <sha>` equal to that PR's index `head=`, and none carries `--admin` or `--auto`; the run prints `outcome=merged`.
- [ ] Same fixture, git assertions (R6): for each node branch, `git merge-base <node-branch> <default-tip-at-cut>` equals the default-branch tip recorded at its cut time; `git merge-base --is-ancestor <c> <node-branch>` fails for every commit `c` on the coordination branch that isn't on the default branch; and `git ls-tree -r --name-only <node-branch> -- docs/plans/PLAN-<topic>.md` prints nothing.
- [ ] Same fixture, only root PRs mergeable (R22): the run ends `outcome=paused-awaiting-merges`, every root PR is ready with passing checks, no `pr create` is logged for a non-root node, no `pr close` is logged, the coordination PR stays open, and the output contains a `resume=` line.
- [ ] Resume after the shim marks the roots `MERGED` (R22): a second `/execute` opens PRs for exactly the next layer's nodes, logs no `pr create` for already-indexed nodes, and makes no scoping commit.
- [ ] Merge not observed (R21): a root node's `pr merge` exits 0 but `pr view` keeps returning `OPEN`; no successor node PR is created or merged, no `pr merge` call is logged for the coordination PR, and that root's line reads `reason=merge-not-observed`.
- [ ] Head moved (R19, R21): a node PR whose live `headRefOid` differs from its index `head=` logs no `pr merge` for that PR and its line reads `reason=head-moved`.
- [ ] Foreign index entry (R19): the index lists a PR number whose author isn't the authenticated user, and separately one whose head branch isn't `impl/<slug>-<node-id>`; each run ends `outcome=error step=execute:pr-adopt` and the shim logs no `pr edit`, `pr ready`, `pr merge`, or `pr close` against that PR number.
- [ ] Out-of-set repository (R19): an index entry, and separately a `_Repo:` entry, naming a repository not in the PLAN's set is refused, the run ends `outcome=error` with a `step=` line, and the shim logs no write call carrying `--repo` for that repository.
- [ ] Without `--merge` (R20): the mergeable fixture run without `--merge` logs no `pr merge` call and ends with no PR reported as merged.
- [ ] The existing coordinated scenarios (`coordinated-cross-unit-carry-forward`, `coordinated-effort-syncs-as-per-repo-prs-progress`, `coordinated-merge-last-gate-blocks-while-pr-unmerged`, `coordinated-plan-verifies-its-mode-scoped-record`) still pass, with edits only where they assert one-branch-per-repository or multi-repo-only text.

*Downstream deliverables*

- [ ] Must deliver: the final Coordinated Execution Path text in `skills/execute/SKILL.md` with "merged" used only for the `merged` final state and PRs GitHub reports `MERGED`, so the wording pass and `check-merged-wording.sh` allowlist can be written against it (required by Issue 6).
- [ ] Must deliver: a `paused-awaiting-merges` exit that prints `outcome=paused-awaiting-merges`, one `pr=<url> waiting=<who> reason=<condition>` line per unmerged PR, `repos=`, and `resume=<command>` with anchored keys, pinned by the pause eval (required by Issue 11).
- [ ] Before `/execute` builds `--pr` arguments for its own `shirabe validate --merge-gate` call, it drops any PR-index entry that points at the coordination PR itself; an eval with such an entry shows the gate still passes once every node PR has merged.
- [ ] An eval asserts the chain-finalization cascade commit lands on the coordination branch after every node PR merged and before the coordination PR's `pr ready` call in the shim log.
- [ ] The paused run's `resume=` line carries `--merge` exactly when the paused invocation had it; the mergeable fixture run without `--merge` ends `outcome=ready-awaiting-merge` with `reason=merge-not-requested` on each open PR.

**Dependencies**: Issue 3, Issue 5

**Type**: code

### Issue 8: test(validate): cover single-repo coordination bodies and self-referencing index entries

**Goal**: Lock in that a coordination PR whose PRs all live in one repository passes `shirabe validate --coordination-body` and `--merge-gate`, and make `lifecycle.yml`'s merge-last gate drop a PR-index entry that points at the coordination PR itself.

**Context**: PRD R6 lets a `coordinated` PLAN put every PR group in one repository, and requires `shirabe validate --coordination-body` to accept a single-repo coordination body. Design Decision 2 found the Rust validator already indifferent to repository count: `check_coordination_body` in `crates/shirabe-validate/src/coordination.rs` matches only the fixed prefix `COORDINATION_DECLARATION_MARKER` ("This is a **coordination PR**"), and `run_merge_gate` in `crates/shirabe-validate/src/merge_gate.rs` resolves each `--pr` ref independently without counting repos. So no validator logic changes here. What's missing is test coverage that pins this behavior: every existing fixture (`good_body()` in `coordination.rs` tests and in `crates/shirabe/tests/coordination_body.rs`) indexes two different repos (`tsukumogami/shirabe` and `tsukumogami/koto`) and carries the old "for a coordinated multi-repo effort" blockquote, and every `merge_gate.rs` test uses a single ref.

The one behavior gap is in `.github/workflows/lifecycle.yml`'s "Coordination merge-last gate" step. It extracts every `owner/repo:path#number` token from the live coordination PR body with `grep -oE` and passes each as `--pr`. In a single-repo coordinated run the coordination PR and its node PRs share a repository, so a body that mentions the coordination PR's own `owner/repo:...#<its number>` would make the gate wait on a PR that can only merge after the gate passes, and the coordination PR could never merge. The design fixes this in the workflow: drop any extracted ref whose repository is the workflow's own repository and whose number is the triggering PR's number.

Design: `docs/designs/DESIGN-scope-then-execute.md` (Decision 2; Solution Architecture > Components > Validator and CI; Implementation Approach > Phase 3b)

**Acceptance Criteria**:

Validator unit tests (`crates/shirabe-validate/src/coordination.rs`, `mod tests`):

- [ ] A new fixture helper (e.g. `single_repo_body()`) builds a coordination body whose blockquote uses the wording Issue 1 puts in the `references/coordination-strategy.md` template (begins `> This is a **coordination PR**`, contains no "multi-repo"), whose PR Index has at least two entries that all reference the same repository (e.g. `tsukumogami/shirabe:...#201` and `tsukumogami/shirabe:...#202`) under distinct node ids, and whose `merge-order` block lists those node ids.
- [ ] Test `body_check_passes_single_repo_body` asserts `check_coordination_body(&single_repo_body())` returns an empty vec.
- [ ] Test `body_check_single_repo_body_has_no_multi_repo_wording` asserts the fixture contains `COORDINATION_DECLARATION_MARKER` and does not contain the substring `multi-repo`, so the fixture can't silently drift back to the old template.
- [ ] Test `gate_passes_single_repo_all_merged` calls `decide_gate` with two `GatePrStatus` entries labelled from the same repository, both merged, and asserts `GateDecision::Pass`; a sibling `gate_blocks_single_repo_one_unmerged` flips one to unmerged and asserts `GateDecision::Block` naming that label.

Merge-gate unit tests (`crates/shirabe-validate/src/merge_gate.rs`, `mod tests`):

- [ ] Test `run_merge_gate_single_repo_all_merged_passes` passes two `--pr` refs in the same repository (`tsukumogami/shirabe:...#201`, `tsukumogami/shirabe:...#202`) with `MockIssueStateClient` returning `IssueState::Closed` for both under `ReviewPosture::Ready`, and asserts `MergeGateOutcome::Pass { pr_count: 2, upstream_count: 0 }`.
- [ ] Test `run_merge_gate_single_repo_one_open_blocks` uses the same two refs with #202 returning `IssueState::Open` and asserts `MergeGateOutcome::Blocked(_)` whose reasons mention #202 (or its node id `pr-202`) and not #201.

CLI integration tests (`crates/shirabe/tests/coordination_body.rs`):

- [ ] Test `coordination_body_single_repo_body_passes` writes a single-repo body (same shape as the unit fixture: new blockquote wording, all PR Index refs in one repository) and asserts `shirabe validate --coordination-body <file>` exits 0.
- [ ] Test `coordination_body_single_repo_body_passes_annotation_format` runs the same body with `--format annotation` and asserts exit 0 with no `::error` in stdout.

`lifecycle.yml` self-reference filter:

- [ ] In the "Coordination merge-last gate" step, after `PR_REFS` is extracted and before `GATE_ARGS` is built, every ref whose `owner/repo` equals the workflow's repository (`github.repository`, compared case-insensitively) and whose `#number` equals `PR_NUMBER` is removed from the list. Refs to the same repository with a different number, and refs to other repositories with the same number, are kept.
- [ ] `github.repository` reaches the script through an `env:` entry (like `PR_BODY`), not by inline `${{ }}` interpolation inside the filter logic.
- [ ] Each dropped ref emits a `::notice::` line naming it, so a reader of the run log can see the gate skipped the coordination PR's own entry.
- [ ] If the filter leaves no refs, the step reaches the existing empty-index branch (`::error::Coordination PR is ready but its PR-index is empty`) and exits 1; the filter doesn't bypass the fail-closed guard.
- [ ] Running the step's extract-and-filter snippet locally in bash with `PR_NUMBER=42`, the repository set to `tsukumogami/shirabe`, and a body indexing `tsukumogami/shirabe:docs/plans/PLAN-x.md#42`, `tsukumogami/shirabe:docs/plans/PLAN-x.md#43`, and `tsukumogami/koto:docs/plans/PLAN-y.md#42` yields exactly the `#43` shirabe ref and the koto `#42` ref.
- [ ] The step's comment block no longer quotes the declaration line as "for a coordinated multi-repo effort"; it quotes only the fixed prefix `This is a **coordination PR**` and explains the self-reference filter and why it exists (a coordination PR that gates on itself can never merge).
- [ ] The non-coordination skip path is unchanged: an ordinary PR (no marker in `PR_BODY`) still exits 0 before any `gh` call, and the filter runs only on the coordination path.

General:

- [ ] No change to `check_coordination_body`, `run_merge_gate`, `decide_gate`, or `COORDINATION_DECLARATION_MARKER` logic; this issue adds tests and the workflow filter only. If a new test fails because the validator does count repositories, stop and report it rather than widening scope silently.
- [ ] Existing multi-repo tests (`body_check_passes_clean_authored_body`, `run_merge_gate_all_merged_passes`, `coordination_body_clean_body_passes`, and the rest) still pass unmodified.
- [ ] `cargo test -p shirabe-validate` and `cargo test -p shirabe --test coordination_body` pass; `cargo fmt --check` is clean.

**Dependencies**: Issue 1

**Type**: code

### Issue 9: feat(scope): accept --intent and forward it to the /plan hop

**Goal**: Make `/scope` accept `--intent=continue|stop` at Phase 0, reject bad or repeated values before any state exists, record the intent in its state file and as the `INTENT` koto variable, refuse a differing intent on reattach, forward intent and the caller's coordination flags to the `/plan` hop, and stop creating an up-front coordination PR on intent runs.

**Context**: Today `/scope` has no notion of caller intent. Its Phase 0 (`skills/scope/references/phases/phase-0-setup.md`, "Flag Parsing Before the Positional Slug Is Read") parses only `--auto`, `--interactive`, `--max-rounds=N`, `--coordinated`, `--no-coordinated`, and `--upstream`. Its `/plan` hop (`phase-2-chain-orchestration.md` per-child argument table, and the `hop_plan` directive in `skills/scope/koto-templates/scope.md`) passes only the DESIGN path plus `--upstream` when `consumed_upstream:` is recorded, so nothing the caller says reaches `/plan`'s split-mode decision. And SKILL.md's "Coordination Intent" section creates a coordination PR up front, before any hop runs, whenever `--coordinated` or a coordinated-by-default header is present.

The design (Decision 1) makes `/plan` own `--intent`, `--coordinated`, and `--no-coordinated` as child-documented flags (delivered by Issue 2); `/scope` only forwards them. Forwarding the coordination flags "exactly as the caller passed them" matters: `/scope` must never synthesize a header-derived `--coordinated`, because on `/plan` an explicit flag outranks `--intent`. Decision 5 and the cross-validation seams give `/scope` the Phase 0 half: an `INTENT` template variable (defaulting to `none`, so the later `intent_declared` gate can route no-intent runs through today's states), an always-present `intent:` state field, and a refusal (`intent-mismatch recorded=<x> requested=<y>`) when a reattach names a different intent, which `/deliver` later maps to `deliver:intent-mismatch`. With intent set, the coordination PR is opened only at exit by the publish step (Issue 10), so a header-coordinated run that doesn't split never carries one and abandonment has none to close.

This issue does not add the publish states, `publish-scoping-pr.sh`, the `intent=`/`outcome=`/`next=`/`pr=` exit lines, `published_pr:`/`publish_error:`, or the `gh ... mode:intent` requires line; those belong to Issue 10. A no-intent run must behave exactly as today (D2, R2).

Design: `docs/designs/DESIGN-scope-then-execute.md` (Considered Options > Decision 1 and Decision 5; Decision Outcome > "Intent mismatch" seam; Solution Architecture > Components > `/scope`; Data Flow step 1; Implementation Approach > Phase 4)
PRD: `docs/prds/PRD-scope-then-execute.md` (R1, R2, R3, R5, R8, R13)

**Acceptance Criteria**:

*Flag parsing and rejection (Phase 0, SKILL.md)*

- [ ] `skills/scope/SKILL.md` "Execution-Mode Flags" (or an adjacent flag section) documents `--intent=continue|stop`, states that omitting it means intent `none` and today's behavior, and the frontmatter `argument-hint` lists `--intent=continue|stop` (R1).
- [ ] `phase-0-setup.md` "Flag Parsing Before the Positional Slug Is Read" lists `--intent=<value>` among the parsed flags and applies the residue rule to it (the token is removed before the slug is read and is never tested against the slug regex).
- [ ] `phase-0-setup.md` states that `--intent` with a value other than `continue` or `stop` (including a bare `--intent` or `--intent=`), and a repeated `--intent` (e.g. `--intent=stop --intent=continue`, even when both values are equal), are rejected with an error naming `--intent`, and that the rejection happens before slug validation, before `koto status`/`koto init`, and before the state file is written (R1).
- [ ] A new eval in `skills/scope/evals/evals.json` for `/scope <topic> --intent=bogus` and one for `/scope <topic> --intent=stop --intent=continue` each expect an error naming `--intent` and assert that no `/scope` state file and no `scope-<topic>` koto session exist afterwards; both scenarios name R1.

*Recording intent (koto var and state file)*

- [ ] `skills/scope/koto-templates/scope.md` declares an `INTENT` variable with `required: false` and `default: none`, with a description naming its three values (`continue`, `stop`, `none`); `koto template compile` (or the repo's template check) passes on the edited template.
- [ ] The `koto init` block in `phase-0-setup.md` "Workflow Session: Probe, Open or Reattach" passes `--var INTENT=<continue|stop|none>` alongside `TOPIC` and `PLUGIN_ROOT`, and the prose states the value is the validated flag value or `none`, never raw `$ARGUMENTS` text.
- [ ] `phase-0-setup.md` "Initial State-File Shape" adds `intent: <continue|stop|none>` to the YAML block and states the field is always present (written as `none` when no `--intent` was given), as the explicit exception to the absence discipline of invariant I-5.
- [ ] `skills/scope/references/state-schema.md` documents `intent:` as an always-present field with values `continue | stop | none`, written at Phase 0 and never changed afterwards (R3).
- [ ] `phase-2-chain-orchestration.md`'s state-file enum re-validation list adds `intent:` against `{continue, stop, none}`, so a tampered value stops the run rather than reaching the `/plan` hop's argument string.
- [ ] An eval for each of `--intent=continue`, `--intent=stop`, and no `--intent` asserts the state file records `intent: continue`, `intent: stop`, and `intent: none` respectively (R3, state-file half; the `intent=` exit token is Issue 10).

*Reattach and mismatch refusal*

- [ ] `phase-0-setup.md` states that on a run whose state file already exists (reattach or resume), an explicit `--intent` differing from the recorded `intent:` is refused with the literal text `intent-mismatch recorded=<x> requested=<y>` and stops before any state write, session tick, or child invocation.
- [ ] `phase-0-setup.md` states that a bare re-invocation (no `--intent`) inherits the recorded value, and that an explicit `--intent` equal to the recorded value proceeds normally.
- [ ] `phase-0-setup.md` states that a state file with no `intent:` field (written before this change) is read as `intent: none`, so an explicit `--intent=continue|stop` against it is refused as a mismatch.
- [ ] An eval covers the mismatch: a topic whose state file records `intent: stop`, re-invoked with `--intent=continue`, expects the `intent-mismatch recorded=stop requested=continue` refusal and an unchanged state file; a second assertion or scenario expects a bare re-invocation of the same topic to reattach without refusal.

*Forwarding to the `/plan` hop*

- [ ] The `/plan` row of the per-child argument table in `phase-2-chain-orchestration.md` and the `hop_plan` directive in `scope.md` both state: when `intent:` is `continue` or `stop`, the hop receives `--intent=<value>`, the `--coordinated`/`--no-coordinated` flag only if the caller passed it on this invocation, and `/scope`'s own resolved mode flag (`--auto` or `--interactive`); all flags come before the `--` that precedes the quoted DESIGN path (R5).
- [ ] Both places state that `/scope` never forwards a `--coordinated` derived from a CLAUDE.md header, and that a no-intent hop sends exactly today's argument string (DESIGN path plus `--upstream` when recorded, with no `--intent`, coordination flag, or mode flag added) (R2, R8).
- [ ] An eval on `/scope <topic> --intent=continue` asserts the transcript's `/plan` Skill invocation carries `--intent=continue`; an eval on `/scope <topic> --intent=continue --no-coordinated` asserts it carries both `--intent=continue` and `--no-coordinated`; a no-intent eval asserts the `/plan` invocation carries none of `--intent`, `--coordinated`, `--no-coordinated` (R5, R8).

*Coordination Intent on intent runs*

- [ ] `skills/scope/SKILL.md` "Coordination Intent" states that when `--intent` is set, `/scope` never creates or authors a coordination PR up front (the publish step opens it at exit once the PLAN's mode is known), and that without `--intent` the up-front creation described there is unchanged (R8, D2).
- [ ] The same section distinguishes the new `--intent` flag from "coordination intent" (the `--coordinated`/header resolution) in one sentence, so a reader can't conflate the two.
- [ ] The abandonment directive in `scope.md` (the "close the coordination PR without merging" paragraph) states that an intent run skips the `gh pr close`, because no coordination PR exists before exit.
- [ ] The existing evals `coord-intent-creates-coordination-pr-up-front` and `coord-intent-absent-behavior-unchanged-r3` still pass unchanged, and a new eval for `/scope <topic> --intent=continue --coordinated` asserts no `gh pr create` happens before the first child runs (R8, R9 up-front half).

*Boundaries*

- [ ] No file under `skills/scope/` gains a Skill invocation of `/execute`, and an eval asserts no `execute-<topic>` koto session and no `/execute` state file exist after an intent run (R13).
- [ ] Every `skills/scope/scripts/*_test.sh` passes, and `skills/scope/koto-templates/scope.mermaid.md` is unchanged (this issue adds a variable, not a state or transition).

*Downstream deliverables*

- [ ] Must deliver: the `INTENT` koto variable declared with `default: none` and passed at every `koto init`, so a `{{INTENT}}` reference in a gate compiles and the `intent_declared` gate (`test "{{INTENT}}" != none`) is false on no-intent runs (required by Issue 10).
- [ ] Must deliver: the always-present `intent:` field in `/scope`'s state file, documented in `state-schema.md` and enum-re-validated, so the publish states and the exit summary can read `intent:` from the state file (required by Issue 10).
- [ ] Must deliver: no coordination PR exists before exit on an intent run, so the publish step's "reuse or create exactly one PR" logic never finds an up-front coordination PR (required by Issue 10).

**Dependencies**: Issue 2

**Type**: code

### Issue 10: feat(scope): publish one PR on intent runs and print exit tokens

**Goal**: On intent runs, make `/scope` push its branch and open or reuse exactly one owned PR through gated publish states. Every run prints the `intent=`/`outcome=`/`step=`/`next=`/`pr=`/`pr_state=`/`wip_paths=` exit lines. The resume ladder re-publishes on an existing PLAN and reports an already-executed topic, and the redirect, PLAN-status table, and enum re-validation become mode-correct.

**Context**: Today `/scope` never pushes and never opens a PR in single-repo mode. `skills/scope/SKILL.md` Security Considerations and `phase-3-exit-finalization.md` "Closed Write-Target Set" both say "Nothing pushes". The koto template `skills/scope/koto-templates/scope.md` runs `finalize -> exit_* -> cleanup_* -> done_*`, and cleanup deletes the state file R12 needs after a failure. `phase-4-cleanup.md` "Success Summary" prints only `/scope finished: exit=<exit>; artifact=<path>`. In `phase-resume.md`, row 5.1 (PLAN-Active) refuses and always redirects to `/work-on`, whatever the mode. Nothing handles a topic whose PLAN was already executed and removed by the cascade. The Full-Run Exit section in `phase-3-exit-finalization.md` says a single-pr PLAN is Draft, but `/plan`'s `phase-7-creation.md` authors every committed PLAN at `status: Active`. `phase-2-chain-orchestration.md` and `state-schema.md` still call `coordinated` "the multi-repo generalization of `multi-pr`".

Decision 5 puts three publish states (`publish_full_run`, `publish_re_evaluation`, `publish_abandonment`) between each exit state and its cleanup. An `intent_declared` gate (`test "{{INTENT}}" != none`, on the `INTENT` variable Issue 9 adds) sends no-intent runs through today's route with no `gh` call. Each publish state's `published` gate runs `publish-scoping-pr.sh --verify`. A failed publish records `publish_error:` and parks the run in the publish state, and re-running `/scope <topic>` retries idempotently. The Components list adds the resume rows: under `--intent` on an existing PLAN, the publish step re-runs and opens the PR when none is owned and open, so `/execute` only ever adopts a PR `/scope` opened. An executed topic prints `outcome=executed`, `pr=`, and `pr_state=merged|open` from the same ownership-filtered read. PR ownership means same repository (`isCrossRepository` false), the authenticated user as author, and the expected base. Zero or several matches is an error, never a pick. Pushes use an explicit `HEAD:refs/heads/<branch>` refspec, never force, and refuse a detached HEAD or the default branch. PR bodies come from a fixed template over validated fields, passed with `--body-file`.

`startable-issues.sh` wraps `plan-to-tasks.sh`, so it depends on the per-node `ISSUES` var from Issue 3.

Design: `docs/designs/DESIGN-scope-then-execute.md` (Considered Options > Decision 5; Decision Outcome seams "Intent mismatch" and "Finished single-pr topics"; Solution Architecture > Components > `/scope`; Key Interfaces > Exit lines and PR ownership; Data Flow step 3; Security Considerations; Implementation Approach > Phase 4)
PRD: `docs/prds/PRD-scope-then-execute.md` (R3, R9, R10, R11, R12, R13, R17, R23, R25, R28; Final States; Acceptance Criteria "`/scope` exit" and "Routing, status, and non-functional")

**Acceptance Criteria**:

*Koto template: publish states and the intent gate*

- [ ] `skills/scope/koto-templates/scope.md` declares the states `publish_full_run`, `publish_re_evaluation`, and `publish_abandonment`, each tagged `# phase: 3`. Each state carries a `published` command gate running `{{PLUGIN_ROOT}}/skills/scope/scripts/publish-scoping-pr.sh --verify --topic "{{TOPIC}}"` (plus whatever mode/exit arguments the script defines) and routes to `cleanup_full_run`, `cleanup_re_evaluation`, and `cleanup_abandonment` respectively, only when `gates.published.exit_code: 0` is paired with an evidence field.
- [ ] `exit_full_run`, `full_run_blocked`, `exit_re_evaluation`, and `exit_abandonment` each carry an `intent_declared` gate whose command is exactly `test "{{INTENT}}" != none`. Every existing arm into a `cleanup_*` state now also requires `gates.intent_declared.exit_code: 1`, and a parallel arm with `gates.intent_declared.exit_code: 0` targets the matching `publish_*` state. No transition from those four states reaches a `cleanup_*` state on an intent run without passing a publish state.
- [ ] Each publish state has an arm that stays in the state (or re-enters it) when `published` fails. The state's directive tells the agent to write `publish_error: <scope:push|scope:pr-create>` to the state file, print the error exit lines (see Exit lines below), and stop. The state file keeps its recorded `exit:` and exit-path fields (R12).
- [ ] The frontmatter `description` state count is updated to match the new total. `skills/scope/koto-templates/scope.mermaid.md` is regenerated and `scripts/validate-template-mermaid.sh` passes on it. `scripts/check-template-interpolation.sh`, `scripts/check-template-directives.sh`, and `koto template compile` all pass on the edited template.
- [ ] The directive sections for the three publish states name the publish steps in order: untrack the topic's own `wip/` prefixes with `git rm --cached` and a pathspec-restricted commit (the files stay on disk for cleanup), run the visibility check over `wip/` paths in unpushed history, push, reuse or create the PR, then tick so `published` verifies.

*`publish-scoping-pr.sh` and its test*

- [ ] `skills/scope/scripts/publish-scoping-pr.sh` exists with a publish mode and a `--verify` mode, and validates `--topic` against `^[a-z0-9-]+$` before composing anything. It reads the current branch with `git symbolic-ref --quiet --short HEAD` and exits non-zero with `scope:push`, making no `git push` and no `gh` write, when HEAD is detached, when the branch equals the repository's default branch, or when the branch name fails `git check-ref-format --branch`.
- [ ] The only push the script makes is `git push origin HEAD:refs/heads/<branch>`, with no `--force`, `-f`, `--force-with-lease`, or `+` refspec. `publish-scoping-pr_test.sh` greps the script and fails if any of those appear.
- [ ] Before the push, the script lists every `wip/` path in commits not yet on `origin` and runs the public-content visibility check over those files. A hit exits with `scope:push` and makes no push. A clean pass prints the paths for the `wip_paths=` exit line.
- [ ] PR lookup uses `gh pr list --head <branch> --state open --json number,url,isDraft,isCrossRepository,author,baseRefName,headRefName` and keeps only entries with `isCrossRepository == false`, `author.login` equal to `gh api user --jq .login`, `baseRefName` equal to the default branch, and `headRefName` equal to the branch. After that filter, one match is reused with no `pr create`. Zero matches issues one `gh pr create --head <branch> --base <default> --title <...> --body-file <file>`. Two or more matches exit with `scope:pr-create` and no write call.
- [ ] The created PR's title contains the topic slug. It's `--draft` for a `single-pr` or `coordinated` full-run and for `re-evaluation` and `abandonment-forced` exits, and not draft for a `multi-pr` full-run (R9). A `coordinated` body starts with the fixed coordination-PR declaration prefix and passes `shirabe validate --coordination-body`.
- [ ] The PR body is rendered from a fixed template containing only the slug, exit, outcome, mode, `docs/` artifact paths, and issue numbers. No free-text state field (`detail`, `failure_reason`, author prose) appears in it. It's passed with `--body-file`, never `--body`.
- [ ] `--verify` exits 0 only when `git ls-remote origin refs/heads/<branch>` equals `git rev-parse HEAD` and exactly one owned open PR exists on the branch under the same filter. It makes no `git push` and no `gh pr create`, `gh pr edit`, or `gh pr ready` call.
- [ ] `skills/scope/scripts/publish-scoping-pr_test.sh` runs against a stub `gh` and a local bare `origin` and covers each of these cases:
  - no PR: one `pr create`
  - one owned PR: zero `pr create`, and its URL is printed
  - `pr list --head <branch>` returns only a cross-repository PR: one fresh `pr create`, and the foreign URL is never printed as `pr=`
  - it returns only another author's PR: one fresh `pr create`, and the foreign URL is never printed
  - it returns only a PR with a non-default base: one fresh `pr create`, and that URL is never printed
  - two owned PRs plus a foreign one: exit with `step=scope:pr-create`, no `pr create`, and no `pr=` line
  - detached HEAD, and HEAD on the default branch: `scope:push`, with no push and no `gh` write logged
  - a failing `pr create`: `scope:pr-create`
  - no `origin` remote: `scope:push`
  - `--verify` where the owned PR exists but `git ls-remote origin refs/heads/<branch>` differs from HEAD: exit 1, and the stub logs no write call
  - `--verify` where the remote equals HEAD and one owned PR exists: exit 0
  - a second publish run after a successful one: no second `pr create` and no second push of a new commit
- [ ] A shell test (in `publish-scoping-pr_test.sh` or alongside it) asserts that `gh pr merge`, `gh pr review`, `--admin`, and `--auto` appear nowhere under `skills/scope/`.

*`startable-issues.sh` and its test*

- [ ] `skills/scope/scripts/startable-issues.sh <plan-path>` calls `plan-to-tasks.sh`, prints one `#<N> <title>` line per issue with no in-PLAN dependency, in PLAN order, reads titles from the PLAN's issue-table cells, and makes no `gh` call.
- [ ] Before printing, it strips CR, LF, and other control characters from each title, so a title containing a newline followed by `outcome=merged` stays on its own `#<N>` line and can't produce a separate `outcome=` line.
- [ ] `skills/scope/scripts/startable-issues_test.sh` uses a mixed-dependency fixture PLAN (two roots, a chain, and a diamond) and asserts exactly the two root issues in PLAN order. It also covers the control-character case, and fails if the script invokes `gh`.

*Exit lines (`phase-4-cleanup.md` Success Summary)*

- [ ] The Success Summary documents the block from Key Interfaces: `/scope finished: exit=<exit>; artifact=<path>`, then one `key=value` per line. `intent=<continue|stop|none>` is always printed. `outcome=<scoped|handed-off-multi-pr|executed|error>` is printed on a full-run, an executed-topic resume, or a publish failure. `step=<scope:push|scope:pr-create>` is printed on error only. `next=<command>` is printed on full-run only. `pr=<url>` is printed on intent runs only. `pr_state=<merged|open>` is printed on executed only. `wip_paths=<comma-separated>` is printed on intent runs with `wip/` in unpushed history. For multi-pr, the `#<N> <title>` lines follow, then one closing line.
- [ ] A full-run with a `single-pr` or `coordinated` PLAN prints `outcome=scoped` and `next=/execute docs/plans/PLAN-<topic>.md`. A `multi-pr` PLAN prints `outcome=handed-off-multi-pr` and `next=/work-on #<N>`, where N is the first line from `startable-issues.sh`. This holds with and without intent (R10, R11).
- [ ] On a multi-pr intent run, the closing line says the listed issues can start once the scoping PR merges and names its URL. Without intent, it says they can start once the PLAN is on the default branch and names no PR (R11).
- [ ] `re-evaluation` and `abandonment-forced` exits print no `outcome=` line (Final States). On intent runs they still print `intent=` and `pr=`.
- [ ] A publish failure prints `intent=<value>`, `outcome=error`, and `step=scope:push` or `step=scope:pr-create`, with no `pr=` line (R12).
- [ ] The `pr=` value is always the URL of the single owned PR from the ownership filter, and is checked against `^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[1-9][0-9]*$` before it's printed.

*Resume ladder (`phase-resume.md`, SKILL.md Resume Logic)*

- [ ] Rows 5.1 (PLAN-Active) and 5.3 (PLAN-Draft), when `--intent` is given, re-run the idempotent publish step and reprint the exit lines (`outcome=scoped` or `handed-off-multi-pr`, `next=`, `pr=`) instead of refusing. They invoke no child and create no BRIEF, PRD, or DESIGN commit.
- [ ] Under `--intent`, when a PLAN exists on the branch and no owned open PR exists, the re-run publish opens it: the shim logs exactly one `pr create` with `--head` equal to the topic branch.
- [ ] Without intent, row 5.1's refuse-and-redirect routes by the PLAN's `execution_mode`. It names `/execute docs/plans/PLAN-<topic>.md` for `single-pr` and `coordinated`, and `/work-on` for `multi-pr` (R23).
- [ ] A new executed-topic row matches when `docs/plans/PLAN-<topic>.md` is absent and `docs/designs/current/DESIGN-<topic>.md` exists with the status the cascade writes. It's evaluated before row 5.4, so row 5.4's Re-evaluate/Revise/Bail triad never fires for such a topic under `--intent`. Under `--intent` it runs `gh pr list --head <branch> --state all` through the same ownership filter and prints `outcome=executed`, `pr=<url>`, and `pr_state=merged` or `pr_state=open` from that PR's state. It invokes no child and makes no push or `pr create`.
- [ ] In the executed-topic row, zero owned PRs, several owned PRs, or one owned PR that was closed unmerged ends `outcome=error` with `step=scope:pr-create`, prints no `pr=` line, and never names a foreign PR.
- [ ] The Slot 5 row count and the high-order summary in `skills/scope/SKILL.md` Resume Logic match the new row set.

*PLAN status, enums, and state schema*

- [ ] The Full-Run Exit section in `phase-3-exit-finalization.md` lists `single-pr`, `multi-pr`, and `coordinated` each with the status `/plan`'s `phase-7-creation.md` writes for a committed PLAN, and the `exit_artifacts` example matches (R25).
- [ ] `phase-2-chain-orchestration.md` and `state-schema.md` no longer describe `coordinated` as multi-repo only. The enum re-validation still accepts `plan_execution_mode: coordinated` and rejects `plan_execution_mode: bogus`.
- [ ] `skills/scope/references/state-schema.md` documents `published_pr:` (the verified PR URL, written by the publish state and re-validated against the URL pattern above on read) and `publish_error:` (enum `{scope:push, scope:pr-create}`, cleared on a successful retry). Both fields are added to the enum/pattern re-validation list.

*Security Considerations and write set (R28)*

- [ ] `skills/scope/SKILL.md` Security Considerations adds a Publish group listing:
  - `git rm --cached` of the topic's own `wip/` prefixes with a pathspec-restricted commit
  - `git push origin HEAD:refs/heads/<branch>`, with no force and never to the default branch or a detached HEAD
  - `gh pr create`, the only `gh` write, with no `gh pr edit`, `ready`, `merge`, or `review`
  - the ownership filter
  - the fixed-template `--body-file` body
  - the `wip_paths=` report and the visibility check that stops the push

  The sentence "Nothing pushes." is replaced.
- [ ] `phase-3-exit-finalization.md` "Closed Write-Target Set" restates the Publish group without divergence, and `phase-4-cleanup.md` reads it back. A diff between the three lists shows the same write verbs and targets.
- [ ] `skills/scope/requires.tsv` gains `gh - - mode:intent`. The Phase 0 or publish directive runs `skill-preflight.sh scope --mode intent` when intent is `continue` or `stop`, and `scripts/check-skill-requires.sh` passes.

*Evals and the `gh` shim*

- [ ] `skills/scope/evals/fixtures/bin/gh` exists. It serves canned JSON per `EVAL_SCENARIO` from `skills/scope/evals/fixtures/scenarios/<scenario>/`, honors a trailing `--jq`, and appends each invocation's full argument list as one line to a call log. Scenario fixtures cover:
  - a local bare `origin`
  - a no-`origin` case
  - a failing `pr create`
  - an existing owned PR
  - a foreign-only PR (cross-repository)
  - a merged and an open owned PR for the executed topic
- [ ] Eval `no-intent-makes-no-gh-call` runs `/scope <topic>` with no `--intent` on the no-split fixture and asserts the shim's call log is empty, no push happened, and `git ls-remote origin` shows no topic branch (R2).
- [ ] Evals assert:
  - `--intent=continue` on the no-split fixture logs one `pr create --draft` on the topic branch whose title contains the slug, and `git ls-remote origin` shows the branch
  - on the forced-split fixture, exactly one `pr create` (draft, body with the declaration prefix)
  - `--intent=stop` on the forced-split fixture creates a PR that isn't a draft
  - `--intent=continue --coordinated` on the multi-repo fixture logs exactly one `pr create`, after the PLAN hop

  (R9)
- [ ] Evals assert that `--intent=continue` runs ending `re-evaluation` and, separately, `abandonment-forced` each log a push and one `pr create --draft` (R9).
- [ ] Evals assert that with a failing `pr create` the state file still records `exit:` and the run prints `outcome=error` and `step=scope:pr-create`, and that with no `origin` it prints `step=scope:push`. A re-run of `/scope <topic>` after fixing the scenario reattaches, publishes, and reaches `done_full_run` (R12).
- [ ] An eval on the mixed-dependency fixture asserts:
  - an `--intent=stop` multi-pr exit lists exactly the two roots, in PLAN order, names the scoping PR, and prints `outcome=handed-off-multi-pr` and `next=/work-on #<first root>`
  - the no-intent run lists the same two roots and names no PR

  (R10, R11)
- [ ] Evals for resume:
  - `--intent=continue` on a branch with an Active single-pr PLAN and no owned PR logs one `pr create` on the topic branch and no BRIEF/PRD/DESIGN commit
  - the same with an existing owned PR logs no `pr create` and prints that PR as `pr=`
  - an executed topic with a merged owned PR prints `outcome=executed`, `pr_state=merged`, and the PR's URL
  - an executed topic whose only PR on the branch is cross-repository prints `outcome=error` and `step=scope:pr-create`, and never prints the foreign URL

  (R17)
- [ ] An eval asserts no `execute-<topic>` koto session and no `/execute` state file exist after any intent run (R13). An eval on an Active PLAN without intent asserts the redirect names `/execute` for single-pr and coordinated and `/work-on` for multi-pr (R23).
- [ ] Every new eval declares the requirement IDs it covers. Every `skills/scope/scripts/*_test.sh` passes. The existing `/scope` evals pass, and the only assertions changed are ones about R10 or R23 text.

*Downstream deliverables*

- [ ] Must deliver: exit lines in the exact `key=value` shape and order above, covering `intent=`, `outcome=` in `{scoped, handed-off-multi-pr, executed, error}`, `step=`, `next=`, `pr=`, `pr_state=`, and `wip_paths=`, each pinned by an eval, so `/deliver` can parse them by anchored key (required by Issue 11).
- [ ] Must deliver: the `intent-mismatch recorded=<x> requested=<y>` refusal line from Issue 9 reaches the output unchanged on every resume path this issue adds, so `/deliver` can map it to `deliver:intent-mismatch` (required by Issue 11).
- [ ] Must deliver: on a PLAN branch with no owned PR, `/scope --intent=continue` opens it during resume, so `/execute` only adopts and never creates its own home PR on a `/deliver` run (required by Issue 11).
- [ ] Must deliver: the executed-topic row's `outcome=executed` with `pr_state=merged|open`, which `/deliver` relays as `merged` or `ready-awaiting-merge` without running `/execute` (required by Issue 11).

**Dependencies**: Issue 9, Issue 3

**Type**: code

### Issue 11: feat(deliver): add the /deliver driver skill

**Goal**: Add a stateless `/deliver <topic>` skill that always enters through `/scope <topic> --intent=continue`, asks one Proceed/Stop confirmation when interactive, runs `/execute docs/plans/PLAN-<topic>.md` with `--merge` unless `--no-merge`, and ends by printing exactly one named final state plus the PR, write-set, and `wip/` lines its children printed.

**Context**: Today no skill can take a feature from scoping to merged code in one session, and the parent-skill pattern names a parent-of-the-parent slot that nothing fills. Decision 4 settles the shape: `/deliver` is a SKILL.md that sequences two inline Skill calls. It has no koto template, no state file, and no phase files, and it never reads `/scope`'s or `/execute`'s state files or koto sessions. Everything it knows comes from three places: the flags it was given, the `key=value` exit lines its children print (see Key Interfaces > Exit lines), and the PLAN's `execution_mode` frontmatter.

The sequence (Solution Architecture > `/deliver` sequence) is:

1. Check CLAUDE.md's `## Repo Visibility:` header and refuse a private repository before anything runs (R29).
2. Run `/scope <topic> --intent=continue` with the forwarded flags and the resolved mode flag. `/scope` owns every "where did this topic stop" question through its own resume ladder, which is why `/deliver` enters through it even when a PLAN already exists. Its exit lines are mapped as follows:
   - intent-mismatch refusal: `outcome=error step=deliver:intent-mismatch`
   - `outcome=error`: relayed with its step
   - `re-evaluation` or `abandonment-forced` exit (no `outcome=` token): `outcome=scope-ended-early` naming which
   - `outcome=handed-off-multi-pr`: relayed with its startable-issue list (R16)
   - `outcome=executed`: `pr_state=merged` becomes `outcome=merged`, `pr_state=open` becomes `outcome=ready-awaiting-merge`, with `/scope`'s `pr=` relayed and no `/execute` run
   - `outcome=scoped`: re-read `docs/plans/PLAN-<topic>.md`. A missing PLAN is `deliver:child-outcome`, `multi-pr` is handed off, anything else continues.
   - anything else: `outcome=error step=deliver:child-outcome`
3. Interactively, ask one Proceed/Stop question naming the PLAN's mode. Stop ends `outcome=scoped` with `next=/deliver <topic>`.
4. Run `/execute docs/plans/PLAN-<topic>.md` with the mode flag and `--merge` unless `--no-merge`, then relay `/execute`'s `outcome=`, `step=`, `pr=` (with `waiting=` and `reason=`), and `repos=` lines, its resume command on a pause, and `/scope`'s `wip_paths=` line.

Because every run passes through `/scope`, a topic whose PLAN exists on the checked-out branch but whose PR was never opened (a publish that failed after the PLAN was written) gets its PR opened by `/scope`'s re-run publish step, and `/execute` then adopts that PR. `/execute` never creates the home PR on a `/deliver` run. `/deliver` itself makes no `gh` call, so its `requires.tsv` carries only the schema line (the design's Components > `/deliver`).

The PRD requirements this issue implements are R14-R18, R28's `/deliver` clause, and R29, together with the PRD's Interfaces rows for `/deliver`, its Final States table, and the `/deliver` acceptance criteria. The README row for `/deliver` and the guide updates land in Issue 12, not here.

**Acceptance Criteria**:

*Skill layout*

- [ ] `skills/deliver/SKILL.md` exists, with frontmatter fields `name: deliver`, a `description` in the same "Use it when... Do NOT use it for..." style as the other skills (naming `/scope`, `/execute`, and `/work-on` as the alternatives), an `argument-hint` listing `<topic-slug> [--auto|--interactive] [--no-merge] [--upstream <path>] [--max-rounds <n>] [--coordinated|--no-coordinated]`, and `allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)`.
- [ ] The first body line of `SKILL.md` is the preflight call `` !`bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh deliver 2>&1 || true` ``, matching `skills/execute/SKILL.md` and `skills/writing-style/SKILL.md`.
- [ ] `wc -l skills/deliver/SKILL.md` reports 250 or fewer lines.
- [ ] `skills/deliver/` contains no `koto-templates/` directory and no `references/phases/` directory, and `SKILL.md` contains no `koto init`, `koto next`, `koto status`, or `koto context` line and names no `wip/` state file it writes.
- [ ] `SKILL.md` never reads `/scope`'s or `/execute`'s state files or koto sessions: it names neither `/scope`'s nor `/execute`'s state file path, and its only inputs from the children are their printed exit lines and the PLAN's `execution_mode` frontmatter.
- [ ] `skills/deliver/requires.tsv` has `#schema<TAB>skill-requires/v1` as its first line and no record lines (comment lines only), with a comment stating that `/deliver` calls no tool itself and writes only through `/scope` and `/execute`, in the style of `skills/writing-style/requires.tsv`.
- [ ] `SKILL.md` contains no `gh` or `git` command line (a grep for lines beginning with `gh ` or `git ` inside code blocks returns nothing).
- [ ] `SKILL.md` has a write-target section declaring that `/deliver` writes nothing itself and writes only through its children, `/scope` and `/execute` (R28).
- [ ] `SKILL.md` identifies `/deliver` as the parent-of-the-parent and cites `references/parent-skill-pattern.md`'s "Parent-of-the-Parent Binding" subsection and `references/parent-skill-child-inspection.md`, rather than describing itself as a fourth parent.
- [ ] `scripts/check-skill-requires.sh` and `scripts/check-evals-exist.sh` both pass, and the latter lists `deliver` among the passing skills.
- [ ] `.claude-plugin/plugin.json` is unchanged; the skill is discovered from its `skills/deliver/` directory.

*Flags and input validation*

- [ ] The topic slug is checked against `^[a-z0-9-]+$` before any child runs. A bad slug prints a refusal naming the rule, and no Skill call to `/scope` or `/execute` happens.
- [ ] `--upstream` is accepted only as a repository-relative path under `docs/` (no leading `/`, no `..` segment), and `--max-rounds` only as a bounded integer. A value outside either rule is refused before any child runs.
- [ ] `--upstream`, `--max-rounds`, `--coordinated`, and `--no-coordinated` are forwarded to `/scope` unchanged, each as its own Skill argument, and are not passed to `/execute`.
- [ ] The run mode is resolved once, in this order: `--auto` or `--interactive` if given, else CLAUDE.md's `## Execution Mode:` header, else interactive. The resolved `--auto` or `--interactive` flag is passed to both `/scope` and `/execute` (R15).
- [ ] `--merge` is passed to `/execute` on every run unless `/deliver` was invoked with `--no-merge`. Nothing about the merge setting is stored between runs, so a re-invocation without `--no-merge` passes `--merge` even if the earlier run used `--no-merge` (R14, R17).

*Sequence and mapping*

- [ ] Before invoking any child, `/deliver` reads `## Repo Visibility:` from CLAUDE.md. When it's `Private`, it prints a refusal and invokes neither `/scope` nor `/execute` (R29).
- [ ] Every run invokes `/scope <topic> --intent=continue` first, including runs where `docs/plans/PLAN-<topic>.md` already exists on the checked-out branch. `/deliver` never checks for the PLAN before calling `/scope`.
- [ ] Exit lines are parsed by anchored key (`^outcome=`, `^step=`, `^pr=`, `^pr_state=`, `^next=`, `^wip_paths=`, `^repos=`); no other text from a child's output is interpreted.
- [ ] Each `/scope` result maps exactly as the Context section's step 2 lists: intent-mismatch refusal to `outcome=error step=deliver:intent-mismatch`; `outcome=error` relayed with its `step=`; a `re-evaluation` or `abandonment-forced` exit to `outcome=scope-ended-early` naming which; `handed-off-multi-pr` relayed with its startable-issue lines and no `/execute` call; `executed` with `pr_state=merged` to `outcome=merged` and with `pr_state=open` to `outcome=ready-awaiting-merge`, each relaying `/scope`'s `pr=` line with no `/execute` call; `scoped` to a PLAN re-read; any other record to `outcome=error step=deliver:child-outcome`.
- [ ] After `outcome=scoped`, `/deliver` reads `execution_mode` from `docs/plans/PLAN-<topic>.md` rather than trusting `/scope`'s `next=` line. A missing PLAN ends `outcome=error step=deliver:child-outcome`. `multi-pr` ends `outcome=handed-off-multi-pr` with the startable-issue list and no `/execute` call (R16). `single-pr` or `coordinated` continues. Any other value ends `deliver:child-outcome`.
- [ ] In interactive mode, exactly one Proceed/Stop question is asked between `/scope` returning and `/execute` starting, and its text names the PLAN's mode. Choosing Stop ends `outcome=scoped` and prints `next=/deliver <topic>`, with no `/execute` call. In `--auto` mode, no question is asked (R15).
- [ ] `/execute` is invoked as `/execute docs/plans/PLAN-<topic>.md` plus the resolved mode flag, plus `--merge` unless `--no-merge` (R14).
- [ ] After `/execute` returns, `/deliver` relays its `outcome=` token, its `step=` line on error, every `pr=<url> waiting=human|predecessor reason=<condition>` line, its `repos=` line, and the resume command on a pause, plus `/scope`'s `wip_paths=` line when `/scope` printed one (R18). An `/execute` outcome outside the Final States `/deliver` emits ends `outcome=error step=deliver:child-outcome`.
- [ ] Every `/deliver` run prints exactly one `outcome=` line of its own, whose token is one of `merged`, `ready-awaiting-merge`, `paused-awaiting-merges`, `paused-for-review`, `scoped`, `handed-off-multi-pr`, `scope-ended-early`, or `error`, and every `error` has a `step=` line (R18).

*Evals*

- [ ] `skills/deliver/evals/evals.json` exists with `skill_name: deliver`, and every scenario names the requirement IDs it covers in its `name` or `expected_output`.
- [ ] A `gh` shim with a call log lives at `skills/deliver/evals/fixtures/bin/gh`, serving at least the mergeable, not-mergeable, CI-red, and executed-topic scenarios, alongside no-split, forced-split, and single-repo coordinated fixture designs and a private-repo fixture.
- [ ] Scenario: `/deliver <topic> --auto` on the no-split fixture with the mergeable scenario logs exactly one `pr merge` call, prints `outcome=merged`, and asks no question between `/scope` and `/execute` (R14, R15).
- [ ] Scenario: `/deliver <topic> --interactive` on the same fixture asks one confirmation naming `single-pr` before `/execute` starts; a variant where the author picks Stop prints `outcome=scoped` and `next=/deliver <topic>` and starts no `/execute` session (R15).
- [ ] Scenario: `/deliver <topic>` with no mode flag in a fixture whose CLAUDE.md has `## Execution Mode: auto` asks no question (R15).
- [ ] Scenario: `/deliver <topic> --interactive`, after confirmation, ends `outcome=paused-for-review` with the home PR still draft when the author declines finalization at `/execute`'s review pause.
- [ ] Scenario: `/deliver <topic> --auto --no-merge` with the mergeable scenario logs no `pr merge` call and prints `outcome=ready-awaiting-merge` (R14).
- [ ] Scenario: `/deliver <topic> --auto --no-coordinated` on the forced-split fixture starts no `/execute` session and prints `outcome=handed-off-multi-pr` with the root-issue list (R16).
- [ ] Scenario: re-invoking `/deliver` after a run stopped during the PRD hop resumes at the PRD hop and creates no new BRIEF commit (R17).
- [ ] Scenario: re-invoking `/deliver` on a checked-out branch whose PLAN exists and has an open owned PR logs zero `pr create` calls, `/execute` adopts that PR, and no BRIEF, PRD, or DESIGN commit is made (R17).
- [ ] Scenario: re-invoking `/deliver` on a checked-out branch whose PLAN exists and has no PR logs exactly one `pr create` call, on the topic branch, made during `/scope`'s publish step; the shim logs no `pr create` and no push with an `impl/<topic>` head; `/execute` adopts the PR `/scope` opened; and no BRIEF, PRD, or DESIGN commit is made (R17).
- [ ] Scenario: re-invoking `/deliver` on a topic whose unfinished `/scope` run recorded `intent: stop` prints `outcome=error` and `step=deliver:intent-mismatch`, and the shim log and the working tree show no change (R17).
- [ ] Scenario: re-invoking `/deliver` on a topic whose PLAN was executed and removed (DESIGN under `docs/designs/current/`) with the shim reporting the branch's PR merged prints `outcome=merged` and that PR's `pr=` line; with the PR open, it prints `outcome=ready-awaiting-merge`. Neither starts an `/execute` session nor logs a `pr merge` call (R17).
- [ ] Scenario: a `/deliver` run whose `/scope` ends `re-evaluation` prints `outcome=scope-ended-early` naming `re-evaluation` and starts no `/execute` session (R18).
- [ ] Scenario: a `/deliver` run with the CI-red scenario prints `outcome=error` and `step=execute:ci` (R18).
- [ ] Scenario: a coordinated `/deliver` run on the single-repo coordinated fixture with the not-mergeable scenario prints `outcome=paused-awaiting-merges`, lists each unmerged PR with `waiting=human` or `waiting=predecessor`, prints a resume command, and relays a `repos=` line (R18).
- [ ] Scenario: `/deliver` on the private-repo fixture refuses before any child runs, logs no `gh` call, and writes no file (R29).
- [ ] Every scenario above passes 3 of 3 runs via `scripts/run-evals.sh deliver`, run by an agent with `/skill-creator` loaded as the repository's "Skill Evals" section requires.

*Downstream deliverables*

- [ ] Must deliver: `skills/deliver/SKILL.md` with a flag table (`--auto`/`--interactive`, `--no-merge`, `--upstream`, `--max-rounds`, `--coordinated`, `--no-coordinated`, with their defaults) and a final-states table listing each `outcome=` token `/deliver` can print and when, so the guides can document them without re-deriving behavior (required by Issue 12).
- [ ] `/deliver` relays `/execute`'s `resume=` line verbatim when the outcome is `paused-awaiting-merges`, and an eval asserts it appears in `/deliver`'s final report.

**Dependencies**: Issue 7, Issue 10, Issue 6

**Type**: code

### Issue 12: docs(guides): document /deliver, intent, single-repo coordinated, and --merge

**Goal**: Update `docs/guides/coordinated-multi-repo.md`, `docs/guides/execute-friction.md`, and `README.md` so users can find and correctly use `/deliver`, `/scope --intent`, single-repo coordinated mode, and `/execute --merge`, and so none of the three files still describes the pre-feature behavior.

**Context**: Phase 5 of the design lists three documentation deliverables alongside the `/deliver` skill: a README row, a single-repo section in the coordinated guide that names the intent route and `/execute` as the driver, and a section in the execute guide covering `/deliver`, `/scope --intent`, and `/execute --merge` that replaces advice assuming `/scope` leaves an open PR.

Today all three files describe the old behavior. `coordinated-multi-repo.md` says coordinated mode is for work spanning more than one repository ("If your change lives in one repo, stay on the single-repo chain"), gives intent precedence as `flag > CLAUDE.md-header > default` with no intent level, says `/scope` creates the coordination PR up front, and names `/work-on` as the skill that tracks and re-authors the coordination PR. `execute-friction.md` tells the reader to run `/execute` from "the `docs/<topic>` scoping branch `/scope` left you on" with an already-open PR, describes coordinated mode as spanning more than one repository with per-repo worktrees, and says `--auto` delivers a "ready-to-merge" PR with no mention of merging. `README.md` has no `/deliver` row, describes `/execute` as owning "coordinated multi-repo plans", and its "Coordinated multi-repo" section says the coordination PR "is created up front".

After this feature, per the design:

- `/deliver <topic>` runs `/scope <topic> --intent=continue`, asks one Proceed/Stop question when interactive, then runs `/execute` with `--merge` unless `--no-merge`, and ends in one named outcome (`merged`, `ready-awaiting-merge`, `paused-awaiting-merges`, `paused-for-review`, `scoped`, `handed-off-multi-pr`, `scope-ended-early`, or `error` with a `step=`). It stops at `handed-off-multi-pr` for a `multi-pr` PLAN and resumes by re-invocation on the same topic.
- `/scope --intent=continue|stop` pushes its branch and opens exactly one PR at exit (draft home PR for single-pr, draft coordination PR for coordinated, ready PR for multi-pr) and prints `intent=`, `outcome=`, `next=`, and `pr=` lines. Without `--intent`, `/scope` behaves as before and opens no PR.
- A split resolves to `coordinated` or `multi-pr` by the precedence: explicit `--coordinated`/`--no-coordinated` > `--intent` (`continue` means coordinated, `stop` means multi-pr) > CLAUDE.md coordination headers > default `multi-pr`. Coordinated works in one repository, with one branch (`impl/<slug>-<node-id>`) and one PR per PR node, cut from the default branch. With `--intent` set, the coordination PR is opened at `/scope` exit rather than up front.
- `/execute` drives coordinated PLANs (not `/work-on`). `/execute --merge` merges only a ready, CI-green, cleanly mergeable PR at the commit the run pushed, on a base branch that requires checks or reviews; it never uses an admin or bypass option; coordinated merges follow the merge order with the coordination PR last. Without `--merge`, `/execute` never merges and ends `ready-awaiting-merge`.

**Acceptance Criteria**:

*`README.md`*

- [ ] The "Execute chain" skill table has a `/deliver` row stating that it runs `/scope --intent=continue` then `/execute --merge` (merging off with `--no-merge`) in one session, and that it hands off rather than executes a `multi-pr` plan.
- [ ] The `/execute` row no longer says "coordinated multi-repo plans"; it says it owns single-pr and coordinated plans (one repository or several) and mentions the opt-in `--merge`.
- [ ] The `/scope` row mentions that `--intent` pushes the branch and opens the scoping PR at exit.
- [ ] The "Coordinated multi-repo" section no longer states the coordination PR is "created up front" without qualification; it says coordinated mode works in one repository or several and that intent runs open the coordination PR at `/scope` exit.
- [ ] The intro paragraph listing each altitude's parent skill mentions `/deliver` as the driver that runs `/scope` then `/execute`.

*`docs/guides/coordinated-multi-repo.md`*

- [ ] The guide no longer says coordinated mode requires more than one repository: the sentences "the work spans more than one repository" (as a required condition) and "If your change lives in one repo, stay on the single-repo chain" are removed or rewritten.
- [ ] A section titled for single-repo coordinated use exists and states: one branch and one PR per PR node, branches named `impl/<slug>-<node-id>` and cut from the default branch (not from the coordination branch), node PRs merge in the merge order, and the coordination PR merges last.
- [ ] The intent-precedence text lists all four levels in order: explicit `--coordinated`/`--no-coordinated` flag, `--intent`, CLAUDE.md coordination headers, default `multi-pr`; it states `--intent=continue` resolves a split to `coordinated` and `--intent=stop` to `multi-pr`, and that `/plan` accepts these flags directly.
- [ ] The guide states that on an `--intent` run the coordination PR is opened at `/scope` exit once the PLAN's mode is known, and that the up-front creation applies only to runs without `--intent`.
- [ ] Every place that names the skill driving or re-authoring a coordinated PLAN names `/execute`, not `/work-on` (including the lifecycle "Track" step and the closing "consumers" sentence).
- [ ] The lifecycle section describes the `/execute --merge` step (node PRs merged in order, coordination PR last) and the `paused-awaiting-merges` outcome, with re-invoking `/execute` (or `/deliver`) as the way to resume.
- [ ] The guide mentions `/deliver` as a one-command route into coordinated mode.

*`docs/guides/execute-friction.md`*

- [ ] The single-pr section no longer assumes `/scope` leaves you on a branch with an open PR: the phrase "the `docs/<topic>` scoping branch `/scope` left you on" and the instruction "if you ran `/scope` and are sitting on its branch, just run `/execute` from there" are rewritten so that the open PR is attributed to `/scope --intent` (or `/deliver`), and plain `/scope` is described as leaving no PR (so `/execute` cuts `impl/<slug>`).
- [ ] The coordinated section no longer states "A coordinated PLAN spans more than one repository"; it describes per-node branches and PRs that work in one repository or several.
- [ ] A new section covers `/deliver`: what it runs, the single interactive Proceed/Stop confirmation, `--no-merge`, the `multi-pr` hand-off, resume by re-invoking on the same topic, and the list of named final outcomes.
- [ ] A new section (or subsection) covers `/scope --intent=continue|stop`: the PR it opens per mode (draft home, draft coordination, ready for multi-pr) and the `intent=`/`outcome=`/`next=`/`pr=` exit lines.
- [ ] A new section covers `/execute --merge`: it is opt-in (never merges without the flag), the conditions it requires before merging (ready PR, every check passed, clean merge state, head equals the commit the run pushed, base branch requires checks or reviews, approving review where required or where workflow files change), no admin/bypass option, and the `merged` versus `ready-awaiting-merge` outcomes, including the 30-minute CI wait limit.
- [ ] The `--auto` section no longer implies the run's end state is always an unmerged "ready-to-merge" PR without mentioning that `--merge` (on by default under `/deliver`) can merge it.

*All three files*

- [ ] No remaining text in the three files claims coordinated mode is "multi-repo only" or that `/work-on` drives a coordinated PLAN.
- [ ] Every relative link added or changed resolves to an existing file.
- [ ] The prose follows the repo's writing-style guidance (`shirabe validate` reports no FC10 writing-style notices on the changed files).

**Dependencies**: Issue 11

**Type**: docs

## Dependency Graph

## Implementation Sequence

Critical path: Issue 1 -> 4 -> 5 -> 7 -> 6 -> 11 -> 12 (seven issues). The
merge work is the longest and highest-risk chain, so start it first after the
shared contracts land.

1. Issue 1 (shared contracts).
2. In parallel: Issue 4 (merge scripts), Issue 2 (`/plan` flags), Issue 3
   (`plan-to-tasks.sh` vars), Issue 8 (validator tests).
3. Issue 5 (`/execute --merge`, single-pr) after 4; Issue 9 (`/scope
   --intent`) after 2.
4. Issue 7 (coordinated in one repository) after 3 and 5; Issue 10 (`/scope`
   publish) after 9 and 3.
5. Issue 6 (merged wording and its check) after 5 and 7, so its allowlist is
   written against the final `/execute` text.
6. Issue 11 (`/deliver`) after 6, 7, and 10.
7. Issue 12 (guides and README) last.

Two tracks run side by side after Issue 1: the `/execute` track (4, 5, 7, 6)
and the `/plan`-`/scope` track (2, 9, 10, with 3 feeding both), joining at
Issue 11.
