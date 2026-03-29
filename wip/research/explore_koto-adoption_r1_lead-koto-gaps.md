# Koto Feature Gaps for Shirabe Skill Adoption

Research output for the koto-adoption exploration. Identifies koto features that
don't exist yet but are needed by shirabe skills.

## Methodology

Compared koto's current capabilities (README, source code in `src/`, open issues)
against the concrete needs of five shirabe skills: explore, design, release,
work-on, and plan.

---

## 1. Gate Types

### 1a. Polling Gate (native)

- **What skills need:** release/Phase 6 polls CI workflow status every 10
  seconds for up to 5 minutes. work-on/ci_monitor checks whether PR checks
  are passing. Both need "run this command repeatedly until it passes or
  times out."
- **What koto can do today:** `default_action` supports a `polling` config
  (`interval_secs`, `timeout_secs`) that re-runs a command in a loop. Command
  gates run once at evaluation time. There is no native "polling gate" --
  only polling default actions.
- **The gap:** The polling mechanism lives on default actions, not on gates.
  work-on's `ci_monitor` state uses a command gate for CI status, but the gate
  evaluates once. If CI isn't passing yet, the gate fails and the agent has to
  submit evidence and re-enter the state manually. A polling gate type would
  let the engine wait automatically.
- **Complexity:** Easy (hours). The `PollingConfig` struct and
  `execute_with_polling` loop already exist. Extending gate evaluation to
  support polling is mechanical.
- **Priority:** High -- 3 skills (work-on, release, plan) need CI polling.
- **Existing issue:** None found.

### 1b. External Status Gate (GitHub-aware)

- **What skills need:** release/Phase 2 checks CI status via `gh api`, checks
  for blockers via `gh issue list`, verifies no existing tags/drafts. work-on
  checks PR CI status with a brittle nested `gh` command. design checks for
  existing PRDs.
- **What koto can do today:** Command gates can run arbitrary shell. Templates
  embed raw `gh` CLI one-liners in gate commands.
- **The gap:** No structured GitHub integration. Every template reinvents
  `gh pr checks ... | jq ...` patterns. Error messages are raw shell stderr.
  Koto issue #87 explicitly calls this out: "template authors have to write raw
  gh CLI commands in gate strings."
- **Complexity:** Hard (architectural). Requires designing a gate extension
  system or built-in GitHub provider. The secondary part of issue #87 discusses
  this but no design exists.
- **Priority:** High -- 4 skills (work-on, release, plan, design) interact with
  GitHub. But the workaround (shell commands) is functional if fragile.

---

## 2. Flow Control

### 2a. Discover-Converge Loop (bounded iteration)

- **What skills need:** explore runs a discover-converge loop: Phase 2 (fan out
  research agents) -> Phase 3 (converge findings) -> decision point -> either
  loop back to Phase 2 with incremented round counter, or proceed to Phase 4.
  The loop has a configurable max rounds (default 3 in --auto mode).
- **What koto can do today:** Self-loops via conditional transitions (a state
  can transition back to itself). The work-on template uses this for retry
  patterns (`scope_changed_retry`, `partial_tests_failing_retry`). Cycle
  detection fires when the advancement loop revisits a state, but self-loops
  with `when` blocks bypass it.
- **The gap:** No loop counter or bounded iteration primitive. Templates can
  model retries via self-loops, but there's no engine-level "run this state
  sequence N times." The explore skill manages loop state entirely in SKILL.md
  prose (increment N, update scope file, return to Phase 2). A koto template
  can't express "allow up to 3 iterations of states A->B before forcing
  transition to C."
- **Complexity:** Medium (days). Needs a counter mechanism -- either a special
  variable that auto-increments on self-loop transitions, or a `max_visits`
  field on states/transitions.
- **Priority:** Medium -- 2 skills (explore, work-on) need bounded loops.
  work-on already works around it with prose instructions ("up to 3 times").

### 2b. Parallel Branches (fan-out / fan-in)

- **What skills need:** explore/Phase 2 fans out up to 8 research agents in
  parallel, each investigating a lead. design/Phase 2 spawns parallel decision
  agents (one per decision question). Both need fan-out, wait-for-all, then
  continue.
- **What koto can do today:** Strictly linear state machine. One current state.
  No concept of parallel execution paths. The `integration` field on states
  can invoke external tools, but there's no multi-branch execution.
- **The gap:** No parallel branch support. Skills handle parallelism outside
  koto (using Claude Code's `run_in_background` for Task agents). Koto can't
  model "spawn N parallel sub-workflows, wait for all to complete, then
  advance." This is the single largest structural gap.
- **Complexity:** Hard (architectural). Requires rethinking the single-state
  model. Possible approaches: sub-workflow spawning, parallel state sets, or
  simply accepting that parallelism lives outside koto and adding a
  "wait-for-artifacts" gate type instead.
- **Priority:** High -- 3 skills (explore, design, decision) use parallel
  agents. But the workaround (skill-layer parallelism via Task agents) is
  functional and well-established.

### 2c. Conditional Phases (skip/include based on variables)

- **What skills need:** work-on has two entry paths (issue-backed vs free-form)
  sharing later states. explore skips triage for non-issue invocations. design
  includes market context only for strategic+private scope.
- **What koto can do today:** Conditional transitions via `when` blocks that
  match evidence fields. The work-on template uses this effectively -- the
  `entry` state routes to `context_injection` or `task_validation` based on
  the `mode` evidence field.
- **The gap:** Minimal. The conditional transition system handles this pattern
  well. The only gap is that conditions can only match on the current state's
  evidence, not on workflow-scoped variables. Issue #65 (`--var` support) and
  issue #87 (evidence promotion to variables) would close this completely.
- **Complexity:** Already addressed by existing issues.
- **Priority:** Addressed by koto #65 and #87.

---

## 3. Integration

### 3a. Template Variable Substitution (`--var`)

- **What skills need:** work-on needs `{{ISSUE_NUMBER}}` and
  `{{ARTIFACT_PREFIX}}` in gate commands and directives. These are set at
  workflow init time and used throughout.
- **What koto can do today:** Variables are declared in templates and the
  `WorkflowInitialized` event has a `variables` field, but `koto init` accepts
  no `--var` flag. The substitution engine exists for `{{SESSION_DIR}}` and
  `{{SESSION_NAME}}` (runtime-injected), but user-defined variables aren't
  wired up.
- **The gap:** The plumbing exists but isn't connected. No `--var` flag on
  init, no substitution of user variables in gates/directives.
- **Complexity:** Medium (days). The design is clear (koto issue #65 has a
  detailed spec). Needs CLI flag, validation, event storage, and runtime
  substitution.
- **Priority:** Critical -- work-on template is blocked on this. It's the
  single most important missing feature for adoption.
- **Existing issue:** koto #65 (needs-design).

### 3b. Evidence Promotion to Workflow Variables

- **What skills need:** work-on's `pr_creation` state captures `pr_url`. The
  next state (`ci_monitor`) needs to reference it in gate commands. Currently
  the CI monitor gate re-derives the PR number with nested shell commands.
- **What koto can do today:** Evidence is epoch-scoped -- cleared on state
  transition. No way to carry a value forward.
- **The gap:** No evidence-to-variable promotion. Values captured in one state
  can't be referenced in later states' gate commands.
- **Complexity:** Medium (days). Requires a `promote: true` field on evidence
  schemas and wiring promoted values into the variable substitution system.
- **Priority:** High -- eliminates the most fragile gate command in work-on.
  Also benefits release (carry forward version, tag, PR URL).
- **Existing issue:** koto #87.

### 3c. Cross-Agent Delegation

- **What skills need:** explore fans out research to specialized agents.
  design delegates decision evaluation to the decision skill. Both spawn
  agents with specific prompts and collect structured results.
- **What koto can do today:** The `integration` field on states can invoke
  external tools, but the delegation mechanism isn't implemented. Issue #41
  describes the full design: tags on states, config-based routing, a
  `koto delegate submit` command.
- **The gap:** No delegation infrastructure. Skills handle agent spawning
  entirely outside koto.
- **Complexity:** Hard (architectural). Issue #41 is a multi-part design
  covering tags, config, routing, and invocation.
- **Priority:** Medium-Low for adoption. Skills already work around this
  using Claude Code's native agent spawning. Delegation would add
  observability and cross-model routing but isn't blocking.
- **Existing issue:** koto #41 (needs-design).

---

## 4. Visibility

### 4a. Decision Audit Trail (mid-state capture)

- **What skills need:** work-on's `analysis` and `implementation` states
  record structured decisions (`{choice, rationale, alternatives_considered}`).
  explore records scope narrowing and option elimination decisions across
  convergence rounds. design records decision outcomes from each question.
- **What koto can do today:** The `DecisionRecorded` event type exists in the
  engine type system. The event payload carries `state` and `decision` (JSON
  value). But there's no CLI mechanism to submit decisions mid-state without
  triggering the advancement loop.
- **The gap:** The event type is defined but the submission path isn't wired
  up. Agents can't record decisions incrementally during long-running states.
  Evidence submission (`--with-data`) triggers advancement, which is wrong
  for mid-state decision capture.
- **Complexity:** Medium (days). The event type exists. Needs a CLI mechanism
  (flag or subcommand) to append decision events without triggering advancement.
- **Priority:** Medium -- 3 skills (work-on, explore, design) benefit. The
  work-on template already includes `decisions` in its `accepts` schemas,
  but they're submitted with completion evidence, not incrementally.
- **Existing issue:** koto #66 (needs-design).

### 4b. Phase Timing and Progress

- **What skills need:** release/Phase 6 tracks dispatch timestamps to correlate
  with workflow runs. explore tracks round numbers across discover-converge
  iterations. work-on could benefit from knowing how long each phase took.
- **What koto can do today:** Events have RFC 3339 timestamps. The state log
  captures every transition with timing. `koto session list` shows active
  sessions.
- **The gap:** No built-in timing queries. An agent would need to replay the
  event log and compute durations manually. No "time spent in state X" query.
- **Complexity:** Easy (hours). A `koto query timing` subcommand that reads
  the event log and computes per-state durations.
- **Priority:** Low -- nice to have for observability, not blocking any skill.

### 4c. State Introspection (query accumulated evidence)

- **What skills need:** work-on's resume logic needs to know what evidence
  was submitted in the current epoch. design's cross-validation phase reads
  decision reports from previous phases. explore reads accumulated findings.
- **What koto can do today:** `koto next` returns the current directive and
  expects schema. The state log contains all evidence events. No dedicated
  query interface for "what evidence has been submitted in the current state."
- **The gap:** No evidence query mechanism. Skills work around this by writing
  artifacts to wip/ files and reading them back, rather than querying koto's
  event log.
- **Complexity:** Easy-Medium. A `koto query evidence` command that filters
  the event log for the current epoch's evidence events.
- **Priority:** Low -- the wip/ artifact pattern works. Would improve
  koto-native workflows but isn't blocking.

---

## 5. Template Features

### 5a. Template Composition (reusable sub-templates)

- **What skills need:** work-on shares setup, implementation, and PR creation
  patterns with potential future skills. design and explore both have
  setup/teardown phases that follow the same pattern. A "CI monitor" sequence
  (create PR -> check CI -> fix failures) appears in work-on, release, and
  plan.
- **What koto can do today:** Templates are monolithic markdown files. No
  include, import, or composition mechanism.
- **The gap:** No template composition. Every template duplicates shared
  patterns. The work-on template is 560+ lines because it can't factor out
  common sequences.
- **Complexity:** Medium (days). Could be as simple as a YAML `includes`
  directive that merges state blocks from referenced templates, or as complex
  as sub-workflow invocation.
- **Priority:** Medium -- reduces maintenance burden as more skills adopt koto
  templates, but each template works standalone today.
- **Existing issue:** None found.

### 5b. Inline Phase Details on First Visit

- **What skills need:** work-on's directives reference external phase files
  ("Read references/phases/phase-1-setup.md"). On first visit, the agent needs
  the full directive. On resume (re-entering a state after rewind), a shorter
  version suffices.
- **What koto can do today:** Directives are static text per state. The
  `advanced` flag in `koto next` output indicates whether the call caused a
  state change, but there's no visit-count-aware directive variation.
- **The gap:** No first-visit vs repeat-visit directive differentiation.
- **Complexity:** Medium (days). Needs visit counting in the engine and
  conditional directive text in templates.
- **Priority:** Medium -- improves token efficiency on resume. Already tracked.
- **Existing issue:** koto #90.

### 5c. Variable Substitution in Transitions

- **What skills need:** work-on could express conditional transitions based on
  workflow variables (not just current evidence). Example: "if ISSUE_NUMBER is
  set, go to context_injection; otherwise go to task_validation."
- **What koto can do today:** Transition `when` blocks match against evidence
  fields submitted with `--with-data`. No matching against workflow variables.
- **The gap:** Transition conditions can only match evidence, not variables.
  work-on works around this by having the entry state accept a `mode` evidence
  field that the agent sets based on the presence of ISSUE_NUMBER.
- **Complexity:** Easy-Medium. Extend transition resolution to also check
  workflow variables in `when` blocks.
- **Priority:** Low -- the evidence-based workaround is clean and explicit.
  Would reduce one layer of indirection.

---

## Summary: Priority Ranking

| # | Gap | Complexity | Skills Affected | Blocked? | Existing Issue |
|---|-----|-----------|-----------------|----------|----------------|
| 1 | Variable substitution (`--var`) | Medium | work-on, release | Yes | koto #65 |
| 2 | Evidence promotion to variables | Medium | work-on, release | Partial | koto #87 |
| 3 | Mid-state decision capture | Medium | work-on, explore, design | No | koto #66 |
| 4 | Polling gate type | Easy | work-on, release, plan | No | None |
| 5 | Bounded iteration (loop counters) | Medium | explore, work-on | No | None |
| 6 | Parallel branches | Hard | explore, design, decision | No | Partly #41 |
| 7 | Template composition | Medium | All skills | No | None |
| 8 | Inline phase details (first visit) | Medium | work-on | No | koto #90 |
| 9 | GitHub-aware gates | Hard | work-on, release, plan, design | No | Partly #87 |
| 10 | Phase timing queries | Easy | release, explore | No | None |

### Critical Path for work-on Adoption

The work-on template already exists and uses koto's current features with
workarounds. To fully adopt koto enforcement, the minimum viable set is:

1. **koto #65** -- `--var` support (template variables like `{{ISSUE_NUMBER}}`)
2. **koto #87** -- evidence promotion (carry `pr_url` to ci_monitor)

With these two, the work-on template's gate commands become clean and the
template can run without skill-layer workarounds for variable passing.

### Critical Path for explore/design Adoption

These skills use parallel agent fan-out, which koto can't model natively.
The pragmatic path is to accept that parallelism lives outside koto and
instead add:

1. A **context-exists gate with glob/count** -- "at least N context keys
   matching pattern X exist" -- so koto can gate on "all research agents
   have submitted their findings."
2. **Bounded iteration** -- so koto can enforce max rounds on the
   discover-converge loop.

### Features That Aren't Gaps

Several things that might seem like gaps are actually handled well:

- **Conditional routing** -- `when` blocks on transitions handle split
  topologies (issue-backed vs free-form) cleanly.
- **Self-loops for retry** -- work-on's retry patterns work with current
  conditional transitions.
- **Context-based gates** -- `context-exists` and `context-matches` handle
  artifact validation without shell commands.
- **Session management** -- automatic cleanup, session directories, and
  `{{SESSION_DIR}}` substitution work well for artifact storage.
- **Rewind** -- recovery from blocked states is clean.
