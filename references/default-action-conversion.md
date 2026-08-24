# Converting a step to `default_action`

A koto template state can declare a command the engine runs itself, on entering
the state, before that state's gates are evaluated. shirabe's templates use it
for mechanical steps so the agent's turns go to judgment instead.

This file is shirabe's policy on when to reach for it. It is not the authoring
guide -- koto ships that, and it is the authority.

## The rule

**Does the command's risk live in a bad success, or only in a bad failure?**

Keep `default_action` off any command whose *successful* exit is itself the
irreversible, externally visible event: creating, publishing, or closing a pull
request, posting a comment, marking a draft ready for review. Allow it for a
command whose only irreversibility is bounded and repairable after a successful
run.

Reversibility has two axes and only the second governs. Not "can the local
artifact be reset" -- usually it can -- but "did this fire an externally visible
event that cannot be un-fired". Closing a pull request undoes its state, not the
notification every watcher already received.

**The reasoning behind this rule lives in koto's
`docs/guides/default-action-authoring.md`**, which is the authoritative
authoring guide: the schema, the failure path, capture semantics, execution
anchoring, and the worked examples on both sides of the line. Read it before
writing an action. It is deliberately not reproduced here -- two copies of one
argument drift, and the guide ships with the engine that implements it.

What follows is what shirabe adds on top, and nothing else.

## Two filters shirabe applies on top of the rule

koto's rule decides whether the engine *may* run a command. These two decide
whether shirabe *should*, and they exist because they are consequences of koto's
response shape rather than properties of the command.

**1. The command must exit non-zero when it fails.** A failing action stops the
tick and hands the agent the command, its exit status, its stdout and stderr, a
typed `failure_kind`, and the state's `fallback` prose. A command that always
exits 0 can never reach that path, so its diagnosis has to come from stdout --
which a *successful* action discards, since output only reaches the agent on
failure or through a capture. Converting such a command makes its failures less
visible than leaving it in prose.

`skills/work-on/references/scripts/extract-context.sh` is the worked case. It
documents `Exit codes: 0 - Always`, and it is why that step is still agent-run.

**2. The command must leave a trace some other command can check.** The state's
gate has to be able to disagree with the action. If the only evidence the step
ran is the step's own exit code, converting it buys automation and sells
assurance, and the only gate available is one that re-runs the action -- which
establishes nothing.

A read can satisfy this: the gate checks that the world is in the state the read
assumes, rather than checking that the read happened.

## Three authoring constraints

**A `fallback` names the evidence, not just the command.** An action-failure
response carries `expects: null`. The agent is told what went wrong and is *not*
told what to submit, so a fallback that stops at "run this yourself" leaves it to
call `koto status` to find out how to get past the state. Name the field and the
value.

**A body longer than one clause goes in a script.**
`scripts/check-template-interpolation.sh` fails any `command:` containing `$NAME`
or `${NAME}`, because it cannot tell an author's mistaken template-variable
reference from a legitimate shell variable -- and that check is what catches a
`$PLAN_SLUG` koto never substitutes, which expands to the empty string and runs
the command against the wrong value. So an inline body cannot hold a local shell
variable at all. Put it in a script under the skill's `scripts/` directory,
where the logic is also testable as a file.

A script that ships in the plugin is reached through a **declared template
variable**, never through `${CLAUDE_PLUGIN_ROOT}`. koto does not resolve shell
variables, and the linter rejects the field. `/execute` declares `PLUGIN_ROOT`
and passes `--var PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT}` at `koto init`, where the
agent's own shell expands it once. A repo-relative path is not the alternative:
it resolves against the execution anchor and therefore only in a checkout of
shirabe itself.

**Every transition out of a converted state names the state's gate.** A state
that auto-advances on success and still lets the agent take over on failure
needs a gate-only edge and evidence-keyed edges together, and koto rejects a
state whose `when` blocks share no fields. Repeating the gate field in every
branch is what makes them mutually exclusive:

```yaml
transitions:
  - target: <next>
    when:
      gates.<gate>.exit_code: 0
  - target: <next>
    when:
      gates.<gate>.exit_code: 1
      status: override
  - target: <blocked>
    when:
      gates.<gate>.exit_code: 1
      status: blocked
```

On the passing path the state advances with no evidence and the agent never sees
it. On the failing path the response carries the gate's exit code and the full
`expects` schema. Keep the `accepts` fields optional -- that is what keeps the
happy path free of them.

## Three things measured against koto 0.12.1 that the guide does not say

Each of these cost a debugging round when the first conversions were written.

**`{{SESSION_NAME}}` is not substituted inside a `default_action` command.**
Filed upstream as [koto#220](https://github.com/tsukumogami/koto/issues/220); the
workaround below is what shirabe does until it lands. A
declared variable in the same string resolves; `{{SESSION_NAME}}` reaches
`sh -c` as the literal token, so a command that passes it to `koto context add`
writes into a session named `{{SESSION_NAME}}` and the state's own gate then
reports the real session's key as absent -- a failure that looks like a broken
gate rather than a broken command. Prose elsewhere in a template uses
`{{SESSION_NAME}}` safely because the agent, not koto, resolves it there.

Rebuild the name from a declared variable instead. `/execute` passes
`"execute-{{PLAN_SLUG}}"`, which is exactly the name its own `koto init` uses,
and which the compiler checks. `$KOTO_TICK_SESSION` is also set in the command's
environment and holds the right value, but the interpolation linter rejects any
`$NAME` in a command field, so it is only reachable from inside a script.

**Do not write a capture's name in braces in the prose of the state that
produces it.** A `{{...}}` reference is substituted wherever it appears,
including in the producing state's own directive and details. On the failure
path the capture does not exist yet, so a braced mention there stops the tick
with `capture_unset` -- and it stops it *instead of* showing the agent the
failure it came to read. Name it without braces in that state; brace it only in
states every path reaches through the producer.

**A `--var` value must satisfy koto's allowlist,
`^[a-zA-Z0-9._/:@ \-]*$`, and a filesystem path need not.** A `+` in a
directory name is legal on disk and outside the pattern, so a plugin root
containing one is refused at `koto init` with a message naming the variable.
The refusal is loud and lands before any work, which is the right failure; it is
worth knowing about because a canonical install under `~/.claude/plugins/cache/`
is clean and a developer's checkout may not be.

## One check before converting anything

**Would the command's output write a secret into the session log?** Every run
appends the command, its exit code, stdout, and stderr to the session event log,
which is committed to feature branches for koto-driven workflows. A command that
prints a token writes it there. This is about what gets written down, not about
who authorized the command, so it applies to commands that pass the rule
cleanly.

## Two more things worth knowing before you write one

**The action re-runs on every entry without evidence** -- each gate-blocked retry
and each lap of a self-loop. Write the command so a second run is harmless:
`mkdir -p`, not `mkdir`.

**A capture is readable only from states every path reaches through its
producer.** Reading one the run never produced is a hard stop with exit 3, not an
empty render. `/work-on` has three entry modes converging at `analysis`, so a
value captured inside one mode's setup state would break every run that took
another mode.

## What is converted today

Read one of these next to your own state; they are the worked examples.

| State | Template | Shape |
|---|---|---|
| `branch_check` | `skills/scope/koto-templates/scope.md` | A read, captured, gated on the world the read describes |
| `settled_branch_record` | `skills/execute/koto-templates/execute.md` | A write, gated by a `context-matches` read-back the action cannot influence |
| `worktree_sync` | `skills/execute/koto-templates/execute.md` | A local mutation, gated on whether the mutation's goal holds |
| `pr_precheck` | `skills/work-on/koto-templates/work-on.md` | A read, captured, gated ahead of the step it feeds |

`docs/designs/DESIGN-koto-default-action-adoption.md` records why each of those
converted, and -- more useful when you are deciding about a new step -- the
thirteen candidates that were examined and stayed with the agent, each with its
reason.
