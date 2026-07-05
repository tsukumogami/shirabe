---
schema: brief/v1
status: Done
problem: |
  Long agent sessions open multiple PRs, often across several repos, and the
  links scroll out of reach. Native affordances don't recover them: the footer
  badge tracks only the current branch, prompt-history search never sees
  assistant output, and session recaps carry no structured links.
outcome: |
  At any moment in a session — after a PR event, on returning from a break, on
  demand, or reading a finished background worker's transcript — the user finds
  one recognizable, searchable block listing every PR the session touched, with
  state, CI status, and a clickable link.
motivating_context: |
  A four-round exploration compared instruction-only, hook-nudged, deterministic,
  and display-only architectures, prototyped the deterministic pipeline, and
  validated every mechanical assumption against Claude Code 2.1.201. This brief
  persists the framing that exploration settled so the downstream PRD inherits
  a confirmed problem shape rather than a hypothesis.
---

# BRIEF: Session Work Summary

## Status

Done

The framing below was settled by a completed exploration; the downstream PRD
owns requirements articulation, and the design records the validated
architecture.

## Problem Statement

A working session with an AI coding agent routinely produces several pull
requests — sometimes in one repository, sometimes spread across a multi-repo
workspace. Each PR's link appears once in the conversation, at the moment of
creation, and then scrolls away. When the user needs it again — to review, to
share, to check CI — they dig through the transcript by eye.

The harness's own affordances don't close the gap. The footer PR badge tracks
only the current branch's PR and disappears on merge, so a session that moved
on to its third branch shows nothing about the first two. Reverse-search
(Ctrl+R) searches the user's own prompts, never the assistant's output, so a
link the agent printed is unfindable by search. Session recaps summarize
without structured links. And for dispatched background workers there is no
live footer at all — the only record is whatever the worker chose to write in
its transcript.

The result: the more productive a session is, the harder it becomes to answer
"what's in flight right now, and where is it?"

## User Outcome

A user in a long session always has a cheap way to re-orient. When the PR set
changes — a PR opens, merges, or its CI flips — a compact, consistently
formatted block appears in the conversation listing every PR the session has
touched: state, CI status, title, and a full clickable URL on every line, every
time. When the user steps away and comes back, the first exchange refreshes the
same block unprompted. When they want it on demand, one command regenerates it
fresh. When a background worker finishes, the same block closes its final
message, so the session dashboard and transcript carry the links.

Because the block always opens with the same marker line, the user can also
find the most recent one by searching terminal scrollback — the block is a
stable landmark in an otherwise scrolling transcript, not another one-off
message shape.

## User Journeys

### The multi-PR afternoon

A developer drives an implementation plan through a single interactive session:
three PRs opened across two repos over several hours. Each time a PR is created
or CI completes, the summary block appears at the end of that exchange —
current state of all three PRs, links included. The developer never asks for
it; the trigger is the event itself. Mid-afternoon they click the CI-failing
PR's URL straight from the latest block instead of scrolling back to find where
it was first mentioned.

### Returning after a break

The same developer steps away for an hour-long meeting. On their first prompt
back — which is about something else entirely — the session leads with a
refreshed block: one PR merged while they were away, one still awaiting review.
Re-orientation costs one glance, and their actual question is answered next,
uncontaminated by stale context.

### Finding a link from an hour ago

A user remembers the session opened a PR "a while back" but the conversation
has moved on. They search the terminal scrollback for the block's fixed marker
text and land on the most recent summary — the link is on the line below,
intact and clickable, because the block's format guarantees a bare URL at the
end of every entry.

### Checking on a dispatched worker

A user hands work to a background session and checks in later through the agent
dashboard. The worker's final message ends with the same summary block, so the
result view shows exactly which PRs it opened and where they stand — without
the user attaching, scrolling, or asking. The block reads identically to the
interactive one; there is one format to learn.

### Asking for status on demand

Between events, a user simply wants the current picture. They invoke the status
command and get the same block, regenerated fresh from live PR state rather
than replayed from memory — merged PRs show merged, CI state is current, and a
freshness line says when it was computed.

## Scope Boundary

### In scope

- A standardized summary block: a fixed marker line plus one line per work
  item carrying repo, PR number, state, CI/review status, truncated title, and
  a bare URL — identical in shape wherever it appears.
- Mechanical capture of PR identity at creation time, so the block does not
  depend on the agent remembering what it opened.
- Event-gated appearance: the block shows when the PR set or its status
  actually changes, plus a refresh on the first exchange after a long absence
  — never as a per-message footer and never on a blind timer.
- Keeping the agent itself aware of the current PR set (including after
  context compaction), so conversational answers about in-flight work are
  grounded.
- An on-demand status command that regenerates the same block from live data.
- Coverage for dispatched/background workers via a final-message requirement.
- Multi-repo workspaces: entries carry repo identity, and collection respects
  per-repo visibility boundaries.

### Out of scope

- Changes to Claude Code itself. The feature consumes existing extension
  points; anything requiring harness modification (e.g. the session-list PR
  column's data source) is explicitly not assumed.
- Timed or turn-count digests. Both were evaluated and rejected; nothing in
  this feature emits on a schedule detached from state changes or user return.
- Shipping always-on display channels that live in user-level settings
  (statusline scripts, footer link badges). The feature may document them as
  optional companions, but they are not deliverables and nothing depends on
  them.
- Team-facing notification fan-out (chat digests, email). This is a
  single-user, in-session affordance.
- Fixing the workspace tooling bug where a hook registered through both
  declared config and auto-discovery loses its matcher. That fix is a
  prerequisite tracked as its own work item, not part of this feature.
- Summarizing work items that never touch a PR (ad-hoc file edits, analysis
  sessions). Pre-PR branches appear only once pushed for tracked work.

## References

- references/coordination-strategy.md — the PR Index line grammar the block
  format extends, and the live-refresh precedent (state recomputed from gh,
  never from body text).
- references/issues-table.md — the existing shirabe convention for
  standardized link-bearing status tables in committed documents.
