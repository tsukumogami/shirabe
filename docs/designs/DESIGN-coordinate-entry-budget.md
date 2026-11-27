---
schema: design/v1
status: Draft
problem: |
  A coordinator dispatched under niwa's coordinator profile still starts at
  about 61K tokens of context, against a target below 35K. The profile took
  the harness down to about 28K. The rest is the coordinate skill's own
  SKILL.md, which a leading `/shirabe:coordinate` invocation expands in full
  into the first turn: 32.5K tokens, every word of it, whatever the
  coordinator is about to do. No harness item the profile still keeps is
  unused by coordinators, so the gap can only close in what the skill puts
  into turn 0.
---

# DESIGN: Coordinate entry budget

## Status

Draft

## Context and Problem Statement

niwa's coordinator dispatch profile (niwa's
`docs/designs/DESIGN-coordinator-dispatch-profile.md`, shipped in niwa
v0.44.0) trims what a dispatched coordinator starts with: it denies the tools
coordinators never call, leaves out the bundled skills and the account
connectors, and denies the Skill tool, so the skill listing goes too. Because
the Skill tool is denied, the coordinate skill reaches the session as a
leading slash invocation: since #2188, `dispatch-worker.sh` starts a
coordinator's prompt with `/shirabe:coordinate <args>` and passes
`--profile coordinator`.

The milestone this serves, a dispatched coordinator that starts without the
harness content it never uses, has one acceptance check that matters here: a
coordinator dispatched under the profile, its prompt led by that invocation,
reads below 35K tokens at turn 0, and still loads and uses SendMessage, the
Cron tools and TaskStop. Before the profile the figure was 59.2K. A session
dispatched without the profile, and a session the owner starts by hand, must
start as they do today.

The live check in #2188 read 60,907 tokens at turn 0 (input 2, cache
creation 60,905, cache read 0). Everything the profile drops was gone, and
the deferred tools loaded and worked. The figure didn't move because the
leading invocation now brings the whole of `skills/coordinate/SKILL.md` into
the first turn, and that file is 96,425 bytes.

Measured since, on Claude Code 2.1.332 and Opus, in print mode, with the
workspace's coordinator profile passed as `--settings` from a niwa instance
root, each run twice:

| Launch | Turn-0 tokens |
|--------|---------------|
| trivial prompt | 22,144 and 22,104 |
| same, prompt led by `/shirabe:coordinate <roadmap> --role manager` | 54,695 and 54,695 |

The skill's expansion is the difference: 32,551 tokens for 95,846 characters,
about 2.95 characters per token. The four-characters-per-token estimate in
#2188 (about 24K) was low. Taking it off the dispatched figure leaves about
28,356 tokens of harness under `--bg`, which runs about 6.3K above print mode
(the background-session and browser sections of the system prompt, and the
AskUserQuestion and ReadNotifications schemas).

The harness has no unused item left. Each remaining item was measured by
denying it on top of the profile, and the 1,705 coordinator transcripts on the
measuring host were read for calls to it:

| Item | Turn-0 tokens | Coordinator transcripts calling it |
|------|---------------|------------------------------------|
| Agent, with its subagent-type listing | 3,943 | 1,081 of 1,705, across every listed type |
| datadog MCP server | 1,958 | 79 |
| ScheduleWakeup | 1,734 | 6 |
| ListAgents | 665 | 1,128 |

None of these has the never-called evidence the profile's design requires for
a drop, so this design proposes no further harness trim. The arithmetic left
is short: 35,000 less about 28,356 is about 6.6K tokens for the coordinate
skill's turn-0 text and the dispatcher's prompt lines together, against
32.5K today.

The question is how the coordinate skill brings a dispatched start's turn 0
under that line, without moving the same text one turn later and calling it a
saving, and without changing what a coordinator knows when it acts.

## Decision Drivers

- **The target is turn 0, and the point is every turn.** A coordinator tenure
  runs for days and pays its context on every turn. A design that lowers turn
  0 by having the coordinator read the same text on turn 1 meets the letter
  and none of the purpose. Text a start doesn't need must stay out until the
  situation that needs it arises, and text for situations a tenure never meets
  must never load.
- **A coordinator acts on what it was shown.** The contract in SKILL.md holds
  rules a coordinator must follow at the moment a situation arises (a
  takeover, a verdict, a teardown, a bound). Each rule moved out of the entry
  has to reach the coordinator at that moment, through a channel that always
  fires, not through the coordinator remembering to look.
- **Headroom, not a squeak.** The harness grows as plugins and Claude Code
  releases add text. A budget that lands at 34.9K fails at the next release.
  The entry text needs a fixed ceiling with room under the line, and a check
  that fails when the file grows past it.
- **No harness change.** Every remaining harness item is in use. The profile,
  niwa and the workspace config stay as they are.
- **Every start reads the same skill.** A coordinator the owner starts by hand
  and one a dispatcher starts invoke the same `/shirabe:coordinate`, so a
  restructured entry reaches both. The profile's clauses about unprofiled and
  interactive sessions concern the harness, which this design doesn't touch;
  what the skill says has to stay correct for every kind of start.
- **The deferred tools keep working.** SendMessage, the Cron tools, TaskStop
  and background Bash load through ToolSearch today under the profile; nothing
  here may change that.

## Considered Options

Not written yet: a later /design phase replaces this line.

## Decision Outcome

Not written yet: a later /design phase replaces this line.

## Solution Architecture

Not written yet: a later /design phase replaces this line.

## Implementation Approach

Not written yet: a later /design phase replaces this line.

## Security Considerations

Not written yet: a later /design phase replaces this line.

## Consequences

Not written yet: a later /design phase replaces this line.
