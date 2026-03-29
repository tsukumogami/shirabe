# Work-On Skill: Koto Integration Reference Analysis

## Template Structure

### States and Topology

The koto template (`work-on.md`) defines 16 states organized into a split-topology workflow:

- **Entry**: single `entry` state with mode-based routing (issue_backed vs free_form)
- **Issue-backed path**: entry -> context_injection -> setup_issue_backed -> staleness_check -> (optional introspection) -> analysis
- **Free-form path**: entry -> task_validation -> research -> post_research_validation -> setup_free_form -> analysis
- **Shared tail**: analysis -> implementation -> finalization -> pr_creation -> ci_monitor -> done
- **Terminal states**: done, done_blocked, validation_exit

The split happens at `entry` via a `when` clause on the `mode` enum. Both paths converge at `analysis`. This is the most complex topology in the skill set -- 16 states, 2 terminal error states, and 1 validation-specific exit.

### Variables

Two template variables are declared:
- `ISSUE_NUMBER` (optional) -- used in command gates like `check-staleness.sh --issue {{ISSUE_NUMBER}}`
- `ARTIFACT_PREFIX` (required) -- used as the workflow name prefix for context keys and branch names

Variables are set at `koto init` time via `--var` flags. The template uses `{{ISSUE_NUMBER}}` Mustache-style interpolation inside gate commands.

### Gates

Three gate types are used:

1. **context-exists**: checks if a koto context key exists (e.g., `context.md`, `baseline.md`, `plan.md`, `summary.md`, `introspection.md`). These enforce that the skill wrote an artifact before advancing.
2. **command**: runs a shell command and checks exit code. Examples:
   - `test "$(git rev-parse --abbrev-ref HEAD)" != "main"` (on feature branch)
   - `go test ./...` (tests pass)
   - `check-staleness.sh --issue {{ISSUE_NUMBER}} | jq -e ...` (staleness check)
   - Complex `gh pr checks` pipeline for CI status
3. No "approval" or "human" gate type exists -- the skill handles interactive/auto mode outside koto.

### Evidence Fields

Every state declares `accepts` with typed fields:

- **Enums with options**: most states use an enum field as the primary signal (e.g., `status: completed|override|blocked`, `plan_outcome: plan_ready|scope_changed_retry|...`)
- **String fields**: for rationale, detail, summaries, URLs
- **Decisions field**: analysis and implementation states accept a `decisions` string containing a JSON array of `{choice, rationale, alternatives_considered}` records

The evidence pattern is consistent: one primary enum drives the transition, plus optional string fields for context. The `transitions` block matches `when` clauses against the enum value.

### Self-Loops

Three states have self-loop transitions for retry:
- `analysis`: `scope_changed_retry` loops back (up to 3, then `scope_changed_escalate`)
- `implementation`: `partial_tests_failing_retry` loops back (up to 3, then escalate)
- `pr_creation`: `creation_failed_retry` loops back (up to 3, then escalate)

The retry count is NOT tracked by koto. The template comment says "Self-loops use conditional when blocks to avoid triggering cycle detection," but the actual retry counting (up to 3) is enforced by the skill's prose instructions, not by koto itself.

## Orchestration Pattern

### Init

```bash
koto init <WF> --template ${CLAUDE_SKILL_DIR}/koto-templates/work-on.md \
  --var ISSUE_NUMBER=<N> --var ARTIFACT_PREFIX=issue_<N>
```

The skill constructs the workflow name (`<WF>`) from the artifact prefix. The `$CLAUDE_SKILL_DIR` environment variable resolves the template path relative to the skill installation.

### Execution Loop

The SKILL.md defines a tight loop:

1. `koto next <WF>` -- returns action + directive
2. If `advanced: true` -- auto-advanced (gate passed), call `koto next` again
3. If `expects` present -- do work, then submit evidence via `koto next <WF> --with-data '{...}'`
4. If `action: "done"` -- stop

This is a polling loop driven by the skill. Koto is passive -- it never pushes. The skill calls `koto next` and interprets the response.

### Resume

1. `koto workflows` to find active workflow
2. If found, `koto next <WF>` picks up where it left off
3. If none, `koto init` fresh

Resume works because koto persists workflow state. The gates (context-exists, command) re-check on resume, so a stale session can still advance if conditions are met.

### Context as Artifact Store

Koto's `context` subsystem serves as the artifact store:

- `koto context add <WF> plan.md --from-file <file>` -- store artifact
- `koto context get <WF> plan.md` -- retrieve artifact
- `koto context exists <WF> context.md` -- check existence
- Gates use `context-exists` type to verify artifacts

This replaces the older `wip/` file convention. The extract-context.sh script has a fallback: if koto is unavailable, it writes to `wip/IMPLEMENTATION_CONTEXT.md` instead.

### Decision Capture

```bash
koto decisions record <WF> --with-data '{"choice": "...", "rationale": "...", "alternatives_considered": [...]}'
```

Decisions are recorded as a side-channel, not part of the state machine transitions. The analysis and implementation states also accept `decisions` as evidence fields, creating two paths for decision recording.

## What Works Well

1. **Clean separation of concerns**: the koto template handles state machine logic (valid transitions, gate enforcement), while phase files handle domain instructions. Neither duplicates the other.

2. **Context as shared memory**: koto's context store solves the sub-agent coordination problem. The analysis agent writes `plan.md` to koto context; the main agent retrieves it in implementation. No temp files, no passing large strings between agents.

3. **Typed evidence with enums**: evidence schemas prevent invalid transitions. The enum values map 1:1 to transition targets, making the state machine self-documenting.

4. **Split topology with convergence**: the issue-backed and free-form paths share the entire implementation tail. This avoids duplicating 6+ states while still allowing mode-specific setup.

5. **Gate-based auto-advance**: when gates pass (e.g., already on a feature branch, tests already pass), `koto next` auto-advances. The skill handles this with the `advanced: true` check, making resume and re-entry smooth.

6. **Resume from interruption**: the combination of persistent state + gate re-evaluation means a crashed session can pick up cleanly. The skill just calls `koto workflows` and `koto next`.

## What's Awkward

### 1. Retry counting lives in prose, not in koto

The template declares self-loops but has no mechanism to count iterations. The phase file says "up to 3 times," but nothing enforces this. The skill relies on the LLM reading the prose and counting. If the LLM loses track, it could loop indefinitely or escalate prematurely.

**Workaround**: the skill text says "up to 3 times" and trusts the agent to count.

### 2. Parallel agents are outside koto

Phase 3 (analysis) launches a sub-agent via the Task tool. This agent reads from and writes to koto context, but koto has no awareness that delegation happened. The sub-agent's lifecycle, error handling, and output validation are all managed by the skill's prose instructions, not by koto's state machine.

Phase 4 (implementation review) can launch multiple specialized agents (security, performance, testing, architecture). These are completely outside koto's model.

**Workaround**: the skill passes the workflow name to agents so they can use `koto context` as shared storage, but koto doesn't track agent count, status, or coordination.

### 3. CI monitoring gate is a fragile shell pipeline

The `ci_monitor` gate is:
```bash
gh pr checks $(gh pr list --head $(git rev-parse --abbrev-ref HEAD) --json number --jq '.[0].number // empty') --json state --jq '[.[] | select(.state != "SUCCESS")] | length == 0' | grep -q true
```

This is a complex pipeline that can fail for many reasons (no PR found, checks still pending, API rate limits). Koto treats any non-zero exit as gate failure, so the skill must handle all these cases in its phase file prose.

**Workaround**: the phase file says "if stuck after 2-3 iterations, ask the user."

### 4. The `override` escape hatch is pervasive

Several states accept `status: override` as evidence, which bypasses the gate entirely. This exists because gates can fail for legitimate reasons (e.g., reusing an existing branch, providing context through a different mechanism). But it means the skill can bypass any gate enforcement if the LLM decides to.

**Implication**: gate enforcement is advisory, not absolute. The override pattern makes koto a soft guardrail rather than a hard constraint.

### 5. Go-specific gate in the template

The `implementation` gate includes `go test ./... 2>/dev/null`, hardcoding a Go-specific test command. This makes the template non-portable to non-Go projects without modification. The skill's extension mechanism (`.claude/shirabe-extensions/work-on.md`) could override this, but the gate is baked into the koto template.

### 6. Duplicate state pairs for setup

`setup_issue_backed` and `setup_free_form` are nearly identical (same gates, same evidence schema). They exist only because transitions from different source states need different targets. This suggests koto lacks a "merge point" or "join" concept that would let both paths converge without duplicating the target state.

### 7. The wip/ fallback in extract-context.sh

The context injection script has a fallback path: if koto is unavailable, it writes to `wip/IMPLEMENTATION_CONTEXT.md`. This shows that the koto integration was retrofitted onto an existing wip/-based workflow, and the fallback was kept as a safety net.

### 8. No polling or wait primitive for CI

The ci_monitor state has a gate that checks CI status, but there is no built-in way to wait/poll. The skill must repeatedly call `koto next`, which re-evaluates the gate. There is no sleep, backoff, or notification mechanism in koto.

## Reusable Patterns

1. **Template + phase file separation**: define the state machine in the koto template, put domain instructions in `references/phases/` files. The template's markdown body sections reference phase files by name.

2. **Evidence enum driving transitions**: one primary enum field per state, with values mapping to transition targets. Add optional string fields for context/rationale.

3. **Context-exists gates for artifact checkpoints**: use koto context as the artifact store and `context-exists` gates to enforce that artifacts were created before advancing.

4. **Resume protocol**: `koto workflows` -> check for active -> `koto next` or `koto init`. This is a 3-line pattern any skill can adopt.

5. **Override evidence value**: include an `override` option in states where gates might legitimately fail. Document when overrides are appropriate.

6. **Split-and-converge topology**: use `when` clauses on entry evidence to route into mode-specific paths, converging at a shared state for common tail logic.

7. **Sub-agent + koto context sharing**: pass the workflow name to sub-agents so they can read/write koto context. The main agent doesn't need to relay large artifacts.

8. **Decision capture as side-channel**: `koto decisions record` for non-obvious choices, separate from state transitions.

## What's Missing from Koto

1. **Retry counters**: self-loops have no iteration tracking. The skill can't say "max 3 retries" in the template and have koto enforce it.

2. **Agent/task delegation primitive**: no way to declare that a state delegates to a sub-agent, track its lifecycle, or gate on its completion.

3. **Polling/wait primitive**: no way to say "check this gate every 30 seconds for up to 10 minutes." CI monitoring requires manual re-invocation.

4. **Parameterized gates**: the `go test ./...` hardcoding could be avoided if gates supported variable interpolation from the skill's extension config, not just template variables.

5. **State merging/join**: no way to have two states share a definition, leading to the setup_issue_backed / setup_free_form duplication.

6. **Conditional gate evaluation**: gates are all-or-nothing. There is no "soft gate" concept where the gate result is advisory and the evidence determines advancement. The skill works around this with the `override` pattern.

7. **Timeout/deadline**: no way to set a time limit on a state or workflow. A stuck workflow stays stuck until the next `koto next` call.

8. **Event-driven advancement**: koto is purely pull-based (the skill calls `koto next`). There is no webhook, callback, or push mechanism for external events like CI completion.

9. **Structured context validation**: `context-exists` checks key existence but not content structure. The skill can't gate on "context.md exists AND has non-empty constraints field."

10. **Cross-workflow references**: no way to reference or depend on another workflow's state. Each workflow is isolated.
