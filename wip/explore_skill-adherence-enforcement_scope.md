# Explore Scope: skill-adherence-enforcement

## Visibility

Public

## Scope

Tactical (cross-repo: shirabe, niwa, koto)

## Core Question

Why do agents that have shirabe skills in their toolset routinely fail to
invoke them -- improvising their own implementation loop instead -- and what
mechanism would make the sanctioned workflow the path an agent actually takes?
The mechanism must work for agents invoked by a human with a bare `/execute`
and for agents launched by another agent through `niwa dispatch`, and it must
be declarable as workspace policy by an org owner rather than re-derived per
repo.

## Context

The trigger is a concrete incident. A session was told to execute a plan. It
never invoked `shirabe:execute`; it built its own task list and implemented 22
plan outlines by hand. No koto session, no task state machine, no per-issue
spawn, no CI monitoring, no adversarial review gates. The user only found out
by asking "are you using koto for anything?" The loss was twofold: no
visibility into what was happening, and no guarantee that the plan's
validation steps ran at all.

The same failure has a second face. When an agent runs `niwa dispatch` and
synthesizes its own prompt for the worker session, it tends to describe the
task and omit which skills and workflows the worker must use -- so the worker
starts with no mandate and improvises in turn.

Two structural facts frame the problem. Shirabe ships as a Claude Code plugin
(`.claude-plugin/plugin.json`, `skills/` only -- no `commands/` directory), so
its skills surface as `shirabe:<name>`; a bare `/execute` matches nothing and
reaches the model as ordinary text it must interpret. And niwa already
distributes CLAUDE.md fragments, `.claude/settings.json`, and hook scripts
into every managed instance, which means a workspace-level policy surface
already exists physically -- what is missing is a declaration for it to carry.

User direction from scoping: the preference is strong guidance over hard
enforcement, but all points on the spectrum should be explored before
committing. The layer that owns the mechanism (shirabe, niwa, niwa dispatch,
koto) is deliberately left open for the exploration to answer. Ambition is
set to designing the general mechanism, not just patching the acute bug.

## In Scope

- Why skill invocation fails: harness mechanics of slash-command resolution,
  skill description quality, and what actually drives the model's choice
- The full strength spectrum: passive discoverability, active steering,
  detection-and-report, and hard blocking
- The configuration surface an org owner would use to declare required
  workflows, and how niwa would distribute it
- Prompt construction in `niwa dispatch` and the `/dispatch` skill
- Using koto session state as an observable adherence signal
- Cross-repo coordination between shirabe, niwa, and koto

## Out of Scope

- Rewriting the shirabe skills' internal workflows
- Changes to Claude Code itself (we can only use surfaces it already exposes)
- Any mechanism that requires an agent to be honest about its own compliance
- Telemetry or metrics collection beyond what is needed to detect skips

## Research Leads

1. **Why did a bare `/execute` fail to resolve to `shirabe:execute`, and what
   invocation surfaces does Claude Code actually offer a plugin?**
   The acute root cause. Determines whether an unqualified alias is even
   possible, and what the model sees when a slash command matches nothing.

2. **What actually causes a skill to fire, and how do shirabe's descriptions
   compare against skills that reliably trigger?**
   Skill selection is driven by frontmatter descriptions and their trigger
   phrasing. `superpowers:using-superpowers` is a working precedent for
   mandatory framing. `skill-creator` claims to measure triggering accuracy --
   whether that is usable here matters.

3. **Which hook and configuration surfaces can carry a policy, and what can
   each one actually do?**
   SessionStart additional context, UserPromptSubmit, PreToolUse deny, Stop.
   This bounds every candidate mechanism -- what can steer, what can block,
   what can only observe.

4. **What does niwa already distribute into an instance, and where would a
   declared skill policy hook into workspace config?**
   `workspace.toml`, the `[files]`/`[instance.files]`/`[root.files]` tables,
   CLAUDE.md fragment generation, settings.json and hook distribution, the
   overlay model. Defines the org-owner configuration surface.

5. **How does `niwa dispatch` build the worker's prompt, and what could be
   injected into it?**
   Covers `internal/cli/dispatch.go` and friends plus the `/dispatch` skill's
   brief synthesis. Determines whether the mandate can be added by niwa
   unconditionally rather than left to the dispatching agent's discretion.

6. **What guarantees does koto provide, and is "a koto session exists for this
   plan" observable from outside the agent?**
   Koto is what supplies the task state machine and review gates. If its state
   is externally readable, it becomes the detection substrate for both
   after-the-fact reporting and any blocking gate.

7. **What prior art exists for making a workflow mandatory in an agent
   harness, and has shirabe already attempted this?**
   Existing shirabe design docs, the parent-skill conformance and autonomy
   mandate language already in `shirabe:execute`, restricted-tool agent
   definitions, output styles, and CLAUDE.md precedence rules.
