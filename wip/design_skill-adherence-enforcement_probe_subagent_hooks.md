# Probe: does PreToolUse fire for a subagent, and what identifies it?

Run live on Claude Code v2.1.233 during `/design` Phase 2, because Decision 3
was blocked on this and it is not answerable by reading the binary.

## Method

A `PreToolUse` hook matching `Write`, whose command appends the raw hook input
JSON to a log and then allows the call. One `claude -p` run instructed to spawn a
general-purpose subagent that writes one file, then write a second file itself.
Both files were written, confirming the scenario executed.

Run twice with the hook registered two different ways.

## Result 1: settings-registered hook — FIRES FOR BOTH

Registered via `--settings <file>` with a `hooks.PreToolUse` block. Two hook
invocations logged, one per write.

**Subagent's write** (`subagent-wrote.txt`):

```
agent_id        = 'a9c0ebeeb7ffd6d51'
agent_type      = 'general-purpose'
session_id      = '0fd0a4c3-50a9-48a5-a6fd-20d78f0623a6'
tool_name       = 'Write'
permission_mode = 'bypassPermissions'
cwd             = '/home/dgazineu/.claude/jobs/4d06ff3a/tmp'
```

**Parent's write** (`parent-wrote.txt`):

```
session_id      = '0fd0a4c3-50a9-48a5-a6fd-20d78f0623a6'
tool_name       = 'Write'
permission_mode = 'bypassPermissions'
cwd             = '/home/dgazineu/.claude/jobs/4d06ff3a/tmp'
```

Three findings follow directly.

**The hook fires for subagent tool calls.** Confirmed, not inferred.

**`agent_id` and `agent_type` are present on the subagent's invocation and
absent entirely on the parent's.** The absence of the fields is the
orchestrator-role signal. This is what makes AC10 satisfiable: a delegated
single-issue session is identifiable by `agent_type`, and the orchestrator by
that field not being there. No comparison against a roster is needed.

**Both invocations carry the same `session_id`.** The parent and its child are
one Claude Code session as far as the session id is concerned. That matters for
Decision 1: the koto workflow record is keyed by session id, so it cannot by
itself distinguish work the orchestrator did from work a child did. The hook
input is the only surface in this probe that separates them.

Also confirmed incidentally: `permission_mode` is reported as
`bypassPermissions` and the hook fired anyway, which is the mode the workspace
runs under.

## Result 2: plugin-registered hook — DID NOT FIRE

The identical hook, identical script, registered instead as
`hooks/hooks.json` inside a throwaway plugin directory loaded with
`--plugin-dir`. Both writes executed and the log file was never created: zero
invocations.

So loading a plugin with `--plugin-dir` does not activate that plugin's hooks.

### Correction: this does NOT generalize to installed plugins

Resolved after the fact, and the resolution reverses the reading above for the
case that matters.

**Plugin-declared hooks do fire when the plugin is installed normally.** The
proof is this session. `superpowers` appears in
`~/.claude/plugins/installed_plugins.json`, its
`hooks/hooks.json` declares exactly one hook:

```json
{"hooks": {"SessionStart": [{"matcher": "startup|clear|compact",
  "hooks": [{"type": "command",
             "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" session-start",
             "shell": "bash", "async": false}]}]}}
```

and that hook fired: the session opened with the injected
`using-superpowers` content it emits.

So the `--plugin-dir` result is a fact about the dev-loading path, not about
plugin hooks. A plugin-declared `PreToolUse` hook in an installed, enabled
shirabe is a supported mechanism, and Decision 3's placement is not undermined
by the probe above.

**I briefed Decision 3 that the plugin route was "directly adverse" on the
strength of the `--plugin-dir` result.** That briefing was wrong, for the same
reason the session-identity briefing was wrong: a probe generalized past the
configuration it measured. Decision 3 chose the plugin route regardless and its
own open question 2 asks for precisely the startup-ordering probe that would
have caught my error. Recording it here so the design's evidence trail does not
carry a refuted claim.

What remains genuinely open from the original probe is narrower: whether plugin
hook registration completes before the first tool call in a `-p` session whose
opening move is a write. The superpowers evidence is a `SessionStart` hook,
which by construction runs at startup and says nothing about `PreToolUse`
ordering against an immediate first write.

## Bearing on the decisions

**Superseded on two points.** Decision 3 subsequently ran the probe through the
supported plugin load path (`claude plugin init` scaffolding, not
`--plugin-dir`) and established more than this probe could. Its results, on the
same version:

- A plugin-registered `PreToolUse` hook fires, which the superpowers evidence
  above could not show because that is a `SessionStart` hook.
- It fires on the session's **first** tool call, against a prompt whose opening
  move was a write. This closes the startup-ordering question this probe left
  open.
- It fires inside a subagent and on the main thread, reproducing the
  field-presence finding through the plugin route.
- It **denies** under permission-bypassing mode, and the deny reason returns to
  the model as tool-error text verbatim, in both the subagent and the parent.
  That is the correction mechanism the requirements depend on, observed rather
  than assumed.

So the corrected reading is: **plugin and settings placement are equivalent on
mechanism**, and the choice rests on distribution and lifetime rather than on
whether the hook fires.

- **Decision 3** can rely on the plugin route. The paragraph this section
  originally carried, saying it could not, is the claim my briefing to that
  decision was based on, and it was wrong.
- **Decision 1** must not assume the session id separates orchestrator work from
  child work in the Agent-tool case. Correct, and see the session-identity probe
  for where it does separate.

## Limits, and one inference to discard

One run, one harness invocation, one subagent type.

**The orchestrator-role inference drawn from this probe is wrong and should not
be used.** I read "absent `agent_type`" as meaning orchestrator. The measurement
is sound; the inference is not. Absence means only *not a Task subagent of this
process*. If plan execution delegates through separately dispatched sessions or
per-repository worktrees, every delegated child is a main thread with no
`agent_type`, and the permitted-write criterion for delegated children fails on
every delegated write.

Both the arming decision and the placement decision reached this objection
independently and declined the framing. The role test the design carries is the
one keyed on the unit of work named in the session's own inbound brief, which
holds under every dispatch shape. Field presence is used only to select which
transcript to read.
