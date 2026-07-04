# Explore Scope: session-work-summary

## Visibility

Public

## Core Question

How should agent sessions periodically surface a standardized summary of the work
in flight — PRs, their status, and their links — so users can find them in a long
chat without every message ending in a summary block? Where should the convention
live (a shirabe skill/template, a niwa-injected instruction, a Claude Code hook,
or something else), and what cadence mechanism (timer, turn count, event-based)
actually works in the harness?

## Context

Claude Code has improved PR-number surfacing, but in long sessions with multiple
concurrent PRs it's still hard to locate PR links in the chat history. The user
wants a standardized summary template but explicitly does NOT want it appended to
every message — cadence should be timer- or turn-count-based (or event-based).
The candidate homes named so far: the shirabe plugin (which owns work-on/execute
and PR-creation conventions) or a standard instruction injected by niwa (which
provisions instances and session configuration). The right answer may combine a
template convention with a delivery/cadence mechanism.

## In Scope

- The summary template itself: structure, fields (PR number, repo, title, status,
  CI state, link), formatting for scannability in a terminal chat
- Cadence mechanisms: what Claude Code hooks/features can trigger or inject
  content on a timer, turn count, or event (PR created/updated, session stop)
- Where the convention lives: shirabe skill conventions, niwa-injected
  instructions/hooks, workspace CLAUDE.md, Claude Code native features
- Reliability: whether the summary should render from chat memory or from durable
  state (gh queries, state files)

## Out of Scope

- Changes to Claude Code itself (we consume its extension points, not modify it)
- Multi-user / team notification systems (Slack digests etc.)
- Redesigning shirabe's PR-creation workflow — only how results are surfaced

## Research Leads

1. **What extension points does Claude Code offer for injecting recurring or conditional instructions into a session?**
   Hooks (Stop, PostToolUse, UserPromptSubmit, SessionStart), statusline, CLAUDE.md, system reminders, task list — which can count turns, measure elapsed time, or react to PR-related tool calls, and what are their injection semantics (context injection vs. blocking vs. display-only)?

2. **How do shirabe skills currently surface PR links and status, and where do they fall short?**
   Read work-on, execute, pr-creation, and release skills for existing summary/reporting conventions. The gap analysis grounds what a standardized template must add.

3. **What injection surfaces does niwa already control, and could it deliver a session-wide instruction or hook?**
   niwa provisions instances, writes workspace-context.md, installs .claude/settings.json with SessionStart hooks, and merges overlays. What would it take for niwa to inject a standing "work summary" instruction or a cadence hook into every session it provisions?

4. **What should the summary render from — conversation memory or durable state?**
   An instruction-only approach relies on the model remembering PRs; a state-file or `gh`-query approach survives context compaction. What state already exists (wip/ files, gh CLI, koto state) and what does each cost in reliability and tokens?

5. **What cadence designs are feasible and least annoying: timer, turn count, or event-driven?**
   Compare triggers the harness can actually implement (hook counters, timestamp comparison, PR-affecting tool-call detection, session stop/idle) against the user's "not every message" constraint. Is event-based (on PR create/update + periodic heartbeat) better than pure timer/turn-count?

6. **What prior art exists for surfacing work-in-flight in agent harnesses and CLI tools?**
   Claude Code's own task list and background-job notifications, gh dash-style tooling, other agent frameworks' progress conventions — what patterns are proven for "where's my PR?" recall.
