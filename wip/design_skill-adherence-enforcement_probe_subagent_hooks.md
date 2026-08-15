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
Whether a plugin installed and enabled the normal way behaves differently was
not tested here, and the difference matters to Decision 3's "ships inside the
shirabe plugin" option. Treat this as a caution against assuming plugin-supplied
hooks are live wherever the plugin is present, not as proof they never are.

## Bearing on the decisions

- **Decision 3** can rely on a settings-registered hook reaching subagents. It
  cannot yet rely on a plugin-registered one, and the skill-frontmatter case
  remains untested. The safest reading is that the mechanism niwa already uses
  (settings injection) is the one with evidence behind it.
- **Decision 2** gains its orchestrator-role discriminator: `agent_type` present
  means delegated child, absent means orchestrator.
- **Decision 1** must not assume the session id separates orchestrator work from
  child work. It does not.

## Limits

One run, one harness invocation, one subagent type. The probe shows the fields
are present in this configuration; it does not establish that `agent_type` is
absent for every non-subagent caller in every configuration, and an
implementation should treat the absence test as a positive check on a known
field rather than an open-world assumption.
