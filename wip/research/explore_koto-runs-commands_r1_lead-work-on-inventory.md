# Lead: Where exactly does the `/work-on` koto template and skill surface tell the agent to run a shell command, and what is each command for?

## Scope covered

- `skills/work-on/koto-templates/work-on.md` (1156 lines, read in full)
- `skills/work-on/koto-templates/work-on.mermaid.md` (149 lines, read in full)
- `skills/work-on/SKILL.md` (288 lines, read in full)
- `skills/work-on/references/**` — every file: `koto-context-conventions.md`,
  `phases/phase-{0,1,2,2.5,2-introspection,3,4,4a,4b,4c,5,6-design-diagram-update,6-pr}.md`,
  `agent-instructions/phase-3-analysis.md`, `review-panel-orchestration.md`,
  `verification-map.md`, `scripts/extract-context.sh`
- `scripts/lib/koto-gates.sh`
- `skills/work-on/requires.tsv` (declarative tool-dependency manifest, read for corroboration, not an instruction site)

Two categories exist that are **not** "agent runs a shell command from prose" and are inventoried separately at the end: (1) koto template **gates** (`type: command`), which koto's engine executes automatically on `koto next` — already-automated, not agent-issued; (2) `scripts/lib/koto-gates.sh`, which is CI drift-check tooling, never invoked during a workflow run.

## Findings — Part A: Agent-instructed commands (prose sites)

| file:line | command | state / section | purpose | classification | output consumed? |
|---|---|---|---|---|---|
| work-on.md:896 | `gh issue view $ISSUE_NUMBER` | `plan_context_injection` (ISSUE_SOURCE=github path) | Fetch issue title/body/labels for a plan-backed child | MECHANICAL | Yes — agent writes result to koto `context.md`; gates `context_artifact` (context-exists) on the next state |
| work-on.md:1046-1060 | retry block: `koto context remove <WF> "$KEY"` ×4 keys, `koto context exists <WF> "$KEY"`, `koto next <WF> --with-data '{"verification_outcome":"failed",...}'` | `verification` (on `failed`) | Clear stale panel/summary artifacts (`scrutiny_results.json`, `review_results.json`, `qa_results.json`, `summary.md`) before looping back so downstream `context-exists` gates can't pass on stale verdicts | MECHANICAL (fully deterministic loop, hard exit-1 on ambiguous signal) — KOTO-PROTOCOL | Yes — clears gates for `scrutiny`, `review`, `qa_validation`, `finalization` |
| work-on.md:1097-1098 | `koto decisions record <WF> --with-data '{"choice":...,"rationale":...,"alternatives_considered":[...]}'` | `deferral_approval` (approved path) | Record human's deferral approval as the audit-trail decision | KOTO-PROTOCOL / MIXED (content is judgment; invocation mechanical) | Yes — surfaced in PR body per phase-6-pr.md |
| work-on.md:1116 | `gh pr list --head $(git rev-parse --abbrev-ref HEAD)` | `pr_creation` | Check whether a PR already exists before creating one | MIXED (mechanical query, agent branches create-vs-reuse on result) | Yes — determines whether "Create PR" step runs |
| SKILL.md:8 | `!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh work-on 2>&1 \|\| true`` | frontmatter directive (not a state) | Harness-executed preflight check when the skill loads | MECHANICAL — but note: this is **not** an agent prose instruction, it's a `!`-prefixed directive the Claude Code harness itself executes at skill-load time | N/A (preflight output, not koto evidence) |
| SKILL.md:31 | `gh issue view` (mentioned) | Handling Blocking Labels | Restates that the issue was already read; check for blocking labels | MECHANICAL (duplicate reference to the Begin-section read at :264) | Yes — feeds blocking-label check (JUDGMENT) |
| SKILL.md:154 | `gh issue view <ISSUE_NUMBER>` | Plan-Backed Child Mode, ISSUE_SOURCE=github | Fetch issue for `plan_context_injection` | MECHANICAL (duplicate of work-on.md:896 — same fetch, described twice) | Yes — becomes `context.md` |
| SKILL.md:184-187 | `koto init <WF> --template ... --var ISSUE_NUMBER=<N> --var ARTIFACT_PREFIX=issue_<N>` | Koto Orchestration → Initialize (issue-backed) | Start the koto session | KOTO-PROTOCOL | Yes — creates the workflow the whole run operates on |
| SKILL.md:191-193 | `koto init <WF> --template ... --var ARTIFACT_PREFIX=task_<slug>` | Initialize (free-form) | Start the koto session | KOTO-PROTOCOL | Yes |
| SKILL.md:212 | `koto next <WF>` | Execution Loop step 1 | Advance/query the state machine | KOTO-PROTOCOL | Yes — drives the whole loop |
| SKILL.md:213 | `koto next <WF>` (repeat) | Execution Loop step 2, when `action:"execute", advanced:true` | Re-poll after an auto-advanced (gate-passed) transition | KOTO-PROTOCOL | Yes |
| SKILL.md:216-218 | `koto next <WF> --with-data '{"field_name":"value",...}'` | Execution Loop step 3 | Submit phase evidence | KOTO-PROTOCOL | Yes — this is the evidence-submission mechanism itself |
| SKILL.md:223 | `koto rewind <WF>` | Execution Loop, Errors note | Step back a state after a failed gate or (per `done_blocked` section, work-on.md:1146-1150) after an externally-resolved blocker | KOTO-PROTOCOL | Yes |
| SKILL.md:231 | `koto workflows` | Resume step 1 | Find the active workflow name | KOTO-PROTOCOL | Yes — determines resume-vs-init branch |
| SKILL.md:232 | `koto next <WF>` | Resume step 2 | Resume an existing run | KOTO-PROTOCOL | Yes |
| SKILL.md:247-249 | `koto decisions record <WF> --with-data '{"choice":...,"rationale":...,"alternatives_considered":[...]}'` | Decision Capture (analysis/implementation) | Record non-obvious judgment calls | KOTO-PROTOCOL / JUDGMENT (content) | Yes — audit trail |
| SKILL.md:264 | `gh issue view <issue-number>` | Begin | First issue read; feeds blocking-label routing | MECHANICAL | Yes — feeds JUDGMENT (blocking-label check) |
| SKILL.md:278 | `koto workflows` | Begin step 1 | Check for an active matching workflow | KOTO-PROTOCOL | Yes |
| SKILL.md:279 | `koto init` | Begin step 2 | Start fresh if none found | KOTO-PROTOCOL | Yes |
| SKILL.md:281-282 | `koto next <WF> --with-data '{"mode":"issue_backed","issue_number":"<N>"}'` (or free-form variant) | Begin step 3 | Submit entry evidence | KOTO-PROTOCOL | Yes |
| phase-0-context-injection.md:12 | `${CLAUDE_PLUGIN_ROOT}/skills/work-on/references/scripts/extract-context.sh <N> --session <WF>` | `context_injection` → Extract Context | Run the full context-extraction pipeline (finds design doc, parses Implementation Issues table, extracts section, stores to koto `context.md`, prints JSON) | MECHANICAL — single deterministic script call; strong `default_action` candidate | Yes — script itself calls `koto context add` internally; gates `context_artifact` |
| phase-0-context-injection.md:30 | `koto context add <WF> context.md --from-file <updated-file>` | Read and Summarize (conditional — only if agent revised the script's output) | Overwrite `context.md` with agent-refined content | KOTO-PROTOCOL, conditional | Yes |
| phase-1-setup.md:9 | `gh issue view <issue-number>` | Review Issue | Re-read requirements/AC/dependencies before branching | MECHANICAL — third occurrence of the same fetch (after SKILL.md:264 and, in plan-backed mode, work-on.md:896/SKILL.md:154) | Yes — informs branch-prefix choice (JUDGMENT) |
| phase-2-introspection.md:17 | `koto context add <WF> introspection.md --from-file <introspection-file>` | Introspection → Steps | Store staleness re-check findings | KOTO-PROTOCOL | Yes — gates `introspection_artifact` |
| phase-2.5-worktree-discipline.md:27 | `git fetch origin` | 2.5.1 Fetch Origin and Rebase | Pull latest main before classifying upstream drift | MECHANICAL | Yes — feeds rebase |
| phase-2.5-worktree-discipline.md:28 | `git rebase origin/main` | 2.5.1 | Rebase the shared branch onto latest main | MECHANICAL, conflict resolution on failure is JUDGMENT | Yes — feeds impact classification (JUDGMENT) |
| phase-2.5-worktree-discipline.md:75,77,79 | `koto next {{SESSION_NAME}} --with-data '{"impact":"none"\|"informational"\|"intent-changing", ...}'` | 2.5.4 Submit Evidence | Submit the drift classification | KOTO-PROTOCOL / JUDGMENT (the impact value is a judgment call) | Yes |
| references/phases/phase-3-analysis.md:80-93 | retry block (`koto context remove`/`exists` ×4 keys + `koto next --with-data '{"plan_outcome":"scope_changed_retry"}'`) | `analysis`, Retry Loop | Clear `plan.md` + downstream panel keys before re-writing a replacement plan | MECHANICAL — KOTO-PROTOCOL | Yes |
| phase-4-implementation.md:6 | `koto context get <WF> plan.md` | Implementation intro | Retrieve the plan the analysis (sub)agent wrote | KOTO-PROTOCOL | Yes — drives the whole implementation cycle |
| phase-4-implementation.md:17 | `koto context get <WF> context.md` | Design Context (conditional, "if you need to revisit") | Re-fetch design rationale mid-implementation | KOTO-PROTOCOL, conditional | Yes |
| phase-4-implementation.md:93 | `gh issue view <N>` (or re-read plan outline) | Re-confirm Acceptance Criteria Mid-Implementation, step 1 | Re-check AC wording against what actually shipped, deliberately not relying on conversation memory | MECHANICAL — fourth occurrence of the same fetch in the workflow, deliberately not cached | Yes — feeds JUDGMENT (AC-drift check) |
| phase-4-implementation.md:124 | `git diff main...HEAD` | Implementation Review, Self-review (always) | Review the full diff before self-assessing AC | MECHANICAL | Yes — feeds JUDGMENT |
| phase-4-implementation.md:150-162 | retry block (`scope_expanded_retry` variant, same 4 keys) | Retry Loop | Clear plan+panel keys before rewinding to `analysis` mid-implementation | MECHANICAL — KOTO-PROTOCOL | Yes |
| phase-4a-scrutiny.md:35-38 | `koto context add <WF> scrutiny_results.json <<EOF ... EOF` then `koto next <WF> --with-data '{"scrutiny_outcome":"passed"}'` | Aggregation (all `blocking_count:0`) | Record panel pass verdict | KOTO-PROTOCOL, content is MIXED (aggregated from 3 parallel reviewer JSONs, a judgment step) | Yes — gates `scrutiny_results` |
| phase-4a-scrutiny.md:48-60 | retry block (same 4-key pattern) | Retry Loop | Clear stale verdicts on `blocking_retry` | MECHANICAL — KOTO-PROTOCOL | Yes |
| phase-4b-review.md:35-38 | `koto context add <WF> review_results.json < /dev/stdin <<EOF ... EOF` then `koto next --with-data '{"review_outcome":"passed"}'` | Aggregation | Record review-panel pass verdict | KOTO-PROTOCOL / MIXED | Yes |
| phase-4b-review.md:46-58 | retry block | Retry Loop | Same 4-key clearing pattern | MECHANICAL — KOTO-PROTOCOL | Yes |
| phase-4c-qa.md:34-37 | `koto context add <WF> qa_results.json < /dev/stdin <<EOF ... EOF` then `koto next --with-data '{"qa_outcome":"passed"}'` | Aggregation | Record QA pass verdict | KOTO-PROTOCOL / MIXED | Yes |
| phase-4c-qa.md:44-57 | retry block | Retry Loop | Same 4-key clearing pattern | MECHANICAL — KOTO-PROTOCOL | Yes |
| phase-5-finalization.md:82-94 | retry block (`finalization_status:"issues_found"` variant) | Retry Loop: issues_found | Clear panel keys + `summary.md` before returning to implementation | MECHANICAL — KOTO-PROTOCOL | Yes |
| phase-6-pr.md:9 | `git diff main...HEAD` | Pre-PR Verification | Confirm no unintended changes before PR | MECHANICAL — second occurrence of the same diff command (after phase-4-implementation.md:124) | Yes — feeds JUDGMENT |
| phase-6-pr.md:20 | `git push -u origin <branch>` | Push Branch | Push the feature branch upstream | MECHANICAL | No direct koto consumption (mechanical prerequisite for `gh pr create`, itself not spelled out literally — JUDGMENT for exact invocation) |
| phase-6-pr.md:23 | `git push --force-with-lease` | Push Branch, conditional ("After rebase") | Re-push after a pre-PR rebase | MECHANICAL, conditional | No |
| references/agent-instructions/phase-3-analysis.md:19 | `gh issue view <N>` (parenthetical reference) | Inputs Needed | Names where issue detail comes from for the dispatched analysis sub-agent | MECHANICAL (reference, not a new fetch — reuses what the main agent already has) | Yes, indirectly |
| references/agent-instructions/phase-3-analysis.md:20 | `koto context get <WF> baseline.md` | Inputs Needed | Fetch baseline for the analysis (sub)agent | KOTO-PROTOCOL | Yes |
| references/agent-instructions/phase-3-analysis.md:22-23 | `koto context get <WF> context.md` (if exists) | Inputs Needed, conditional | Fetch design context for the analysis (sub)agent | KOTO-PROTOCOL, conditional | Yes |
| references/agent-instructions/phase-3-analysis.md:140-141 | `koto context exists <WF> context.md` then `koto context get <WF> context.md` | Step 3: Read Design Context | Same fetch, restated inside the numbered task list | KOTO-PROTOCOL — duplicate of the "Inputs Needed" mention above within the same file | Yes |

**37 distinct prose instruction sites** (some spanning multi-line blocks counted once). Breakdown:
- **KOTO-PROTOCOL** (koto subcommand itself — `koto init/next/workflows/rewind/context add/context get/context exists/context remove/decisions record`): **26 sites** — SKILL.md:184-187, 191-193, 212, 213, 216-218, 223, 231, 232, 247-249, 278, 279, 281-282; phase-0:30; phase-2:17; phase-2.5:75-79; phase-3(main):80-93; phase-4:6, 17, 150-162; phase-4a:35-38, 48-60; phase-4b:35-38, 46-58; phase-4c:34-37, 44-57; phase-5:82-94; agent-instructions/phase-3:20, 22-23, 140-141; work-on.md:1046-1060, 1097-1098. (Several of these are also tagged MECHANICAL/MIXED below since a koto call can itself be a deterministic clearing loop or carry judgment-authored content.)
- **MECHANICAL** (deterministic, no interpretation needed to construct or run the command): **~14 sites** — `gh issue view` (5 occurrences: work-on.md:896, SKILL.md:31/154/264, phase-1-setup.md:9, phase-4-implementation.md:93 — 6 total counting all), `git diff main...HEAD` (×2), `git fetch origin`, `git rebase origin/main`, `git push -u origin`, `git push --force-with-lease`, `gh pr list --head ...`, extract-context.sh invocation, all 8 retry-loop clearing blocks (also KOTO-PROTOCOL).
- **JUDGMENT** (no literal command given; agent must author/decide): branch naming and `git checkout -b` (phase-1-setup.md, prose only — "create a new branch: feature/<N>-<desc>..."), baseline test-suite command ("use project-specific commands"), commit invocations throughout (message format prescribed, `git commit` itself never spelled out), `gh pr create` invocation (phase-6-pr.md — content rules delegated to `pr-body-conformance.md`, no literal command), impact-classification content, plan/summary/decision content.
- **MIXED**: `gh pr list --head ...` (mechanical query, judgment on result), `koto decisions record` (mechanical call, judgment content), the three panel Aggregation calls (mechanical `koto context add`+`koto next`, but the JSON content depends on 3 parallel reviewer verdicts — a judgment aggregation step).

### Duplicate `gh issue view <N>` calls (worth flagging on its own)

The same issue is fetched **up to four times** across one issue-backed run with no reuse/caching instructed:
1. SKILL.md:264 (Begin, before blocking-label check)
2. SKILL.md:154 / work-on.md:896 (plan-backed only — `plan_context_injection`)
3. phase-1-setup.md:9 (`setup_issue_backed` → Review Issue)
4. phase-4-implementation.md:93 (mid-implementation AC re-confirmation — explicitly justified: "don't rely on what's still in your conversation context; issues and outlines change")

Only the 4th is deliberately justified as a fresh re-read (staleness protection). The 1st–3rd look like unintentional repetition rather than a designed re-check.

## Findings — Part B: koto template **gates** (`type: command`) — auto-executed by koto, not agent-instructed

These already ARE automation koto runs itself on `koto next`, distinct from `default_action` (they gate a transition rather than execute a whole state's mechanical work) but proving the pattern is already in use in this template:

| file:line | gate name | state | command |
|---|---|---|---|
| work-on.md:161-163 | `on_feature_branch` | `setup_issue_backed` | `test "$(git rev-parse --abbrev-ref HEAD)" != "main"` |
| work-on.md:192-195 | `on_feature_branch` | `setup_free_form` | same |
| work-on.md:290-293 | `on_feature_branch` | `setup_plan_backed` | same |
| work-on.md:322-325 | `staleness_fresh` | `staleness_check` | `check-staleness.sh --issue {{ISSUE_NUMBER}} \| jq -e '.introspection_recommended == false'` |
| work-on.md:433-435 | `on_feature_branch_impl` | `implementation` | same branch-check |
| work-on.md:436-438 | `has_commits` | `implementation` | `test "$(git log --oneline main..HEAD \| wc -l)" -gt 0` |
| work-on.md:439-441 | `tests_passing` | `implementation` | `[ ! -f go.mod ] \|\| go test ./...` |
| work-on.md:733-735 | `ci_passing` | `ci_monitor` | `gh pr checks $(gh pr list --head $(git rev-parse --abbrev-ref HEAD) --json number --jq '.[0].number // empty') --json bucket --jq '...' \| grep -q true` |

8 gate commands total. Zero `default_action` occurrences confirmed — grepped the whole `skills/work-on/` tree and `koto-templates/work-on.md` frontmatter; only `gates:` blocks exist, no `default_action:` key anywhere.

## Findings — Part C: not agent-facing (out of the inventory proper)

- `scripts/lib/koto-gates.sh` — a shared awk-based reader used by `scripts/validate-template-mermaid.sh` and `scripts/ci-gate-expression_test.sh` to extract gate command strings from template YAML for drift-checking (comparing the template against its `.mermaid.md` companion, and unit-testing the `ci_passing` gate expression). Never invoked during a `/work-on` run — it's CI/dev tooling that reads the same `gate: type: command` strings inventoried in Part B, not a runtime instruction.
- `requires.tsv` — a declarative tool-dependency manifest (koto subcommands + `gh`/`git`/`jq`, each marked `always`). Corroborates Part A's tool surface but is metadata, not an instruction.
- `references/phases/phase-6-design-diagram-update.md` — no shell commands at all; entirely Read/Grep/Edit-tool regex operations on a design doc's Mermaid diagram.
- `references/verification-map.md` — no real commands; explicitly illustrative placeholders ("not a real project's map").
- `references/review-panel-orchestration.md` — pure cross-reference prose, no new commands beyond what phase-4a/b/c already state.

## Implications

- **The retry-loop clearing blocks are the strongest `default_action` candidates.** Eight near-identical blocks (verification, analysis, implementation, and all three panel files, plus finalization) run the exact same deterministic 4-key `koto context remove`/`exists` loop with a hard `exit 1` on ambiguity, then a fixed `koto next --with-data`. These are fully mechanical, already written as copy-pasted bash, and exist in the template's prose precisely because koto has no way to run them itself today. This is the single biggest concentration of MECHANICAL, judgment-free command text in the whole surface.
- **`extract-context.sh` (phase-0) is effectively a hand-rolled `default_action` already** — a deterministic script the agent is told to run verbatim, whose entire job (find doc → parse table → extract section → store to koto context.md → emit JSON) requires zero agent judgment on the happy path. It's the cleanest single-state candidate: replace the "Run this script" instruction with a `default_action` that runs the same script, falling back to agent instructions only if it exits non-zero or its JSON reports `degraded`/`failed`.
- **Every "Initialize/Execution Loop/Resume" `koto` call in SKILL.md is unavoidably agent-issued** — these bootstrap and drive the state machine itself (`koto init`, `koto next`, `koto workflows`, `koto rewind`). They can't become `default_action` inside the template because the template doesn't exist yet at `koto init` time, and the loop's whole point is the agent deciding whether to advance, submit evidence, or resume.
- **`gh issue view` repetition (4 call sites, up to 4 runs per issue) is a separate, smaller optimization opportunity** unrelated to `default_action`: caching the first read into koto context and reading from there would remove 2–3 of the mechanical re-fetches, though the phase-4-implementation.md:93 re-read is deliberately fresh (staleness protection) and should stay a live fetch.
- **The 8 existing `gate: type: command` entries are the closest existing precedent for `default_action`** on the happy path (branch check, commit check, test-passing check, CI-passing check, staleness check) — the design target's "koto runs commands on all happy paths, falling back to agent instructions only on failure" is already half-true for *checks*; it's the *actions* (context fetch/store, retry-clearing) that are still 100% prose.

## Surprises

- **`phase-2.5-worktree-discipline.md` is not orphaned but has moved homes.** Its `worktree_discipline_check` state no longer exists in `work-on.md` (confirmed — grep found zero hits in `skills/work-on/`); it now lives in `skills/execute/koto-templates/execute.md:406`, which explicitly points back at `skills/work-on/references/phases/phase-2.5-worktree-discipline.md` for the per-child instruction text. So this file is live and in-scope for `/execute`, not `/work-on` — the lead's "references/**" scope pulled in a file that's actually part of the `/execute` inventory now. Worth flagging to whoever inventories `/execute` so the `git fetch`/`git rebase` pair there isn't double-counted or missed.
- **`SKILL.md:8`'s `!`bash ...`` line is not a prose instruction to the agent at all** — it's the Claude Code harness's own preflight mechanism (executed at skill-load time via the `!` prefix and the `allowed-tools` frontmatter), architecturally distinct from every other command in this inventory, which the agent reads and then chooses to run.
- Three of the four panel-aggregation "passed" blocks (phase-4a/4b/4c) use slightly different heredoc syntax for the same `koto context add` call — `phase-4a-scrutiny.md` uses `koto context add <WF> KEY <<EOF`, while `phase-4b-review.md` and `phase-4c-qa.md` use `koto context add <WF> KEY < /dev/stdin <<EOF`. Functionally identical, textually inconsistent — a minor drift that would need normalizing if these become `default_action` templates.
- The verification-retry block (work-on.md:1046-1060) is the one retry-clearing block embedded directly in the koto **template's** prose (not a `references/phases/*.md` file) — it lives in the template's own per-state markdown section, unlike the other seven which live in the reference phase docs.

## Open Questions

- Should the `gh issue view` fetched at SKILL.md:264 (Begin) be written into koto context immediately, so `plan_context_injection`/`setup_issue_backed`/mid-implementation re-reads become `koto context get` calls instead of fresh `gh` calls — except where staleness genuinely requires a fresh fetch?
- Is `phase-2.5-worktree-discipline.md`'s `git fetch origin && git rebase origin/main` pair (now under `/execute`) in scope for this exploration's target state, or does it belong entirely to a separate `/execute`-focused inventory round?
- For the 8 retry-clearing blocks: would a single shared `default_action` (parameterized by which keys to clear and which outcome field/value to submit) cover all 8 sites, or does each state need its own because the outcome field name differs (`verification_outcome`, `plan_outcome`, `implementation_status`, `scrutiny_outcome`, `review_outcome`, `qa_outcome`, `finalization_status`)?

## Summary

`/work-on` hands the agent roughly 37 distinct hard-coded command instructions across its template and reference docs — about two-thirds are `koto` protocol calls (init/next/workflows/rewind/context add|get|exists|remove/decisions record) that must stay agent-issued since they drive the state machine itself, but eight of those are fully mechanical 4-key context-clearing retry loops (identical pattern repeated in verification, analysis, implementation, finalization, and all three review panels) plus one full script invocation (`extract-context.sh` in phase-0) that are the strongest `default_action` candidates on the repo. Separately, the template already auto-executes 8 `gate: type: command` checks (branch/commit/test/CI/staleness) via koto's existing (non-`default_action`) gate mechanism, and `gh issue view <N>` gets fetched fresh up to four times per issue-backed run with no caching. `scripts/lib/koto-gates.sh` and `requires.tsv` are meta-tooling/manifest, not agent-facing at all, and `phase-2.5-worktree-discipline.md` — while physically under `work-on/references/` — now belongs to `/execute`'s template, not `/work-on`'s.
