# Lead: What does koto's default_action actually do at runtime? (orchestrator probe)

Run by the orchestrator against the **installed** binary, not the source tree:
`koto 0.11.6 (3d9ef1c 2026-08-17T21:44:00Z)` at `~/.tsuku/tools/current/koto`.
Scratch workflows in `$CLAUDE_JOB_DIR/tmp/kototest`, a throwaway git repo on
branch `feature/some-branch`.

## Findings

### P1. `default_action` works, and it auto-advances

Template:

```yaml
states:
  detect:
    default_action:
      command: "git rev-parse --abbrev-ref HEAD"
    gates:
      on_branch: { type: command, command: "true" }
    transitions:
      - target: report
```

`koto next` ran the command and chained straight through to the terminal state.
The capability is live in the shipped binary — this is not a source-tree-only
feature.

### P2. The command's stdout is captured and persisted

Event log (`~/.koto/sessions/<name>/koto-<name>.state.jsonl`):

```json
{
  "seq": 4,
  "type": "default_action_executed",
  "payload": {
    "state": "detect",
    "command": "git rev-parse --abbrev-ref HEAD",
    "exit_code": 0,
    "stdout": "feature/some-branch\n",
    "stderr": ""
  }
}
```

The branch name koto's caller wanted is right there, in koto's own state file.

### P3. On the happy path the agent never sees it

The `koto next` response for the same run:

```json
{"action":"done","advanced":true,"error":null,"expects":null,
 "state":"report","unassigned_children":[]}
```

No `action_output`. No stdout. Nothing referencing the action at all. The value
exists in the event log and dies there.

### P4. There is exactly one way to see action output, and it stops the loop

With `requires_confirmation: true`:

```json
{
  "action": "confirm",
  "action_output": {
    "command": "echo would-create-pr",
    "exit_code": 0,
    "stderr": "",
    "stdout": "would-create-pr\n"
  },
  "advanced": false,
  "directive": "Create the PR.",
  "state": "risky"
}
```

`action_output` is a real field in the response contract — it is simply only
populated on the confirmation stop. So "run a command and hand the agent its
output" is expressible today only by halting the workflow at that state.

### P5. `requires_confirmation` confirms *after* execution, not before

The stdout above (`would-create-pr`) proves the command already ran before the
agent was asked anything. The flag is a post-execution checkpoint, not a
pre-execution guard. The design's safety story — "only reversible actions
auto-execute; irreversible actions require agent confirmation" — does not hold
as implemented: an irreversible action declared with `requires_confirmation`
still executes, and the agent is consulted about a fait accompli.

### P6. A failing action does not stop anything and is not reported

Template with `command: "exit 3"` and a gate of `"true"`:

```json
{"action":"done","advanced":true,"error":null,"state":"done"}
```

The workflow advanced to terminal. The event log recorded `"exit_code": 3`.
The agent was told nothing. **The action's exit code has no effect on control
flow at all** — only the gate decides. The failure path the exploration is
premised on ("koto falls back to instructing the agent when the command fails")
does not exist: koto swallows the failure and moves on unless a gate
independently catches the same condition.

### P7. The realistic fallback case is structurally right but diagnostically blind

Action succeeds, gate on the same state fails — the shape a template would use
for "koto tries, agent takes over":

```json
{
  "action": "gate_blocked",
  "advanced": false,
  "blocking_conditions": [
    {"name":"ok","status":"failed","type":"command",
     "agent_actionable":true,"category":"corrective",
     "output":{"error":"","exit_code":1}}
  ],
  "directive": "Create the branch. If the automated attempt failed, do it by hand.",
  "state": "risky"
}
```

The agent gets the prose and the gate's exit code — but not the action's
stdout, stderr, or exit code. It is told to take over without being shown what
the automated attempt did or why it did not satisfy the gate.

### P8. The action runs in whatever directory `koto next` was invoked from

This is the decisive safety finding, and it corrects a first impression. The
session's `workflow_initialized` event does record
`"template_source_dir": "/home/.../tmp/kototest"`, and a `default_action` of
`pwd > cwd-proof.txt` run from that same directory writes there — which looks
like the workflow root is the base.

It is not. Initializing the workflow in `tmp/kototest` and then running
`koto next action-cwd` from `tmp/elsewhere` wrote `cwd-proof.txt` into
**`tmp/elsewhere`**, containing `/home/.../tmp/elsewhere`. Nothing was written
in `kototest`. Sessions are looked up by flat name under `~/.koto/sessions/`,
so the session carries no binding to the tree it was created in, and the action
inherits the caller's raw cwd.

`working_dir` does not fix this — it is relative to the same caller cwd.
Same workflow, `working_dir: "sub"`, invoked from `tmp/elsewhere`, wrote into
`tmp/elsewhere/sub`, not `tmp/kototest/sub`.

`working_dir: ".."` also escapes upward and writes outside the tree: no
canonicalize-and-contain step exists. An earlier probe with
`working_dir: "../../../../etc"` failed only because the resolved path happened
not to exist, not because anything rejected it.

The user's exact stated fear — "running the command on the wrong folder" — is
not a hypothetical failure mode. It is the default behavior whenever `koto next`
is invoked from anywhere other than the intended tree.

### P9. A non-existent `working_dir` fails silently

`working_dir: "no/such/dir"` produced:

```json
{"exit_code": -1, "stdout": "",
 "stderr": "failed to spawn command: No such file or directory (os error 2)"}
```

in the event log, and a `koto next` response that mentioned none of it. The
"ran the command in the wrong folder" failure mode the user named is not just
possible — its close cousin, "never ran the command at all", is invisible.

### P10. `koto init --var` does reject shell metacharacters

`koto init --help`: "VALUE accepts letters, digits, and `. _ - / : @` plus
spaces; shell metacharacters are rejected." So variable values interpolated
into action and gate commands cannot trivially inject shell syntax. This is a
real, enforced guard — the one found in this probe.

## Implications

- The gap is not "koto cannot run commands". It runs them today, in the shipped
  binary, and shirabe uses that capability nowhere.
- The gap that blocks the motivating example is **output routing**: koto has the
  branch name and no way to give it to the agent or to a later state without
  halting. `action_output` already exists in the response contract, which makes
  the smallest useful change small.
- The gap that blocks the user's stated fallback design is **failure
  propagation**: an action's exit code currently influences nothing. Any
  "fall back to the agent when the command fails" story needs koto to act on
  the exit code, or needs every action paired with a gate that re-checks the
  same condition (which doubles the command count and still hides the reason).
- The guard the user asked about — never run in the wrong folder — is not weak,
  it is absent. The action inherits the caller's cwd, the session is not bound
  to a tree, `working_dir` is relative to that same caller cwd, and a bad
  directory fails invisibly. Any adoption of `default_action` for commands that
  write (branch creation, commits, PR pushes) inherits this exposure directly.

## Surprises

- `requires_confirmation` confirming after the fact inverts what its name and
  its design rationale promise.
- A failing action being a complete no-op for control flow. This is the single
  most consequential finding of the probe.
- `action_output` already being in the response schema. The plumbing is half
  built; only the population rule is narrow.

## Open Questions

- Is the post-execution confirmation deliberate (confirm the *result* before
  advancing) or a defect against the design's stated intent?
- Is there an intended pairing convention — every `default_action` gets a gate
  that verifies it — documented anywhere?
- Would populating `action_output` on every stop (not just `confirm`) break the
  output contract's compatibility guarantees?

## Summary

Against the shipped koto 0.11.6, `default_action` runs commands and persists
their stdout, but the agent only ever sees that output when the action is
declared `requires_confirmation` — which halts auto-advance — and a failing
action changes nothing at all about control flow or the response. The
motivating example is blocked by output routing rather than by execution, and
the user's desired failure-fallback does not exist in any form. The safety
guard the user asked for is absent rather than weak: the action runs in
whatever directory `koto next` happens to be invoked from — proven by
initializing in one tree and running from another — with `working_dir` relative
to that same caller cwd, no containment against `..`, and silent failure when
the directory does not exist.
