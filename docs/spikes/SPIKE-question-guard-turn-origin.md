---
status: Complete
question: |
  Can a PreToolUse hook on the question tool (AskUserQuestion) tell a turn
  a person typed from a turn no person typed, using only what the harness
  gives a hook, and can it tell whether the session is unattended, without
  any change outside shirabe?
timebox: "1 session"
---

# SPIKE: Question guard turn origin

## Status

Complete

## Question

Can a PreToolUse hook on the question tool (`AskUserQuestion`) tell a turn a
person typed from a turn no person typed, using only what the harness gives a
hook, and can it tell whether the session is unattended, without any change
outside shirabe?

## Context

PRD-decision-escalation-ladder R27 says a question prompt can't open in a turn
the person didn't start, that a turn whose origin can't be established is
refused when the session is unattended and allowed otherwise, and that a
prompt a skill opens in a turn the person started behaves as it does today.
The design names two places the origin could come from:

- **A mark.** A prompt-submission hook (`UserPromptSubmit`) writes the turn's
  origin somewhere the PreToolUse hook reads it.
- **The session record.** The PreToolUse hook's input names the session
  record (`transcript_path`), and the guard reads the turn's origin from the
  entry that started the turn.

Under either source, the design's security constraint applies: the origin
comes only from structured fields, never from message text. The record is
opened only at the path the harness named, read-only, after checking that
the path lies under the harness's own directory with symbolic links resolved.

The guard's rule can't be written until it's known what each source actually
reports for each way a turn starts. This spike captures that.

## Approach

Every row below comes from a real session on Claude Code 2.1.332. Nothing in
it is inferred from documentation. The sessions ran the smallest model
available, in a scratch directory holding no repository.

A throwaway plugin, loaded with `claude --plugin-dir <dir>`, declared three
hooks:

- On `PreToolUse` for `AskUserQuestion`, it saved standard input, a few
  environment values (`CLAUDE_CODE_SESSION_ATTENDED`,
  `CLAUDE_CODE_ENTRYPOINT`) and a copy of the session record. It then printed
  a deny, so no session blocked waiting for an answer.
- On `UserPromptSubmit`, it saved standard input and the same environment
  values.
- On `PreToolUse` for `Bash`, it saved the same, so a subagent's call could be
  captured.

Interactive sessions were driven through a pseudo-terminal, with the parent
environment stripped of the harness's own variables, and background sessions
were attached to the same way. The cases were made like this:

| Turn start | How the capture was made |
|---|---|
| Typed prompt | Typed a prompt asking for a two-option question. |
| Dispatch brief | Started a background session with `claude --bg -- <prompt>`, the prompt asking for a question. |
| Scheduled wake-up | In an interactive session, scheduled a one-shot wake-up (`CronCreate`) whose prompt asks for a question, then waited for it to fire. |
| Background-task notification | Had the session start a background shell command that finishes after the turn ends, with an instruction to ask a question when it does. |
| Message from another session | From a second local session, sent a message (`SendMessage`) to a background session asking it to ask a question. |
| Hook continuation | Added a `Stop` hook that blocks once with a reason asking for a question. Typed a prompt that needs no question. |
| Typed slash command | Typed a plugin command that runs `pwd`, `date` and `ls` and then asks a question. A second variant also starts an agent, waits for its completion notice, runs two more commands, then asks. |
| Subagent | Typed a prompt that starts a plugin agent whose definition lists the question tool, telling it to ask. |
| Person typing a later turn into a dispatched session | Started a background session with a brief that needs no question, then attached to it (`claude attach <id>`) and typed a prompt asking for one. |
| Typed plugin command in a later turn | Attached to the same session and typed a plugin command that asks three questions with a shell command between each. The capture hook's deny told it to go on to the next step. |
| Command-line prompt to an existing background session | Ran `claude --bg --resume <id> "<prompt>"` against that session, the prompt asking for a question, once with no other flags (the session continued under its own id) and once with flags (the harness started a copy). |
| Respawn | Ran `claude respawn <id>` on that session, then attached and typed a prompt asking for a question. |
| Print mode | Ran `claude -p <prompt>`, the prompt asking for a question or, when the tool wasn't there, for a shell command. |

The fixtures under `hooks/testdata/question-guard/` were generated from these
captures. Every key is kept, along with its nesting, and with string values
handled as follows:

- **Enumerations the rule or this table reads keep their value.** These are
  `type`, `tool_name`, `hook_event_name`, `permission_mode`, `kind`,
  `producer`, `promptSource`, `turnOrigin`, `rowSource`, `userType`,
  `entrypoint`, `role`, `operation`, `level`, `mode`, `permissionMode`,
  `stop_reason`, `fromMode`, and a tool call's `name`.
- **Every other string becomes a marker.** That covers prompt and message
  text, question and option text, paths, identifiers and tool output. The
  marker is `<P>-ID-<n>` for identifiers and `<P>-TEXT-<n>` for text, where
  `<P>` is the fixture's prefix (`TYPED`, `NOTIFY`, and so on).
- **Markers are consistent within a fixture.** The same input string always
  maps to the same marker, so `promptId`, `parentUuid` and `tool_use_id`
  still link up.
- **The record path is `PATH-1`.** The input's `transcript_path` value is
  that marker, and the tests point it at the fixture's record.

Each case has three files:

- `<case>.json`: the PreToolUse input.
- `<case>.record.jsonl`: the session record's `user`, `assistant` and
  `queue-operation` rows, in order. The harness's other row types
  (attachments, API request rows, snapshots, ownership rows) were dropped.
- `<case>.prompt-submit.jsonl`: the prompt-submission inputs for the turn.

The three-question command has one input per question
(`later-skill-three-prompts-<n>.json`) and the record as it stood at the
third.

Booleans are kept. Numbers are kept only for `turnPosition`'s `promptIndex`
and `turnIndex`; every other number (token counts, timestamps, durations, a
process id) becomes 0. An object key that is itself an identifier, such as a
tool-call id used as a key, becomes a marker like any other identifier. Two
deviations from a straight copy:

- **Subagent and print mode.** The harness never offered the question tool
  to a subagent (not to a background agent, and not to a plugin agent whose
  definition lists it), nor to a print-mode session. Those cases' captures
  are a `Bash` call. Each fixture keeps every field of that input and
  replaces only `tool_name` and `tool_input` with the question tool's.
- **Record path.** A fixture can't be piped into the hook as it stands,
  because `PATH-1` isn't under the harness's session records, so the origin reads
  as unknown. The README shows how to place the record first.

The time spent was within the session timebox.

## Findings

### What each turn start reported

"Entry" means a session record `user` entry that belongs to the turn the hook
input's `prompt_id` names. An entry belongs to the turn when its
`turnPromptId` equals `prompt_id`, or, for an entry with no `turnPromptId`,
when its `promptId` does. In every capture but the copy the two fields always
held the same value. They differ in a copied session (see below). The
PreToolUse input had the same keys in every case: `session_id`,
`transcript_path`, `cwd`, `scratchpad_dir`, `prompt_id`, `permission_mode`,
`effort`, `hook_event_name`, `tool_name`, `tool_input` and `tool_use_id`. The
subagent's input also had `agent_id` and `agent_type`. The prompt-submission
input had `session_id`, `transcript_path`, `cwd`, `scratchpad_dir`,
`prompt_id`, `permission_mode`, `hook_event_name` and `prompt`, plus
`session_title` in a named background session. Neither input carried a field
naming the turn's origin.

Every entry that starts a turn also carries
`turnPosition: {promptIndex, turnIndex}`. `turnIndex` counts the session's
turns from 1, whatever started them. `promptIndex` counts only prompts
labelled `human`, and is 0 for a print-mode turn.

| Turn start | PreToolUse input | Prompt-submission hook | Entry that started the turn | `turnIndex` | `CLAUDE_CODE_SESSION_ATTENDED` |
|---|---|---|---|---|---|
| Typed prompt | `prompt_id` matches the entry | fired; `prompt` is the typed text | `turnOrigin: human`, `origin.kind: human`, `promptSource: typed`, `isMeta` absent | 1 | `1` |
| Dispatch brief (first prompt) | same keys | fired; `prompt` is the brief | identical to a typed prompt | 1 | `0` |
| Person typing a later turn into a dispatched session, after attaching to it | new `prompt_id` | fired; `prompt` is the typed text | identical to a typed prompt | 2 | `0` |
| Typed plugin command in that later turn, asking three questions with a shell command between each | one `prompt_id` for all three calls | fired once | `turnOrigin: human`, `origin.kind: human`, `promptSource` absent | 5 | `0` |
| Command-line prompt to an existing background session (`claude --bg --resume <id> "<prompt>"`) | new `prompt_id` | fired; `prompt` is the command-line text | identical to a typed prompt | 4 | `0` |
| The same, when the harness starts a copy of the session instead | new `prompt_id` | fired | identical to a typed prompt. The copy's record restates the earlier turns' entries with the new `promptId`, keeping each turn's own id in `turnPromptId` | 3 | `0` |
| Respawn of a background session (`claude respawn <id>`) | no call | did not fire | no entry added; a person's next typed turn continued the count | 3 (next turn) | `0` |
| Print mode (`claude -p <prompt>`) | the question tool isn't offered; captured on a `Bash` call | fired | `turnOrigin: sdk`, `promptSource: sdk`, no `origin`; `entrypoint: sdk-cli` | 1 (`promptIndex` 0) | `0` |
| Scheduled wake-up | new `prompt_id` | fired; `prompt` is the scheduled text | `turnOrigin: scheduled`, `promptSource: system`, `isMeta: true`, no `origin` | 2 | `1` |
| Background-task notification | new `prompt_id` | fired; `prompt` starts `<task-notification>` | `turnOrigin: task_notification`, `origin: {kind: task-notification, producer: session-task, ...}`, `promptSource: system` | 2 | `1` |
| Message from another session | new `prompt_id` | fired; `prompt` starts `<cross-session-message` | `turnOrigin: peer`, `origin: {kind: peer, from, name, ...}`, `promptSource: system`, `isMeta: true` | 2 | `0` (the receiver was a background session) |
| Hook continuation | the person's `prompt_id`, unchanged | did not fire | the person's typed entry, then a second entry in the same turn: `isMeta: true`, `rowSource: hook`, `hookText: true`, no `origin` | 1 | `1` |
| Typed slash command | the command's `prompt_id`, after three tool calls and results | fired; `prompt` is the typed command | `turnOrigin: human`, `origin.kind: human`, `promptSource` absent; the expanded command text follows as `isMeta: true`, `rowSource: local`, with no origin fields | 1 | `1` |
| Typed slash command with an agent | same `prompt_id` throughout, after the agent's completion notice | fired for the command, and again when the completion notice arrived mid-turn, with the same `prompt_id` | as above; the mid-turn notice appears only as `queue-operation` rows and adds no origin-bearing entry | 1 | `1` |
| Subagent | the parent's `prompt_id` and `transcript_path`; adds `agent_id` and `agent_type` | not applicable | the parent's typed entry | 1 | `1` |

Three more facts came from a count of origin-field values over the session
records already on the capture host. Only field values were counted, no
message text:

- **`turnOrigin: system`.** It carries `promptSource: system` and
  `isMeta: true` and no `origin`. Every such turn was a notice the harness
  itself delivered, such as a notice that another session went idle. No test
  session produced one on demand, so there is no fixture for it.
- **More typed sources.** A `human` turn also carries `promptSource: queued`
  (typed while a turn was running) or `promptSource: suggestion_accepted` (a
  suggested prompt the person accepted).
- **Compaction.** After a compaction the record gains a summary entry for
  the turn in progress. It has the turn's own `promptId` and
  `turnPromptId`, `isCompactSummary: true`, the turn's `turnOrigin` and no
  `promptSource`. Its `turnPosition` was sometimes 1 whatever the turn's
  real position.

### Which source tells which case apart

**The mark can't tell any case apart from structured fields.** The
prompt-submission input has no origin field. Its only signal is the `prompt`
text, where a notification and a peer message start with a tag. Reading that
text is what the design rules out, and a person can type the same tag. On top
of that:

- The hook didn't fire for the hook continuation, which keeps the person's
  `prompt_id`. A mark keyed by `prompt_id` would still say "typed".
- A scheduled wake-up's `prompt` is just the scheduled text.
- A subagent's call never passes through it.

**The run mode doesn't say whether a person is present.**
`CLAUDE_CODE_SESSION_ATTENDED` was `0` in every background session, for its
whole life, including the turns a person typed after attaching. A rule that
denied typed turns whenever the session was unattended would refuse every
prompt to a person working in a background session.

**The session record tells apart every case but two.**

- The scheduled wake-up, notification, peer message and harness notice each
  carry their own `turnOrigin`, and two of them also carry an `origin.kind`.
- The hook continuation adds an entry marked `rowSource: hook` to the
  person's turn.
- A typed slash command keeps a typed label through any number of tool calls
  and a mid-turn notice.
- The subagent is identified by `agent_id` in the PreToolUse input itself.
- A typed later turn is told from a dispatch brief by position: a dispatch
  brief is always the session's first turn (`turnIndex` 1).
- A copy's opening prompt is recognisable, because the copy restates the
  earlier turns' entries with its `promptId`.
- **The dispatch brief** can't be told from a person's typed first prompt.
  That matches the design's expectation for a dispatched session's first
  prompt.
- **A command-line prompt to an existing background session** can't be told
  from a person's typed later turn. Its entry, its position and both hook
  inputs match field for field. This is a later typed-labelled turn that
  arrives with nobody at the session's terminal, whether a person or a
  script ran the command.

The design also expected a scheduled wake-up to carry the same label as typed
text. The capture corrects that: the wake-up carries `turnOrigin: scheduled`.

**The guard uses the session record.** At PreToolUse time the record already
holds the turn's `user` entries, though not yet the `assistant` row holding
the call being decided. The rule reads only the turn's `user` entries, so
that's enough.

### The rule

The guard decides only for `tool_name: AskUserQuestion`. Other input, and
input that isn't JSON, gets no decision.

1. **Subagent.** A non-empty `agent_id` denies.
2. **Check the record path.** `transcript_path` must be absolute. Once
   symbolic links are resolved, it must be a regular `.jsonl` file under the
   harness's session records, `<harness dir>/projects/`. The harness's
   directory is `CLAUDE_CONFIG_DIR` when that's absolute, else
   `$HOME/.claude`. A path that fails the check is never opened, and the
   origin is unknown.
3. **Read the turn's entries.** Read the record line by line, buffering no
   line longer than 4 MiB. A longer line that names the turn leaves the
   origin unknown. Take each `user` entry that belongs to the turn, skipping
   compaction summaries, and classify it:
   - `rowSource: hook` or `hookText: true` means not typed.
   - `turnOrigin` of `task_notification`, `scheduled`, `peer` or `system`,
     `origin.kind` of `task-notification` or `peer`, `promptSource: system`,
     or `isMeta: true` means not typed.
   - `turnOrigin: human` means a typed label, but only when `origin.kind` is
     absent or `human` and `promptSource` is absent, `typed`, `queued` or
     `suggestion_accepted`.
   - Any other entry with `turnOrigin` or `origin` means unknown. That
     includes `sdk`.
   - An entry with neither (a tool result, an expanded command) doesn't
     count.
4. **Combine the entries.** Any "not typed" entry decides the turn as not
   typed. Otherwise any "unknown" entry makes the turn unknown. Otherwise a
   typed label stands. A turn with no counting entry is unknown.
5. **Place the turn.** The turn is an opening turn when any of these holds:
   - one of its entries has `turnIndex` 1;
   - none of them records a position;
   - an entry of another turn carries the turn's `promptId`, which is how a
     copy restates its history for the prompt that started it.
6. **Decide.**
   - Not typed denies.
   - A typed label on a turn that isn't an opening turn gets no decision, in
     any run mode.
   - A typed opening turn, and an unknown origin, fall back to the run mode:
     denied when the session is unattended, no decision otherwise.

### Where the guard reads whether the session is unattended

The source is `CLAUDE_CODE_SESSION_ATTENDED`, which the harness sets in the
environment of every hook it runs:

- `1` in each interactive session captured.
- `0` in each background and print-mode session captured. That covers the
  dispatched one, the one that received the peer message, and the turns a
  person typed into a background session after attaching to it.

So the variable says what kind of session this is, not whether anyone is
watching. The rule uses it only for the turns the record can't place.

A session no workflow drives gets the variable all the same, since the
harness sets it, not the workflow engine. koto's own hook reads the same
variable to record a session's run mode, and records `unknown` when it's
absent. So the guard and the workflow engine agree on the run mode, and koto
needs no change. With the variable unset or holding any other value, the
session isn't known to be unattended, and the fallback allows.

The skills' non-interactive mode (`--auto`, or an `## Execution Mode:` header
in `CLAUDE.md`) is a property of a skill invocation, not of the session. A
hook can't read it. An attended session running a skill in non-interactive
mode is treated as attended.

### Stated limitations

- **Dispatch brief.** A dispatched session's first prompt can't be told from
  a typed one, so it follows the run mode. It's denied only because a
  dispatched session is unattended (`0`). An attended session started with a
  prompt on the command line (`claude -- <prompt>`, not `--bg`) is
  indistinguishable from typing that prompt, and is allowed. A person who
  starts a background session with their own prompt is denied in that first
  turn, and in no later one.
- **Command-line prompt to an existing background session.** It carries the
  same fields as a person's later turn and is allowed, though nobody may be
  watching the session when its question opens. Denying it would deny every
  person who attaches to a background session and types.
- **Hook continuation.** Once a Stop hook has blocked a stop, every question
  for the rest of the person's turn is denied, including one the model would
  have asked without the hook. The continuation shares the person's turn, and
  `hookText: true` alone on an entry of the turn is enough to deny. The
  continuation's text isn't something the person typed, and the record can't
  separate the two.
- **Harness notices and print mode.** No test session produced a
  `turnOrigin: system` turn on demand. The rule denies it from the field
  values seen on the capture host, and the unit tests cover it. A print-mode
  turn (`sdk`) is unknown and follows the run mode. Print mode doesn't offer
  the question tool, and a program driving the harness may be relaying a
  person's text.
- **Subagent.** The harness doesn't offer the question tool to a subagent
  today, so the subagent rule can't be seen to fire in a live session. It
  rests on `agent_id`, which the capture shows on a subagent's PreToolUse
  input.
- **Labels can change.** The record's origin labels and `turnPosition` are
  the harness's own and could change in a later version. An unfamiliar label
  makes the origin unknown. A missing position makes the turn an opening
  turn. Both fall back to the run mode rather than denying in an attended
  session. A harness that stopped writing `turnOrigin` and `origin`
  altogether would leave every turn unknown. That would still deny in an
  unattended session and allow in an attended one.
- **Cost.** The record is read from the start on each question-tool call.
  Lines that don't contain the turn's `prompt_id` are skipped without
  parsing. A 20 MB record decides within the suite's 2-second bound.
- **No binary.** Without the `shirabe` binary the shell entry can't read
  either source, so it gives no decision (see the README). The shell entry
  can read the run mode itself, since it's an environment variable. But it
  would still need the record's origin, so the run mode alone doesn't let it
  decide.

## Recommendation

Go. Build the guard on the session record and `CLAUDE_CODE_SESSION_ATTENDED`,
with the rule above. Nothing outside shirabe has to change.

Conditions:

- **Fixtures as regression set.** Keep the fixtures as the guard's regression
  set. When a harness version changes the record's labels or positions,
  recapture the affected case the way this report describes and update the
  fixture, not the rule's fallback.
- **The two cases the record can't tell apart.** The dispatch brief and the
  command-line prompt to an existing background session stay stated
  limitations for as long as their entries carry a typed label. If the
  harness later labels a prompt passed on the command line, the guard can
  deny both. That needs a new capture and a rule change, not a change to the
  fallback.
