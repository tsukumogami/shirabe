# Lead: What is the complete, code-derived inventory of states, prose steps, scripts and references in each skill, and what does `/execute` have that `/work-on` lacks?

## Findings

All line numbers are against `main` at commit `9f84fa7` (branch `docs/work-on-standalone-completeness`, HEAD `e16a6ff` which only adds this exploration's brief doc; the skill files themselves are unchanged from `9f84fa7`).

### 1. State inventory — `/work-on` (`skills/work-on/koto-templates/work-on.md`)

28 states, declared at `states:` (line 41) through the closing `---` (line 838). Counted by grepping `^  [a-zA-Z_][a-zA-Z0-9_]*:$` inside the frontmatter block; every name below also has a matching `## <state>` prose header (lines 841-1227), confirmed 1:1 except that 3 setup states each get their own header (no sharing).

| State | Declaration line | One-line description |
|---|---|---|
| `entry` | 44 | Determine workflow mode (issue_backed / free_form / plan_backed / skipped) from entry evidence. |
| `context_injection` | 77 | Issue-backed only: fetch the GitHub issue into `context.md` via `extract-context.sh`. |
| `task_validation` | 105 | Free-form only: judge whether the task description is clear/scoped enough to implement directly. |
| `validation_exit` | 122 | Terminal; free-form task was rejected as not ready (needs design / narrower scope). |
| `research` | 125 | Free-form only: gather codebase context before validating scope a second time. |
| `post_research_validation` | 136 | Free-form only: re-judge scope now that research findings are in hand. |
| `setup_issue_backed` | 159 | Create/confirm feature branch + baseline for an issue-backed run. |
| `setup_free_form` | 191 | Create/confirm feature branch + baseline for a free-form run. |
| `plan_context_injection` | 223 | Plan-backed only: pull issue context from GitHub or from the PLAN outline. |
| `plan_validation` | 268 | Plan-backed/outline-sourced only: judge whether the outline item is clear enough to implement. |
| `setup_plan_backed` | 285 | Create/confirm branch for a plan-backed child (skippable when `SHARED_BRANCH` is set). |
| `staleness_check` | 321 | Gate: has the codebase drifted enough since the issue was filed to warrant re-reading it. |
| `introspection` | 355 | Re-validate the issue against current code after staleness flags drift; can mark issue superseded. |
| `analysis` | 384 | Produce `plan.md`; classify `issue_type` (code/docs/task); detect already-complete issues. |
| `implementation` | 431 | Write code/commits; self-loops on `partial_tests_failing_retry`; routes by `issue_type`. |
| `scrutiny` | 502 | Three-reviewer panel (completeness/justification/intent) gate on the implementation. |
| `review` | 532 | Three-reviewer code-review panel (pragmatic/architect/maintainer) gate. |
| `qa_validation` | 562 | QA panel gate. |
| `verification` | 592 | Definition-of-done gate: run the project's verification-map commands and require a pass. |
| `finalization` | 630 | Decide `ready_for_pr` / `deferral_requested` / `issues_found`; writes `summary.md`. |
| `deferral_approval` | 663 | Blocking human-approval gate for a deferred acceptance criterion. |
| `pr_precheck` | 695 | koto-run branch read (refuses `main`) that feeds `BRANCH` to the next two states. |
| `pr_creation` | 752 | Push and `gh pr create` (or `pr_status: shared` when riding a plan orchestrator's branch). |
| `ci_monitor` | 777 | Poll `gh pr checks`; fix and retry, or escalate unresolvable failures. |
| `done` | 820 | Terminal: PR created, CI green. |
| `done_already_complete` | 823 | Terminal: analysis found the issue already satisfied by current code. |
| `done_blocked` | 826 | Terminal/failure: any blocking condition from any of the above states. |
| `skipped_due_to_dep_failure` | 836 | Terminal/skipped: koto's `skip_dependents` policy bypassed this child. |

This is **28**, exactly matching issue #361's claim.

### 2. State inventory — `/execute` (`skills/execute/koto-templates/execute.md`)

14 states, declared at `states:` (line 34) through the closing `---` at line 491. Prose headers at lines 494-758, 1:1 with declarations.

| State | Declaration line | One-line description |
|---|---|---|
| `orchestrator_setup` | 49 | Create (or adopt) the shared `impl/<slug>` branch and open the draft PR, once, before children spawn. |
| `settled_branch_record` | 71 | koto-run action: record the branch every child will commit to, gated by regex match (no override edge — deliberately). |
| `worktree_sync` | 170 | koto-run `git fetch && git rebase origin/main`, gated on ancestor-check + no rebase-in-progress. |
| `worktree_discipline_check` | 233 | Judge whether upstream drift (from `worktree_sync`) is intent-changing for the PLAN. |
| `escalate_upstream_drift` | 279 | Terminal path (→`done_blocked`) when upstream drift invalidates the PLAN's intent. |
| `spawn_and_await` | 290 | Materialize one `work-on.md` child per PLAN issue (via `plan-to-tasks.sh`), await batch completion. |
| `pr_finalization` | 317 | Author the conventional-commit title + two-part body on the shared PR; mode-driven pause decision. |
| `ci_monitor` | 369 | Poll `gh pr checks` **and** `mergeStateStatus`; routes DIRTY separately from failing/passing. |
| `escalate_dirty_merge_state` | 418 | Terminal path (→`done_blocked`) when the PR's merge state is DIRTY. |
| `plan_completion` | 429 | Run `run-cascade.sh --push` (PLAN deletion + BRIEF/PRD/DESIGN/ROADMAP transitions, pushed) then `gh pr ready`. |
| `escalate` | 457 | Terminal path (→`done_blocked`) when one or more children failed/were skipped. |
| `paused_for_review` | 468 | Terminal **suspension** (not failure, not completion) when interactive mode pauses before the cascade. |
| `done` | 482 | Terminal: all children succeeded, PR body finalized, CI green. |
| `done_blocked` | 485 | Terminal/failure: any blocking condition from any of the above states. |

This is **14**, exactly matching issue #361's claim.

### 3. State comparison

**In `/execute`, with no counterpart in `/work-on`** (all plan-level orchestration, not per-issue work):
`orchestrator_setup`, `settled_branch_record`, `worktree_sync`, `worktree_discipline_check`, `escalate_upstream_drift`, `spawn_and_await`, `pr_finalization`, `escalate_dirty_merge_state`, `plan_completion`, `escalate`, `paused_for_review`. That is 11 of `/execute`'s 14 states with zero analog in `/work-on`. Everything downstream of "PR exists" that turns a PR into a merge-ready, chain-finalized PR — `gh pr ready`, the doc-cascade (PLAN deletion, BRIEF/PRD/DESIGN/ROADMAP transitions), DIRTY-merge-state detection, and the PR body's conventional title/two-part-body/`Fixes #N` authoring — lives **only** in `plan_completion` and `pr_finalization`, both `/execute`-only states.

**In `/work-on`, with no counterpart in `/execute`** (per-issue work `/execute` never does itself — it delegates all of this to spawned `work-on.md` children):
`entry`, `context_injection`, `task_validation`, `validation_exit`, `research`, `post_research_validation`, `setup_issue_backed`, `setup_free_form`, `plan_context_injection`, `plan_validation`, `setup_plan_backed`, `staleness_check`, `introspection`, `analysis`, `implementation`, `scrutiny`, `review`, `qa_validation`, `verification`, `finalization`, `deferral_approval`, `pr_precheck`, `pr_creation`, `done_already_complete`, `skipped_due_to_dep_failure`. 25 of 28. This is expected — `/execute` is a thin coordinator and never re-implements single-issue mechanics (`skills/execute/SKILL.md:22-23`).

**Same name, materially different behavior:**
- `ci_monitor` — `/work-on`'s gates only on `ci_passing` (`skills/work-on/koto-templates/work-on.md:781-786`, one command gate). `/execute`'s adds a second gate, `merge_state_clean` (`skills/execute/koto-templates/execute.md:398-400`), and a fourth outcome value `dirty_merge_state` that routes to a state `/work-on` doesn't have (`escalate_dirty_merge_state`). `/execute`'s prose explicitly documents why: a DIRTY PR suppresses new check-runs, and the `length==0` gate expression can't tell "all green" from "no checks ran because DIRTY" (`skills/execute/koto-templates/execute.md:683-693`).
- `done` — in `/work-on` this means "PR created, CI green" (`skills/work-on/koto-templates/work-on.md:1199-1201`). In `/execute` it means the whole PLAN's children succeeded, the shared PR's body was finalized, the doc-cascade ran, `gh pr ready` fired, and CI is green on the now-ready PR (`skills/execute/koto-templates/execute.md:754-756`). `/execute`'s `done` is strictly further down the mergeability path than `/work-on`'s.
- `done_blocked` — same terminal shape (`terminal: true`, `failure: true`, `failure_reason` context assignment) in both, but the set of originating states differs entirely per the state lists above; `/work-on`'s `done_blocked` prose (lines 1209-1221) even documents a `koto rewind` recovery ladder that `/execute`'s `done_blocked` prose (lines 758-761) does not.

### 4. Scripts inventory

`/work-on`:

| Script | Lines | What it does | Invoked from |
|---|---|---|---|
| `skills/work-on/references/scripts/extract-context.sh` | 414 | Fetches a GitHub issue (with auth/fetch failure handling) and writes `context.md`. This is the only production script `/work-on` owns. | `skills/work-on/references/phases/phase-0-context-injection.md:12`, which is read by state `context_injection` (`work-on.md:863`). |
| `skills/work-on/scripts/retry-clearing_test.sh` | 868 | A **test with no corresponding production script**. It extracts the retry-clearing shell blocks directly out of the shipped `verification` prose (`work-on.md`) and the phase files at run time, and asserts they clear the right context keys before a retry. `/work-on`'s "retry clearing" logic is inline prose/bash in the template (`work-on.md:1097-1120`), not a script. | Run by CI: `.github/workflows/check-work-on-scripts.yml:50`. |

`/work-on` ships **zero standalone production scripts under `scripts/`** — the one production script it has (`extract-context.sh`) lives under `references/scripts/`, and the only file under `scripts/` proper is a test harness with no script to test (it tests inline template prose instead).

`/execute`:

| Script | Lines | What it does | Invoked from |
|---|---|---|---|
| `skills/execute/scripts/record-settled-branch.sh` | 104 | Reads HEAD, refuses detached HEAD / disallowed name / default branch, writes `settled_branch` context key. | koto `default_action` on state `settled_branch_record` (`execute.md:127`); documented in `SKILL.md:232`, `SKILL.md:784`. |
| `skills/execute/scripts/settled-branch-record_test.sh` | 396 | Test harness for the above. | CI: `.github/workflows/check-execute-scripts.yml`. |
| `skills/execute/scripts/run-cascade.sh` | 1026 | Runs the pre-cascade lifecycle probe, the atomic finalization commit (PLAN deletion + BRIEF/PRD/DESIGN transitions + `handle_roadmap_deletion`), pushes, and the post-cascade verification. | State `plan_completion` (`execute.md:709`); documented `SKILL.md:257,573,786`. |
| `skills/execute/scripts/run-cascade_test.sh` | 2100 | Test harness for the cascade script — the single largest file in either skill's `scripts/`. | CI: `.github/workflows/check-execute-scripts.yml`. |
| `skills/execute/scripts/assert-child-template.sh` | 29 | Cross-skill guard: fails closed if `/work-on`'s child template drifted from what `/execute` expects. | `SKILL.md:167,328` (Step 1 of both Single-PR and Coordinated paths). |
| `skills/execute/scripts/assert-child-template_test.sh` | 81 | Test harness for the above. | CI: `.github/workflows/check-execute-scripts.yml`. |

`/execute` has 3 production scripts totaling 1,159 lines (plus 2,577 lines of tests for them). `/work-on` has 1 production script (414 lines) plus one orphaned-looking test (868 lines) that tests template prose, not a script. **All of the finishing-logic machinery — settled-branch recording, cascade/lifecycle transition, and the cross-skill template-drift guard — is `/execute`-only; `/work-on` has no equivalent scripts at all.**

### 5. References inventory

`/work-on/references/` — 16 files, 1,766 lines (excluding `extract-context.sh`, counted above as a script):

| File | Lines | Wired from |
|---|---|---|
| `phases/phase-0-context-injection.md` | 37 | `context_injection` (`work-on.md:863`) |
| `phases/phase-1-setup.md` | 73 | `setup_issue_backed`, `setup_free_form`, `setup_plan_backed` (`work-on.md:937,944,981`) |
| `phases/phase-2-introspection.md` | 24 | `introspection` (`work-on.md:1012`) |
| `phases/phase-2.5-worktree-discipline.md` | 100 | **Not referenced by any `/work-on` state.** Only consumer is `/execute`'s `worktree_discipline_check` (`execute.md:563`) — see Surprises. |
| `phases/phase-3-analysis.md` | 112 | `analysis` (`work-on.md:1019`); itself references `agent-instructions/phase-3-analysis.md` |
| `phases/phase-4-implementation.md` | 175 | `implementation` (`work-on.md:1041`) |
| `phases/phase-4a-scrutiny.md` | 79 | `scrutiny` (`work-on.md:1060`), and cited again from `verification` (line 1121) |
| `phases/phase-4b-review.md` | 73 | `review` (`work-on.md:1068`) |
| `phases/phase-4c-qa.md` | 72 | `qa_validation` (`work-on.md:1076`) |
| `phases/phase-5-finalization.md` | 111 | `finalization` (`work-on.md:1131`) |
| `phases/phase-6-pr.md` | 63 | `deferral_approval`, `pr_creation`, `ci_monitor` (`work-on.md:1156,1180,1194`) |
| `phases/phase-6-design-diagram-update.md` | 72 | Cited from `phase-6-pr.md` (transitively wired) |
| `agent-instructions/phase-3-analysis.md` | 219 | `phases/phase-3-analysis.md:23,35,38` |
| `koto-context-conventions.md` | 49 | `phases/phase-1-setup.md`, `phases/phase-5-finalization.md`, `agent-instructions/phase-3-analysis.md` |
| `review-panel-orchestration.md` | 37 | `SKILL.md:238` |
| `verification-map.md` | 56 | `SKILL.md:50,64` |

`/execute/references/` — **1 file, 15 lines**:

| File | Lines | Wired from |
|---|---|---|
| `cross-issue-context.md` | 15 | `spawn_and_await` prose (`execute.md`, "run the context assembly step in `references/cross-issue-context.md`") |

`/execute` also cites a large set of shared, plugin-root-level `references/` files it does **not** own (`parent-skill-state-schema.md`, `parent-skill-resume-ladder-template.md`, `parent-skill-pattern.md`, `parent-skill-security.md`, `parent-skill-child-inspection.md`, `coordination-strategy.md`, `default-action-conversion.md`), listed in `SKILL.md:773-789`. These aren't `skills/execute/references/*` files, so they're outside the "references/" count in the lead's literal sense, but they're the load-bearing documentation for everything `/execute` does that `/work-on` doesn't (state-file schema, resume ladder, exit paths, security contract). `/work-on`'s SKILL.md cites the pattern-level `references/decision-presentation.md`, `references/decision-protocol.md`, and `references/fixes/sub-agent-dispatch.md`, but none of the parent-skill-pattern files — `/work-on` is not a parent-skill-pattern implementer (it has no `wip/<skill>_<topic>_state.md`, no `exit:` field, no three-exit-path model).

### 6. Prose steps/phases in each `SKILL.md`

`/work-on/SKILL.md` — 298 lines. Section spine: Input Resolution (issue/milestone/`needs-triage`/blocking labels) → Definition of Done (verification-map gate) → Finalization and No Silent Deferral → Plan Input (Dispatcher: routes `single-pr`/`coordinated` to `/execute`, runs `multi-pr` itself) → Mode Detection → Plan-Backed Child Mode → Koto Orchestration (Initialize/Branch Setup/Execution Loop/Review Panel/Resume/Decision Capture) → Output → Begin. **Output is stated plainly at line 264: "A merged PR with passing CI, referenced back to the source issue."** There is no section in `/work-on/SKILL.md` for: exit-path taxonomy, a durable state file, `gh pr ready`, a document-lifecycle cascade, DIRTY-merge handling, or a "Security Considerations" section — none of those concepts appear anywhere in the file (confirmed by header grep and by the term-count check in section 7).

`/execute/SKILL.md` — 795 lines, roughly 2.7x `/work-on`'s. Section spine: Input Modes → Execution-Mode Flags (`--auto`/`--interactive`) → Topic-Slug Constraint → Workflow Phases (0 Setup/1 Drive/2 Finalize/3 Exit) → Phase Execution → Single-PR Execution Path (3 steps: assert child template, initialize orchestrator, drive the loop with mode-driven pause) → Coordinated Execution Path (3 steps + Abandonment) → **State** (durable `wip/execute_<topic>_state.md`, report-upstream convention) → **Resume** → **Exit Paths** (`full-run`/`abandonment-forced`/`re-evaluation`, plus the `paused_for_review` suspension that is explicitly *not* one of the three) → **Finalization-Not-Done Guard (R5)** → Autonomy → Child Inspection → Security Considerations → Team Shape → Reference Files. Every one of the bolded sections above (State, Resume as a formal ladder, Exit Paths, Finalization-Not-Done Guard, Security Considerations) has no counterpart section in `/work-on/SKILL.md` — `/work-on` has a much smaller "### Resume" subsection (3 bullet points, `SKILL.md:240-252`) that only covers koto-workflow lookup, not a durable state file or exit taxonomy.

### 7. Term-count verification (issue #361)

Ran directly against `skills/work-on/koto-templates/work-on.md` and `skills/execute/koto-templates/execute.md` on this checkout:

```
grep -c -- "gh pr ready" skills/work-on/koto-templates/work-on.md   -> 0
grep -c -- "gh pr ready" skills/execute/koto-templates/execute.md   -> 12
grep -c -- "Fixes #"     skills/work-on/koto-templates/work-on.md   -> 0
grep -c -- "Fixes #"     skills/execute/koto-templates/execute.md   -> 3
grep -c -- "--draft"     skills/work-on/koto-templates/work-on.md   -> 0
grep -c -- "--draft"     skills/execute/koto-templates/execute.md   -> 1
grep -c -- "cascade"     skills/work-on/koto-templates/work-on.md   -> 0
grep -c -- "cascade"     skills/execute/koto-templates/execute.md   -> 27
grep -c -- "lifecycle"   skills/work-on/koto-templates/work-on.md   -> 0
grep -c -- "lifecycle"   skills/execute/koto-templates/execute.md   -> 4
grep -c -- "run-cascade" skills/work-on/koto-templates/work-on.md   -> 0
grep -c -- "run-cascade" skills/execute/koto-templates/execute.md   -> 3
```

**All six of issue #361's claimed counts are exactly correct** (0/12, 0/3, 0/1, 0/27, 0/4, 0/3), when "count" means matching *lines* (`grep -c`), which is what these numbers are.

One nuance worth flagging: if you count raw *occurrences* instead of matching lines (`grep -o | wc -l`), two of the six numbers change because a line can contain a term twice: `Fixes #` occurs **4** times on 3 lines (line 654 has it twice: "Append `Fixes #<N>` lines ... omit `Fixes #N` entirely"), and `cascade` occurs **38** times on 27 lines (several sentences use the word more than once, e.g. the `plan_completion` state's design-rationale prose). `gh pr ready`, `--draft`, `lifecycle`, and `run-cascade` have the same occurrence and line counts (12, 1, 4, 3). This doesn't contradict #361 — the issue's numbers are correct for line-count grep — but a reader who re-runs `grep -o` instead of `grep -c` will see different totals for two of the six terms and should not read that as a discrepancy in the issue.

State counts: confirmed independently in sections 1-2 above — **28** for `/work-on`, **14** for `/execute`, both exactly matching #361.

### 8. Mermaid companion templates

Both skills ship a `*.mermaid.md` alongside the koto template (`work-on.mermaid.md`, `execute.mermaid.md`), and `scripts/validate-template-mermaid.sh` (cited in comments at `work-on.md:783` and `execute.md:401`) enforces that the `ci_passing` gate's shell expression stays byte-identical between the two templates ("check 4"). This is the one piece of machinery that explicitly keeps the two templates in sync at all — everything else about the two files evolves independently.

## Implications

The inventory shows the asymmetry the exploration is investigating is not evenly spread across "a few missing steps" — it's concentrated in exactly two `/execute`-only states (`pr_finalization`, `plan_completion`) plus one upgraded shared state (`ci_monitor`'s DIRTY handling). Everything that turns "PR exists, CI green" into "PR is a conventional-title/two-part-body, `Fixes #N`-linked, ready-for-review, document-chain-finalized, CI-green-on-ready PR" is produced by `run-cascade.sh` (1,026 lines) plus the `pr_finalization`/`plan_completion` prose — all currently reachable only through `/execute`, which in turn is only reachable for `single-pr` and `coordinated` PLANs, never for a bare issue or `multi-pr` PLAN run through `/work-on` directly. That matches the evidence in the exploration context (dispatched `/work-on` workers needing hand-supplied `Fixes #N`, `gh pr ready`, CI watching, and document-chain scoping) precisely at the mechanism level: those four gaps map 1:1 onto `pr_finalization` (title/body/`Fixes #N`), `plan_completion` (`gh pr ready` + cascade), and `ci_monitor`'s DIRTY handling.

Whichever direction (fold `/work-on` into `/execute`, or migrate the finishing logic down into `/work-on`/a shared component), the migration unit is clear from the code: `run-cascade.sh`, `record-settled-branch.sh` (or an equivalent single-issue-safe settling step), the `pr_finalization` prose (title/body authoring), and the `plan_completion` prose (cascade + `gh pr ready` + CI-on-ready). `settled_branch_record`, `worktree_sync`, and `worktree_discipline_check` are plan-level-only concepts (multi-child branch coordination, upstream-drift-across-children judgment) that don't obviously apply to a single `/work-on` issue run and would need separate design thought rather than a straight port.

## Surprises

1. **A `/work-on`-owned reference file is used exclusively by `/execute`.** `skills/work-on/references/phases/phase-2.5-worktree-discipline.md` is cited only from `execute.md:563` (state `worktree_discipline_check`); no state in `work-on.md` reads it. Worse, the file's own text is stale: it says "This phase runs inside the `worktree_discipline_check` koto state defined in `skills/work-on/koto-templates/work-on-plan.md`" (`phase-2.5-worktree-discipline.md:5-6`) — but `work-on-plan.md` doesn't exist in this checkout. `git log --all -- '**/work-on-plan.md'` shows it was renamed/split out by PR #199, "feat(execute): add implementation-altitude plan-execution skill and narrow /work-on" — the orchestrator moved from `work-on-plan.md` into `execute.md`, and this one reference file's cross-reference was never updated to match. This is direct, code-level evidence that the plan-orchestrator logic used to live inside `/work-on` and was extracted into `/execute`, leaving one orphaned pointer behind — relevant context for "fold back in vs. migrate further out," since it shows the boundary has moved before.

2. **`/work-on`'s `staleness_check` gate depends on a script this repo doesn't ship.** The gate command is `check-staleness.sh --issue {{ISSUE_NUMBER}} | jq -e '.introspection_recommended == false'` (`work-on.md:325`, prose at `work-on.md:993`), but there is no `check-staleness.sh` anywhere in this checkout (`find . -iname '*staleness*'` finds only PRD/BRIEF/DESIGN docs for a "prose-reference-staleness" issue, unrelated). `docs/plans/PLAN-work-on-friction-fixes.md:81` confirms this directly: "Decide how the `staleness_check` gate should work on a shirabe-only install, given `check-staleness.sh` currently ships only with the private tsukumogami plugin." This means `/work-on` run standalone in the public `shirabe` repo (as opposed to inside the tsukumogami workspace, which supplies the script via its own tooling) hits a gate whose command doesn't resolve — a second, separate kind of "`/work-on` standalone incompleteness" from the one this exploration was framed around, worth flagging to whoever scopes the fix so it isn't conflated with the PR-finishing-logic gap.

3. **`/work-on`'s only file under `scripts/` (as opposed to `references/scripts/`) is a test with no script under test.** `retry-clearing_test.sh` (868 lines) doesn't test a `retry-clearing.sh` — it extracts the retry-clearing bash blocks directly out of the shipped template/phase-file prose at run time and executes them (its own header comment explains this is deliberate, to catch a shipped-text edit that breaks the logic). `/work-on` therefore has, in a literal file-system sense, zero production scripts under `scripts/` — its retry-clearing logic is prose, not code, unlike every one of `/execute`'s three finishing-logic scripts.

4. **The reference-file asymmetry is far more lopsided than the state-count asymmetry.** `/work-on` has 16 reference files / 1,766 lines to `/execute`'s 1 file / 15 lines — a ~118x line-count gap, versus a 2x gap in state count (28 vs 14). This isn't itself surprising once you know `/execute` delegates almost all judgment-heavy work to `/work-on` children, but it's a sharper number than the state-count comparison alone would suggest, and worth keeping in mind when someone estimates the size of "porting the finishing logic" — the actual finishing logic (`run-cascade.sh` + `pr_finalization`/`plan_completion` prose) is compact; it's `/work-on`'s own reference tree that's large, and that tree is unaffected by either candidate direction.

## Open Questions

- Does `/work-on`'s `pr_creation` state ever produce a **draft** PR on any path? Grep confirms zero occurrences of `--draft` in `work-on.md`; `phase-6-pr.md` (63 lines) wasn't fully read line-by-line here and should be checked to confirm `/work-on` PRs are always created ready-for-review (not draft), which — if true — means the DRAFT-vs-READY discipline `/execute` implements (#117, referenced repeatedly in `execute.md`) may not even apply to a standalone `/work-on` PR the way it applies to `/execute`'s shared PR. Worth a follow-up lead.
- Is `check-staleness.sh`'s absence (Surprise 2) already a known/tracked gap, or is this exploration the first time it's been noticed as a standalone-completeness issue distinct from the PR-finishing gap in scope?
- The `phase-2.5-worktree-discipline.md` staleness (Surprise 1) suggests there may be other orphaned cross-references left over from the `work-on-plan.md` → `execute.md` split (PR #199) that a targeted `git log`/grep pass over both skills' reference trees would surface — not done exhaustively here since it's tangential to this lead's core ask.
- This lead didn't dig into `evals/` fixture-level detail beyond eval names/counts (`/work-on`: 29 evals; `/execute`: 35 evals, including several `e2e-execute-cascade-*` and `pr-finalization-*` evals with no `/work-on`-side counterpart, unsurprisingly, since `/work-on` has no cascade/pr-finalization behavior to eval). A dedicated lead on evals coverage could confirm whether any `/execute`-only eval is implicitly testing behavior a folded-in `/work-on` would need to inherit test coverage for.

## Summary
Issue #361's numbers all check out exactly against the code — 28 states in `/work-on`, 14 in `/execute`, and all six term counts (`gh pr ready` 0/12, `Fixes #` 0/3, `--draft` 0/1, `cascade` 0/27, `lifecycle` 0/4, `run-cascade` 0/3) — with the one caveat that raw occurrence counts (not line counts) differ for `Fixes #` (0/4) and `cascade` (0/38) because two lines each contain the term twice. The gap between the skills is concentrated, not diffuse: two `/execute`-only states (`pr_finalization`, `plan_completion`) plus a DIRTY-aware `ci_monitor` and three scripts (`run-cascade.sh`, `record-settled-branch.sh`, `assert-child-template.sh`, 1,159 production lines) carry all of the PR-title/body/`Fixes #N` authoring, the document-lifecycle cascade, `gh pr ready`, and DIRTY-merge detection that `/work-on` has none of. The biggest open question is how much of that concentrated logic — versus the plan-level-only states around it (`settled_branch_record`, `worktree_sync`, `worktree_discipline_check`, batch spawning) — actually needs to move for a standalone `/work-on` run to finish a PR unattended.
