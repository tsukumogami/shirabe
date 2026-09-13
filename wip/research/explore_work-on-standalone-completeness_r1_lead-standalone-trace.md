# Lead: What does a standalone `/work-on` run actually produce today, traced through its koto template from entry to every terminal state?

All line numbers below are against `skills/work-on/koto-templates/work-on.md` on `main` (9f84fa7) as checked out in this worktree, unless another file is named.

## Findings

### The full state graph

The template (`skills/work-on/koto-templates/work-on.md:43-839` for the YAML state machine, `:841-1227` for the per-state prose) declares 27 states: one entry, 18 mid-flow states, and 6 terminals (`done`, `done_already_complete`, `done_blocked`, `validation_exit`, `skipped_due_to_dep_failure` — 5 distinct terminal *kinds*, `done_blocked` reachable from 9 different origin states).

| State | Outcome (evidence field) | Next state | Cite |
|---|---|---|---|
| `entry` | `mode: issue_backed` | `context_injection` | :64-66 |
| `entry` | `mode: free_form` | `task_validation` | :67-69 |
| `entry` | `mode: plan_backed` | `plan_context_injection` | :70-72 |
| `entry` | `mode: skipped` | `skipped_due_to_dep_failure` (terminal) | :73-75 |
| `context_injection` | `status: completed/override` | `setup_issue_backed` | :91-97 |
| `context_injection` | `status: blocked` | `done_blocked` | :98-102 |
| `task_validation` | `verdict: proceed` | `research` | :114-117 |
| `task_validation` | `verdict: exit` | `validation_exit` (terminal) | :118-120 |
| `research` | (always) | `post_research_validation` | :133-134 |
| `post_research_validation` | `verdict: ready` | `setup_free_form` | :149-151 |
| `post_research_validation` | `verdict: needs_design` or `exit` | `validation_exit` (terminal) | :152-157 |
| `setup_issue_backed` | `status: completed/override` | `staleness_check` | :175-183 |
| `setup_issue_backed` | `status: blocked` | `done_blocked` | :184-188 |
| `setup_free_form` | `status: completed/override` | `analysis` | :207-215 |
| `setup_free_form` | `status: blocked` | `done_blocked` | :216-220 |
| `plan_context_injection` | `issue_source: github` | `setup_plan_backed` | :246-251 |
| `plan_context_injection` | `issue_source: plan_outline` | `plan_validation` | :252-257 |
| `plan_context_injection` | `status: blocked` | `done_blocked` | :261-265 |
| `plan_validation` | `verdict: proceed` | `setup_plan_backed` | :278-280 |
| `plan_validation` | `verdict: exit` | `validation_exit` (terminal) | :281-283 |
| `setup_plan_backed` | `status: completed/override` | `analysis` | :305-313 |
| `setup_plan_backed` | `status: blocked` | `done_blocked` | :314-318 |
| `staleness_check` | `fresh`/`override` | `analysis` | :341-347 |
| `staleness_check` | `stale_requires_introspection` | `introspection` | :338-340 |
| `staleness_check` | `blocked` | `done_blocked` | :348-352 |
| `introspection` | `issue_superseded` | `done_blocked` | :369-373 |
| `introspection` | `approach_unchanged`/`updated` | `analysis` | :374-382 |
| `analysis` | `plan_ready` | `implementation` | :410-413 |
| `analysis` | `already_complete` | `done_already_complete` (terminal) | :414-416 |
| `analysis` | `scope_changed_retry` | `analysis` (self-loop, capped) | :417-419 |
| `analysis` | `scope_changed_escalate` / `blocked_missing_context` | `done_blocked` | :420-429 |
| `implementation` | `complete` + `issue_type: code` | `scrutiny` | :464-470 |
| `implementation` | `complete` + `issue_type: docs\|task` | `verification` | :471-483 |
| `implementation` | `partial_tests_failing_retry` | `implementation` (self-loop) | :484-486 |
| `implementation` | `scope_expanded_retry` | `analysis` | :487-490 |
| `implementation` | `partial_tests_failing_escalate` / `blocked` | `done_blocked` | :491-500 |
| `scrutiny` | `passed` | `review` | :519-522 |
| `scrutiny` | `blocking_retry` | `implementation` | :523-525 |
| `scrutiny` | `blocking_escalate` | `done_blocked` | :526-530 |
| `review` | `passed` | `qa_validation` | :550-552 |
| `review` | `blocking_retry` | `implementation` | :553-555 |
| `review` | `blocking_escalate` | `done_blocked` | :556-560 |
| `qa_validation` | `passed` | `verification` | :580-582 |
| `qa_validation` | `blocking_retry` | `implementation` | :583-585 |
| `qa_validation` | `blocking_escalate` | `done_blocked` | :586-590 |
| `verification` | `passed` | `finalization` | :611-614 |
| `verification` | `failed` | `implementation` | :615-619 |
| `verification` | `cannot_verify` | `done_blocked` | :620-628 |
| `finalization` | `ready_for_pr` | `pr_precheck` | :654-657 |
| `finalization` | `deferral_requested` | `deferral_approval` | :658-661 |
| `finalization` | `issues_found` | `implementation` | :649-651 |
| `deferral_approval` | `approved` | `pr_precheck` | :685-688 |
| `deferral_approval` | `rejected` | `done_blocked` | :689-693 |
| `pr_precheck` | gate passes (auto) | `pr_creation` | :738-740 |
| `pr_precheck` | `precheck_status: override` | `pr_creation` | :741-744 |
| `pr_precheck` | `precheck_status: blocked` | `done_blocked` | :745-750 |
| `pr_creation` | `pr_status: created` | `ci_monitor` | :762-764 |
| `pr_creation` | `pr_status: shared` | `done` (terminal) | :765-767 |
| `pr_creation` | `creation_failed_retry` | `pr_creation` (self-loop) | :768-770 |
| `pr_creation` | `creation_failed_escalate` | `done_blocked` | :771-775 |
| `ci_monitor` | `passing`/`failing_fixed` | `done` (terminal) | :801-812 |
| `ci_monitor` | `failing_unresolvable` | `done_blocked` | :813-817 |

### Happy path narrative (issue-backed, code-typed)

`entry` (mode: issue_backed) → `context_injection` (write GitHub issue as `context.md`) → `setup_issue_backed` (create `feature/<N>-<desc>` branch, run baseline tests, write `baseline.md`) → `staleness_check` (confirm the issue is still current) → `analysis` (write `plan.md`, classify `issue_type`) → `implementation` (commit code, self-loop on failing tests up to 3x) → `scrutiny` → `review` → `qa_validation` (three sequential three-reviewer panels, each gated only on `context-exists` of a JSON file the agent itself writes) → `verification` (run the project's definition-of-done gate for real, per `SKILL.md:54-119`) → `finalization` (cleanup, write `summary.md`) → `pr_precheck` (confirm not on `main`, capture `BRANCH`) → `pr_creation` (push branch, `gh pr create`, evidence `pr_status: created` + `pr_url`) → `ci_monitor` (poll `gh pr checks`, fix and re-push on failure) → `done`.

For a `docs`- or `task`-typed issue, `implementation` routes straight to `verification`, skipping `scrutiny`/`review`/`qa_validation` entirely (:471-483).

### What every terminal state leaves behind

| Terminal | Branch exists? | Pushed? | PR open? | Draft or ready? | `Fixes #N` in body? | CI watched? | koto context survives? |
|---|---|---|---|---|---|---|---|
| `done` (via `ci_monitor`) | Yes | Yes | Yes | **Ready** (never draft — see below) | Only if the agent chose to write it in Part 2; nothing enforces it | Yes, to a passing bucket or an agent-fixed push | **No** — see below |
| `done` (via `pr_status: shared`) | Yes (`SHARED_BRANCH`) | orchestrator's job | orchestrator's PR, not this run's | n/a — child never touches it | n/a | No — `pr_creation:765-767` skips `ci_monitor` entirely on this path | No |
| `done_already_complete` | Yes (created in setup, if issue-backed/plan-backed) | No | No | n/a | n/a | No | No |
| `validation_exit` (free-form only) | **No** — reached only from `task_validation`/`post_research_validation`, both of which precede `setup_free_form` | No | No | n/a | n/a | No | No |
| `skipped_due_to_dep_failure` | No | No | No | n/a | n/a | No | No |
| `done_blocked` (9 possible origins: `context_injection`, `setup_issue_backed`, `setup_free_form`, `plan_context_injection`, `setup_plan_backed`, `staleness_check`, `introspection`, `analysis`, `implementation`, `scrutiny`, `review`, `qa_validation`, `verification`, `deferral_approval`, `pr_precheck`, `pr_creation`, `ci_monitor`) | Depends on origin — none if blocked before any `setup_*` state ran; yes (uncommitted or committed) if blocked after | Only if blocked at/after `pr_creation`'s failed-creation path (push happens inside `pr_creation`, before the evidence is submitted, per phase-6-pr.md:17-23) or `ci_monitor` | Only if blocked from `ci_monitor` (`failing_unresolvable`) — a real open PR sits behind it | If open, ready (never draft) | Only if the agent wrote it manually | Only if blocked from `ci_monitor`; every earlier blocking path never opened a PR | **No** |

**Every terminal loses the koto context record.** `/work-on` calls `koto next` at 16 call sites and passes `--no-cleanup` at none of them (`requires.tsv` confirms every `koto next` call site is bare); GitHub issue #360 documents that koto deletes a session's `ctx/` on reaching *any* terminal state, and measured a real `done_blocked` run that lost its running `plan.md` this way. This applies uniformly to `done`, `done_already_complete`, `done_blocked`, `validation_exit`, and `skipped_due_to_dep_failure` — none of the 6 terminal kinds is exempted. `--no-cleanup` is `/scope`'s own fix for the identical problem (issue #360, quoting `skills/scope/references/phases/phase-4-cleanup.md:119-124`); `/work-on` never adopted it.

**`/work-on` never marks a PR ready and never creates one as draft.** `pr_creation`'s prose (`:1174-1191`) and `references/phases/phase-6-pr.md` both describe `gh pr create` with no `--draft` flag anywhere in the skill (grep confirms zero `--draft` hits in `skills/work-on/`, vs. one hit in `skills/execute/koto-templates/execute.md:506`: `gh pr create --draft --title "impl: {{PLAN_SLUG}}" ...`). `gh pr create` with no flag opens a normal, ready-for-review PR — so a standalone `/work-on` run's PR is mergeable-shaped from the moment it opens, not stuck in draft. There is also no `gh pr ready` anywhere in `work-on.md` (0 occurrences vs. 12 in `execute.md`, per issue #361's own count, which I re-verified: `grep -c "gh pr ready" skills/work-on/koto-templates/work-on.md` = 0, `skills/execute/koto-templates/execute.md` = re-verified present at :339,341,343,351,430,432,436,702,715,718,721,750).

### `pr_creation`: quoted, and what `created` vs. `shared` route to

`pr_creation`'s evidence schema accepts only `pr_status` (`created`, `shared`, `creation_failed_retry`, `creation_failed_escalate`) and `pr_url` (:753-760). The prose (:1174-1191):

> "If `SHARED_BRANCH` is set, this child is running on the orchestrator's shared branch and the orchestrator owns the PR. Submit `pr_status: shared` — no PR creation step is needed here."
> "Otherwise, read `references/phases/phase-6-pr.md` for PR format, pre-PR verification, and push instructions."
> "Check if a PR already exists: `gh pr list --head {{BRANCH}}`"
> "Push with `git push -u origin {{BRANCH}}`."
> "`gh pr create` stays with you, permanently: its successful exit is the externally visible event ... and closing the pull request afterwards undoes its state and not the notifications."

`pr_status: created` routes to `ci_monitor` (:762-764) — CI gets watched. `pr_status: shared` routes directly to `done` (:765-767), bypassing `ci_monitor` entirely; the CI that eventually runs is the orchestrator's shared-branch PR, watched (if at all) by `/execute`, not by this child. `phase-6-pr.md:52-55` states this explicitly: "Using `created` instead would enter `ci_monitor` and monitor the orchestrator's PR, not this child's work."

`Fixes #<N>` is mentioned exactly once in the entire `/work-on` skill tree: `phase-6-pr.md:35` — "Include `Fixes #<N>` in Part 2." This is prose inside a reference file the agent is told to *read*; there is no evidence field for it anywhere in the template, no gate checks for it, and `references/pr-body-conformance.md` (the CI-enforced, mechanical PR-body rule cited by both `/work-on` and `/execute`) explicitly keeps it advisory: "Whether Part 1 mentions an issue in prose ... stays advisory ... A legitimate docs-only PR with a one-line Part 1 and a Part 2 that is only `Fixes #N` passes" — but nothing requires that line to be present at all. `shirabe validate --pr-body` (PB1–PB4) checks title format, one separator, no AI-attribution footer, and no ATX heading in Part 1 — never presence of a closing keyword.

### `finalization`: what it actually finalizes, and whether the name is misleading

`finalization`'s evidence schema and prose (:630-662, :1129-1146) and `references/phases/phase-5-finalization.md` describe exactly three things: code cleanup (remove debug statements, dead code, unused imports), a final full test/build/lint run, and writing `summary.md` (a requirements-mapping document) before committing it (`docs: add implementation summary`). It also runs the no-silent-deferral gate (routes to the human-approval `deferral_approval` state on an unmet acceptance criterion). It does **not** touch the PR (that's `pr_creation`/`ci_monitor`, two states later) and it does **not** touch the document chain — no PLAN deletion, no DESIGN/PRD/BRIEF status transition, no ROADMAP update.

The tracking issue's name for the equivalent concept in `/execute` is a different state entirely: `plan_completion`, which runs `run-cascade.sh` — PLAN deletion, DESIGN→Current, PRD/BRIEF→Done, ROADMAP entry update, then `gh pr ready`. `/execute` also has its own, separately named `pr_finalization` state (PR title/body assembly only, explicitly *not* marking the PR ready). So the ecosystem already uses "finalization" for two different things in `/execute` (`pr_finalization` = PR body only; `plan_completion` = the chain cascade + ready-flip), and `/work-on`'s single `finalization` state is neither of those — it is closer to `/execute`'s `pr_finalization` in scope (assemble a summary artifact) but happens two states *before* the PR exists at all, and never touches the chain. Given `grep -c "cascade" skills/work-on/` = 0 and `grep -c "lifecycle"` = 0 (confirmed via issue #361's table, itself re-derivable from the same grep), `/work-on`'s `finalization` finalizes the *implementation* (tests, cleanup, an acceptance-criteria summary) — not the PR and not the document chain. The name is not wrong on its own terms, but it invites the same misreading the tracking issue's audit surfaced: someone hearing "finalization" from `/execute`'s vocabulary would expect the chain cascade, and `/work-on`'s state of the same name does something narrower and earlier in the pipeline. Confirmed by a still-open, related defect: issue #87 ("work-on: finalization phase missing PLAN doc deletion and design status transition") was filed specifically because a plan-backed `/work-on` run's `finalization` phase does not delete the PLAN doc or transition the DESIGN doc, leaving that "to be done manually after the PR is committed" — i.e., a human previously ran into exactly this gap and filed it four months before issue #361 generalized it.

### SKILL.md prose that the template does not enforce

- **`Fixes #<N>`** (`phase-6-pr.md:35`) — prose only, no evidence field, no gate (above).
- **Design-doc diagram update** (`phase-6-pr.md:11-15`, delegating to `phase-6-design-diagram-update.md`) — "If the issue body contains `Design: \`<path>\`` ... Skip if no `Design:` reference." This is the *only* place `/work-on` touches a DESIGN doc at all, and it is narrow: flip one Mermaid node from `:::ready`/`:::blocked` to `:::done` in a dependency graph. It is not gated — nothing in the koto template checks whether this ran, and its own error-handling section (`phase-6-design-diagram-update.md:69-72`) says to "log warning, skip update" and "continue PR without it" on any failure. A run can silently skip it.
- **Rebase/conflict resolution and `git diff main...HEAD` review** (`phase-6-pr.md:5-9`) — advisory pre-PR hygiene, no gate.
- **CI-failure iteration cap ("If stuck after 2-3 iterations, ask the user")** (`phase-6-pr.md:45-47`) — the template's actual cap on `ci_monitor` is none: the state has no self-loop and no retry counter; the agent evidence enum is `passing | failing_fixed | failing_unresolvable`, and going in a fix/push/re-check loop before submitting is entirely agent discretion, not a koto-tracked cycle count the way `analysis`'s `scope_changed_retry` (capped at 3, :1035-1036) or the panel retries (capped at 2, `review-panel-orchestration.md:14`) are.
- **`SKILL.md`'s "Handling `needs-triage` Issues" and "Handling Blocking Labels"** (`SKILL.md:36-48`) — these run entirely before `koto init`/`entry`; the koto state machine has no state for them at all, so a skipped label check leaves no trace in the workflow's evidence history.
- **`SKILL.md`'s repo-visibility / content-governance load** (`SKILL.md:279-283`) and **extension-file language/PR skill invocation** (`SKILL.md:285-286`) — same: pre-`entry` prose, no koto state, no gate.
- **Panel composition itself.** `review-panel-orchestration.md:1-11` describes each of `scrutiny`/`review`/`qa_validation` as *three parallel reviewers* with named rubrics. But each panel's koto gate (`scrutiny_results.json`, `review_results.json`, `qa_results.json`, all `type: context-exists` with `override_default: {exists: true}`, :503-509, :533-539, :563-569) only checks that a JSON file exists at that key — written by the same agent driving the workflow. Nothing checks reviewer count, identity, or that parallel spawns happened at all. This is independently confirmed as a live, filed defect: issue #352 ("Review panels and juries are unenforceable: a run can skip them and pass every gate") states plainly, with a fresh audit, that "no gate anywhere in the system can tell a jury that ran from one that didn't," and specifically that `scrutiny_results.json`/`review_results.json`/`qa_results.json`'s gates are "`context-exists` over a key the agent writes itself ... A run that spawned zero reviewers and wrote `{"passed": true}` clears every gate in the system." So the SKILL/reference-file description of a three-reviewer panel is exactly the kind of prose-as-advice the lead is asking about — koto enforces only artifact presence, never panel composition.

### Document-chain / artifact-lifecycle acknowledgment

`/work-on`'s only textual touches to BRIEF/PRD/DESIGN/PLAN/ROADMAP vocabulary in the whole skill tree are incidental: `koto-templates/work-on.md:665` references "PRD R4/R5" as a citation to the requirements document that justified the `deferral_approval` gate's design (not an in-workflow read of an actual PRD file), and `SKILL.md:141` references "the DESIGN's ephemeral-home model" as a citation, again not a runtime read. Neither is the workflow acting on a document-chain artifact. The one concrete, project-file-touching action is the diagram-node flip in `phase-6-design-diagram-update.md` described above — and even that only fires when the issue body happens to carry a `Design: \`<path>\`` line, and never transitions the DESIGN's own `status:` field or moves it between directories. `/work-on` has zero mentions of `cascade` or `lifecycle` (confirmed by grep and independently asserted, with the same zero-count, in issue #361's evidence table). PLAN deletion and DESIGN/PRD/BRIEF status transition exist only in `/execute`'s `plan_completion` (`run-cascade.sh`). This gap is specifically the subject of a second, older, still-open issue (#87), filed well before #361 generalized the finding to the whole standalone workflow.

### Evals: what they assert (and don't)

`skills/work-on/evals/evals.json` holds 29 scenarios. None assert anything about the terminal-state deliverable beyond the immediate koto transition: `pr-shared-skips-ci-monitor` (id 32) checks only that `pr_status: shared` skips `gh pr create` and routes to `done`; `already-complete-terminal` (id 29) checks only the `analysis`→`done_already_complete` transition and that the agent reports to the user. `dod-no-silent-deferral` (id 37) and `dod-fail-closed-cannot-verify` (id 36) assert the no-silent-pass behavior at `verification`/`finalization` but stop at "reports blocked," not at what a human is then supposed to do to unblock it. No eval asserts: a PR is marked ready, `Fixes #N` appears in the body, a document chain gets scoped or transitioned, or the koto context record survives a terminal. The eval fixtures directory does carry PLAN/PRD/DESIGN/ROADMAP fixtures (`evals/fixtures/{plans,prds,designs,roadmaps}/`), but these are for testing plan-*routing* (dispatcher mode-detection, multi-pr issue selection), not for asserting that `/work-on` finalizes those documents' lifecycle status.

## Implications

The template's design is internally consistent and its gates (`context-exists`, command gates for branch/tests/CI) do what they claim — the incompleteness is not a bug in what's gated, it's that several things a "finished, mergeable PR" needs are simply outside the state machine's scope by construction: PR readiness (draft/ready), closing keywords, and document-chain lifecycle are `/execute`-only concepts today, and `/work-on`'s own evidence schema has no field to carry them even if an agent wanted to submit one. The standalone stop-short point is precise: a `/work-on` run that reaches `done` has a real, open, non-draft PR with CI green — genuinely close to mergeable — but with no guarantee of a closing keyword and, if the work descended from a DESIGN/PRD/PLAN chain, that chain is left exactly where it was before the run started. The very next thing a human (or supervising session) has to say out loud, per the anecdote in the tracking issue, is some combination of: "does the PR body close the issue," "has the document chain been scoped/transitioned," and (separately, per issue #360) "the context record won't survive — capture what you need before this terminates."

## Surprises

- The PR `/work-on` opens is **not** draft — it's immediately in ready shape (mergeable barring review/CI), which cuts against a plausible-sounding but wrong assumption that a standalone run leaves a draft PR needing a manual "ready" flip. The actual gap is narrower: closing keywords and the document chain, not draft status.
- **Every** terminal state, not just `done_blocked`, loses its koto context record — including the two "successful" terminals (`done`, `done_already_complete`). A supervising session that wants to inspect what `/work-on` decided, after the fact, has nothing to read once the run terminates, regardless of outcome.
- `finalization` — the state whose name is most likely to be confused with "the run is finished" — runs two states before the PR exists and never touches the PR or the document chain at all. `/execute`'s chain-cascade equivalent is named `plan_completion`, not "finalization"; `/execute` even has its own `pr_finalization` state that is scoped narrower than what its name might suggest (title/body only, explicitly not marking ready). The word "finalization" is overloaded three different ways across the two skills.
- Issue #87, filed 2026-04-28 (months before #361, 2026-09-13), had already identified the PLAN-deletion / DESIGN-transition gap for plan-backed `/work-on` runs specifically — this is not a new observation, it's a recurrence of a previously-filed, still-open defect.
- Issue #352 independently establishes that even the parts of `/work-on` that look most rigorous — the three sequential three-reviewer panels — are gated only on artifact existence, not on the panel actually having run at the specified width. This means "was reviewed" is exactly as unenforced as "was finalized."

## Open Questions

- Whether the intended fix (per #361's two candidate directions) would keep `/work-on`'s `finalization` state as-is (implementation-summary scope) or expand its evidence schema/transitions to also carry ready-flip and cascade responsibility — the tracking issue explicitly declines to choose and flags the per-issue-vs-per-plan cascade cadence as the open structural question.
- Whether `Fixes #N` should become a gated, mechanical PR-body check (like PB1-PB4) or stay advisory-by-design (per `pr-body-conformance.md`'s stated position that issue-reference presence is deliberately not gated to avoid false-positiving legitimate PRs that reference the issue only in prose).
- Whether the koto context-survival fix (#360, `--no-cleanup`) lands before or independently of whatever #361 changes — the two are explicitly flagged as needing to be "checked against the new boundary rather than inherited by it."

## Summary
A standalone `/work-on` run that reaches `done` leaves a real, pushed, non-draft, CI-green PR behind — genuinely close to mergeable — but the template has no field, gate, or state for closing keywords, PR-ready status (it's already ready, never draft), or document-chain lifecycle, and every terminal state (including the two success terminals) discards the koto context record because `/work-on` never passes `--no-cleanup`. The `finalization` state's name is misleading in exactly the way a reader familiar with `/execute`'s vocabulary would expect: it finalizes the implementation (cleanup, tests, a summary artifact) two states before the PR exists, never the PR and never the BRIEF/PRD/DESIGN/PLAN/ROADMAP chain, which lives solely in `/execute`'s differently-named `plan_completion` cascade — a gap issue #87 flagged for the plan-backed case four months before the tracking issue (#361) generalized it, and reinforced by #352's independent finding that even the review panels inside `/work-on` are gated on self-reported artifact existence rather than verified reviewer participation. The biggest open question is which of #361's two candidate directions (fold into `/execute`, or migrate finishing logic into `/work-on`) the project takes, since that determines whether the per-plan cascade cadence changes and whether `finalization` keeps its current, narrower meaning.
