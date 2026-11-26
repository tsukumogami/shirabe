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
environment stripped of the harness's own variables. The eight cases were
made like this:

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

Booleans and numbers are kept. Two deviations from a straight copy:

- **Subagent.** The harness never offered the question tool to a subagent:
  not to a background agent, and not to a plugin agent whose definition lists
  it. That case's capture is the subagent's `Bash` call. The fixture keeps
  every field of that input and replaces only `tool_name` and `tool_input`
  with the question tool's.
- **Record path.** A fixture can't be piped into the hook as it stands,
  because `PATH-1` isn't under the harness's directory, so the origin reads
  as unknown. The README shows how to place the record first.

The time spent was within the session timebox.

## Findings

### What each turn start reported

"Entry" means the session record's `user` entry whose `promptId` equals the
hook input's `prompt_id`. The PreToolUse input had the same keys in every
case: `session_id`, `transcript_path`, `cwd`, `scratchpad_dir`, `prompt_id`,
`permission_mode`, `effort`, `hook_event_name`, `tool_name`, `tool_input` and
`tool_use_id`. The subagent's input also had `agent_id` and `agent_type`. The
prompt-submission input had `session_id`, `transcript_path`, `cwd`,
`scratchpad_dir`, `prompt_id`, `permission_mode`, `hook_event_name` and
`prompt`, plus `session_title` for the peer message. Neither input carried a
field naming the turn's origin.

| Turn start | PreToolUse input | Prompt-submission hook | Entry that started the turn | `CLAUDE_CODE_SESSION_ATTENDED` |
|---|---|---|---|---|
| Typed prompt | `prompt_id` matches the entry's `promptId` | fired; `prompt` is the typed text | `turnOrigin: human`, `origin.kind: human`, `promptSource: typed`, `isMeta` absent | `1` |
| Dispatch brief (first prompt) | same keys; `permission_mode` of the background session | fired; `prompt` is the brief | identical to a typed prompt: `turnOrigin: human`, `origin.kind: human`, `promptSource: typed` | `0` |
| Scheduled wake-up | new `prompt_id` | fired; `prompt` is the scheduled prompt's text | `turnOrigin: scheduled`, `promptSource: system`, `isMeta: true`, no `origin` | `1` |
| Background-task notification | new `prompt_id` | fired; `prompt` starts `<task-notification>` | `turnOrigin: task_notification`, `origin: {kind: task-notification, producer: session-task, ...}`, `promptSource: system` | `1` |
| Message from another session | new `prompt_id` | fired; `prompt` starts `<cross-session-message`; `session_title` added | `turnOrigin: peer`, `origin: {kind: peer, from, name, ...}`, `promptSource: system`, `isMeta: true` | `0` (the receiver was a background session) |
| Hook continuation | the person's `prompt_id`, unchanged | did not fire | the person's typed entry, then a second entry with the same `promptId`: `isMeta: true`, `rowSource: hook`, `hookText: true`, no `origin` | `1` |
| Typed slash command | the command's `prompt_id`, after three tool calls and results | fired; `prompt` is the typed command | `turnOrigin: human`, `origin.kind: human`, `promptSource` absent; the expanded command text follows as `isMeta: true`, `rowSource: local`; tool-result rows carry the same `promptId` with no origin fields | `1` |
| Typed slash command with an agent | same `prompt_id` throughout, after the agent's completion notice | fired for the command, and again when the completion notice arrived mid-turn, with the same `prompt_id` | as above; the mid-turn notice appears only as `queue-operation` rows (`enqueue`, `remove`) and adds no origin-bearing entry | `1` |
| Subagent | the parent's `prompt_id` and `transcript_path`; adds `agent_id` and `agent_type` | not applicable | the parent's typed entry | `1` |

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

**The session record tells apart every case except the dispatch brief.**

- The scheduled wake-up, notification and peer message each carry their own
  `turnOrigin`, and two of them also carry an `origin.kind`.
- The hook continuation adds an entry marked `rowSource: hook` to the
  person's turn.
- A typed slash command keeps a typed label through any number of tool calls
  and a mid-turn notice.
- The subagent is identified by `agent_id` in the PreToolUse input itself.
- The dispatch brief's entry can't be told from typed text. That matches the
  design's expectation for a dispatched session's first prompt.

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
   symbolic links are resolved, it must lie under the harness's directory
   and be a regular file. The harness's directory is `CLAUDE_CONFIG_DIR` when
   that's absolute, else `$HOME/.claude`. A path that fails the check is
   never opened, and the origin is unknown.
3. **Classify the turn's entries.** Read the record line by line and take
   each `user` entry whose `promptId` equals `prompt_id`:
   - `rowSource: hook` or `hookText: true` means not typed.
   - `turnOrigin` of `task_notification`, `scheduled` or `peer`, or
     `origin.kind` of `task-notification` or `peer`, means not typed.
   - `turnOrigin: human` means a typed label, but only when `origin.kind` is
     absent or `human`, `promptSource` is absent or `typed`, and `isMeta`
     isn't true.
   - Any other entry with `turnOrigin` or `origin` means unknown.
   - An entry with neither (a tool result, an expanded command) doesn't
     count.
4. **Combine the entries.** Any "not typed" entry decides the turn as not
   typed. Otherwise any "unknown" entry makes the turn unknown. Otherwise a
   typed label stands. A turn with no counting entry is unknown.
5. **Decide.** Not typed denies. A typed label or an unknown origin falls
   back to the run mode: denied when the session is unattended, no decision
   otherwise.

A typed label goes through the fallback because the dispatch brief carries
the same label. In an attended session the two outcomes are the same.

### Where the guard reads whether the session is unattended

The source is `CLAUDE_CODE_SESSION_ATTENDED`, which the harness sets in the
environment of every hook it runs:

- `1` in each interactive session captured.
- `0` in each background session captured. That covers the dispatched one and
  the one that received the peer message.

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
  indistinguishable from typing that prompt, and is allowed.
- **Subagent.** The harness doesn't offer the question tool to a subagent
  today, so the subagent rule can't be seen to fire in a live session. It
  rests on `agent_id`, which the capture shows on a subagent's PreToolUse
  input.
- **Hook continuation.** A continuation denies every question for the rest
  of the person's turn, including one the model would have asked without the
  hook. The continuation's text isn't something the person typed, and the
  record can't separate the two.
- **Labels can change.** The record's origin labels are the harness's own
  and could change in a later version. An unfamiliar label makes the origin
  unknown, which falls back to the run mode rather than denying in an
  attended session. A harness that stopped writing `turnOrigin` and `origin`
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
  set. When a harness version changes the record's labels, recapture the
  affected case the way this report describes and update the fixture, not
  the rule's fallback.
- **Dispatch brief.** The dispatch brief stays a stated limitation for as
  long as its entry carries a typed label. If the harness later labels a
  first prompt passed on the command line, the guard can deny it in an
  attended session too. That needs a new capture and a rule change, not a
  change to the fallback.
