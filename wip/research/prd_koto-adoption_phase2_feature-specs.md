# Koto Feature Request Specifications

Feature specs derived from the koto-adoption gap analysis. Each targets a gap
not already tracked by existing koto issues (#65, #66, #87, #41, #90, #102).

---

## 1. Polling/Wait Gate

**Title**: feat(engine): add polling gate type for external status checks

### Problem Statement

Koto has a polling mechanism on `default_action` (interval + timeout), but no
equivalent on gates. When a gate checks an external condition that isn't ready
yet (CI status, deployment health, external approval), the gate fails and the
agent must manually re-invoke `koto next`. There is no way to say "keep
checking this gate every N seconds until it passes or times out."

The work-on template's `ci_monitor` state illustrates this: the command gate
runs a `gh pr checks` pipeline that fails if CI is still in progress. The
skill's phase file tells the agent to retry manually, creating a fragile
poll-by-hand loop.

### Use Cases

**work-on / ci_monitor**: After PR creation, the workflow gates on all CI
checks passing. Today the agent calls `koto next` repeatedly; with a polling
gate, koto itself would wait up to 10 minutes, checking every 30 seconds.

**release / Phase 6 (dispatch monitoring)**: After triggering a release
workflow, the skill polls `gh run view` for completion. A polling gate would
let the template express this directly.

**plan / CI validation**: After filing issues, the plan skill verifies that
issue creation didn't trigger any CI failures. Same polling pattern.

### Proposed Behavior

Add `polling` configuration to command gates, reusing the existing
`PollingConfig` struct (`interval_secs`, `timeout_secs`):

```yaml
states:
  ci_monitor:
    gates:
      ci_passing:
        type: command
        command: "gh pr checks {{PR_NUMBER}} --json state --jq '...' | grep -q true"
        polling:
          interval_secs: 30
          timeout_secs: 600
```

When `koto next` evaluates this gate:
1. Run the command. If exit 0, gate passes.
2. If non-zero, sleep `interval_secs` and retry.
3. Repeat until the command succeeds or `timeout_secs` is exceeded.
4. On timeout, return `GateBlocked` with a message indicating the polling
   timed out after N attempts.

The `koto next` call blocks for the duration of the polling. This matches the
existing `execute_with_polling` behavior on default actions.

### Complexity Estimate

**Easy (hours)**. The `PollingConfig` struct and `execute_with_polling` loop
already exist in the codebase for default actions. The work is:
- Allow `polling` field in gate YAML schema
- Wire gate evaluation through the existing polling loop
- Add timeout reporting to `GateBlocked` response

---

## 2. Bounded Iteration / Loop Counter

**Title**: feat(engine): bounded self-loop iteration with max_visits

### Problem Statement

Koto supports self-loops via conditional transitions (a state can transition
back to itself). But there is no mechanism to count iterations or cap them.
Templates that use self-loops for retry patterns (work-on's
`scope_changed_retry`, `partial_tests_failing_retry`) rely on prose
instructions telling the agent to stop after 3 attempts. The agent must count
on its own, which is unreliable.

The explore skill's discover-converge loop is the most demanding case: Phase 2
fans out research, Phase 3 converges, and the workflow may loop back to Phase 2
up to 3 times. Today this loop counter lives entirely in the skill's markdown
instructions.

### Use Cases

**explore / discover-converge loop**: The loop between research dispatch and
convergence should run at most 3 rounds in auto mode. A `max_visits` on the
research dispatch state would let koto enforce the cap and force advancement
to the synthesis phase.

**work-on / analysis retries**: The `analysis` state loops on
`scope_changed_retry`. The template says "up to 3 times" but koto doesn't
enforce it. With `max_visits: 4` (initial + 3 retries), koto could reject
the self-loop transition after the limit.

**work-on / implementation retries**: Same pattern -- `implementation` loops on
`partial_tests_failing_retry` with an unenforced prose-level cap.

**design / corrective loop**: The design skill's validation phase can loop back
to revision. Bounding this prevents infinite revision cycles.

### Proposed Behavior

Add a `max_visits` field on states. The engine tracks how many times a state
has been entered (counting `transitioned` events with `to: <state>` in the
event log). When `max_visits` is reached, transitions targeting that state
are treated as blocked.

```yaml
states:
  analysis:
    max_visits: 4
    accepts:
      plan_outcome:
        type: enum
        values: [plan_ready, scope_changed_retry, scope_changed_escalate, blocked]
        required: true
    transitions:
      - target: analysis
        when:
          plan_outcome: scope_changed_retry
      - target: implementation
        when:
          plan_outcome: plan_ready
      - target: done_blocked
        when:
          plan_outcome: scope_changed_escalate
```

When the engine processes a transition targeting `analysis` and the visit count
equals `max_visits`, the transition is blocked. The response should include
the visit count and limit so the agent can choose an alternative path (e.g.,
escalate instead of retry).

A complementary approach: expose a `{{VISIT_COUNT}}` variable per state,
usable in `when` conditions. This would let templates express "if visit count
>= 3 AND evidence is retry, route to escalate" without a hard `max_visits`
cutoff.

### Complexity Estimate

**Medium (days)**. Requires:
- Adding `max_visits` to the template schema and compiler validation
- Counting state entries from the event log during transition resolution
- Reporting the limit in the response when a transition is blocked
- Optional: `{{VISIT_COUNT}}` variable injection

---

## 3. Glob-Aware context-exists Gate

**Title**: feat(engine): glob pattern matching for context-exists gates

### Problem Statement

The `context-exists` gate checks whether a single, exact key exists in the
context store. Skills that fan out parallel work and collect results need to
gate on "all expected artifacts exist." Today, each artifact needs its own
separate gate entry, and the gate author must know the exact key names at
template authoring time.

The explore skill dispatches N research agents that each write a context key
like `research/r1_lead-<name>.md`. The number and names of these keys aren't
known until runtime. There is no way to express "at least 3 keys matching
`research/r1_lead-*.md` exist" in a gate.

### Use Cases

**explore / convergence gate**: After dispatching research agents, the
convergence phase should wait until all research outputs are present. With glob
matching: `pattern: "research/r1_lead-*.md"`, `min_count: 3`.

**design / decision collection**: Design dispatches one agent per decision
question. The synthesis phase needs all decision reports. Glob gate:
`pattern: "decisions/q*.md"`, `min_count` matching the number of questions.

**work-on / multi-artifact validation**: If a future version of work-on
produces multiple review artifacts (security, performance, architecture), a
glob gate could verify all are present without listing each explicitly.

### Proposed Behavior

Extend the `context-exists` gate type with optional `pattern` and `min_count`
fields. When `pattern` is present, the gate lists context keys matching the
glob and checks whether the match count meets `min_count`.

```yaml
states:
  convergence:
    gates:
      all_research_complete:
        type: context-exists
        pattern: "research/r1_lead-*.md"
        min_count: 3
```

Behavior:
- `koto context list <WF> --prefix research/` already returns matching keys.
  The gate applies glob matching over those keys.
- If `min_count` is omitted, default to 1 (at least one match).
- The existing `key` field and new `pattern` field are mutually exclusive.
- On failure, report the current match count vs the required minimum.

Variable substitution should work in `pattern` and `min_count`:
```yaml
pattern: "research/r{{ROUND}}_lead-*.md"
min_count: "{{AGENT_COUNT}}"
```

### Complexity Estimate

**Easy-Medium (1-2 days)**. Requires:
- Extending the gate schema to accept `pattern` and `min_count`
- Implementing glob matching over context store key listing
- Compiler validation (key vs pattern mutual exclusivity)
- Variable substitution in the new fields (depends on #65)

---

## 4. Content-Match Gate

**Title**: feat(engine): content-match gate for file and context validation

### Problem Statement

The `context-matches` gate checks context store content against a regex. But
skills also need to validate files on disk (not in the context store) and
check structured content like YAML frontmatter or JSON fields. Today,
templates embed complex `jq` or `grep` pipelines in command gates to achieve
this, producing opaque error messages when validation fails.

The work-on template's staleness check gate runs
`check-staleness.sh --issue {{ISSUE_NUMBER}} | jq -e '.introspection_recommended == false'`.
If this fails, the agent sees a raw non-zero exit code with no explanation of
what field had what value.

### Use Cases

**work-on / staleness validation**: Instead of piping through jq in a command
gate, a content-match gate could run the staleness check command and validate
the output against a pattern, providing a clear message on mismatch.

**explore / frontmatter status check**: After research agents write outputs,
the convergence phase could validate that each document's frontmatter contains
`status: complete` rather than `status: draft`, gating on content quality.

**release / changelog validation**: The release skill could gate on the
CHANGELOG containing an entry for the target version, using a regex like
`## \[{{VERSION}}\]`.

**plan / issue body validation**: After creating issues, the plan skill could
verify each issue body contains required sections (acceptance criteria,
complexity estimate) by matching against section header patterns.

### Proposed Behavior

Add a `content-match` gate type that reads from a file path or command output
and matches against a regex pattern. This combines the data-access flexibility
of command gates with the pattern-matching semantics of context-matches.

```yaml
states:
  staleness_check:
    gates:
      not_stale:
        type: content-match
        source: command
        command: "check-staleness.sh --issue {{ISSUE_NUMBER}}"
        pattern: '"introspection_recommended":\s*false'
        message: "Issue spec appears stale -- introspection may be needed"
```

Alternative form reading from a file:

```yaml
gates:
  changelog_updated:
    type: content-match
    source: file
    path: "CHANGELOG.md"
    pattern: "## \\[{{VERSION}}\\]"
    message: "CHANGELOG.md missing entry for version {{VERSION}}"
```

Fields:
- `source`: `command`, `file`, or `context` (for context store keys)
- `command`/`path`/`key`: the data source (mutually exclusive, based on source)
- `pattern`: regex to match against the content
- `message`: human-readable explanation shown when the gate fails

The `message` field is the key differentiator from command gates. Instead of
"command exited with code 1," the agent sees a meaningful explanation of what
content was expected.

### Complexity Estimate

**Medium (days)**. Requires:
- New gate type in the schema and compiler
- Source resolution (command execution, file read, or context lookup)
- Regex matching with the existing regex engine
- Custom failure message rendering
- Variable substitution in all fields

---

## Summary

| # | Feature | Title | Complexity | Depends On |
|---|---------|-------|-----------|------------|
| 1 | Polling gate | feat(engine): add polling gate type for external status checks | Easy | None |
| 2 | Bounded iteration | feat(engine): bounded self-loop iteration with max_visits | Medium | None |
| 3 | Glob context-exists | feat(engine): glob pattern matching for context-exists gates | Easy-Medium | #65 (for variable substitution in patterns) |
| 4 | Content-match gate | feat(engine): content-match gate for file and context validation | Medium | None |

### Priority for Shirabe Adoption

The polling gate (1) and bounded iteration (2) address the most frequently
encountered workarounds across skills. The glob context-exists gate (3) is
essential for any skill that fans out parallel agents and needs to reconverge.
The content-match gate (4) is a quality-of-life improvement that reduces
brittle shell pipelines in templates.

Combined with the existing issues (#65 variable substitution, #87 evidence
promotion), these four features would close the remaining gaps for full koto
adoption across all shirabe skills.
