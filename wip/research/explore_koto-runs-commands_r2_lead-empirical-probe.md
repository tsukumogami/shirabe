# Lead: What breaks when koto runs a command? (round 2 orchestrator probe)

Round 1 established what `default_action` does. This probe started by testing
the workaround several round-1 findings assumed was available — having an action
pipe its result into `koto context add`, or having an action perform koto's retry
bookkeeping directly — and ended up finding a defect underneath it that affects
gates in shirabe's production templates today.

Same setup as the round 1 probe: shipped `koto 0.11.6`, scratch workflows under
`$CLAUDE_JOB_DIR/tmp`.

## Findings

### P11. Any command that writes more than ~64KB deadlocks and loses everything

This is the headline. Four actions, each running nothing but `tr` against
`/dev/zero`, differing only in output size:

| action command | result |
|---|---|
| `head -c 60000 /dev/zero \| tr "\0" "a"` | exit 0, 60000 bytes of stdout captured |
| `head -c 70000 /dev/zero \| tr "\0" "a"` | **timed out after 30 seconds**, exit -1, stdout empty |
| `head -c 200000 /dev/zero \| tr "\0" "a"` | timed out after 30 seconds, exit -1, stdout empty |
| `head -c 200000 /dev/zero \| tr "\0" "b" >&2` | timed out after 30 seconds, exit -1, stdout empty |

The threshold sits at the 64KB pipe buffer, and stderr triggers it as readily as
stdout. The cause is visible in `src/action.rs`: the child is spawned with piped
stdout and stderr, then `child.wait_timeout(timeout)` is called, and only after
it returns are the pipes read. A child that fills the buffer blocks writing,
the parent blocks waiting, and the timeout is the only thing that breaks the
tie — at which point the process group is killed and the output is gone. The
64KB truncation the design intended is applied after a read that never happens.

The failure presents as a slow command, not as a structural bug: exit code -1,
`"command timed out after 30 seconds"`, and — per round 1 — nothing about any of
it in the `koto next` response.

### P12. Gates have the same defect, and shirabe's templates are exposed today

`run_shell_command` is shared by gate evaluation. A gate declared as
`head -c 200000 /dev/zero | tr "\0" "a"; true` — a command that exits 0 — took
30.2 seconds and reported:

```json
{"name":"noisy","status":"timed_out","type":"command",
 "output":{"error":"timed_out","exit_code":-1}}
```

A passing check reported as a failure, after a 30-second stall. This is not
hypothetical for shirabe: `/work-on` declares
`tests_passing: [ ! -f go.mod ] || go test ./...` (`work-on.md:439-441`), and
`go test ./...` on any repository with a meaningful number of packages emits far
more than 64KB. The same exposure applies to any future gate wrapping a build,
a linter, or a verbose CI query. This bug is live in production templates and is
independent of whether anyone ever adopts `default_action`.

**Severity refinement** (from the `r2-map-work-on` lead, recorded here next to
the mechanism): `run_shell_command` captures only the top-level `sh -c`
process's pipes, so a command wrapped in `$(...)` has its output consumed by the
shell internally and never reaches the buffer. That shields most existing gates.
Of the eight in `/work-on`, only `tests_passing` is a clear exposure — and it is
the worst case, because Go dumps full per-subtest output on failure, so the gate
breaks on exactly the run where the real output matters. `staleness_fresh` is
unverified (`check-staleness.sh` is not in shirabe's tree). `ci_passing`
collapses through `--jq` and `grep -q` before the top-level capture. The three
branch checks and `has_commits` are negligible — `has_commits` looks risky
(`git log | wc -l`) but sits entirely inside a `$(...)` substitution.

### P12a. Nested `koto next` corrupts the outer invocation's view (found by the r2-map-work-on lead)

Separate from the pipe problem and not fixed by redirecting output. A nested
`koto next --with-data` run inside an action performs a real transition and
genuinely advances its session to terminal. The outer `koto next` that spawned
it then returns `{"state":"s","advanced":false,"action":"evidence_required"}` —
reporting the workflow still waiting in its original state while the session has
already ended. A follow-up `koto status` reports the session as not found. So
nested `koto next` remains unsafe on its own merits even with clean output;
nested `koto context` reads and writes do not share this defect.

### P13. Nested koto calls hang for this reason, not because of a lock

The first version of this probe concluded that koto could not call itself from
inside an action, and attributed it to a workspace-scoped lock. That conclusion
was wrong and is corrected here.

Measured stderr volume per koto invocation in this workspace:

| command | stderr bytes | stdout bytes |
|---|---|---|
| `koto workflows` | 108,783 | 35,459 |
| `koto status <session>` | 108,783 | 279 |
| `koto context list <session>` | 108,783 | 31 |
| `koto version` | 0 | 43 |

Every session-touching koto command emits about 106KB of
`koto: migration skipped <name>: session already exists` warnings — one line per
session, and this workspace has roughly 1,250 of them. That is comfortably over
the 64KB buffer, so every one of them deadlocks inside an action while
`koto version`, which emits nothing, runs in 0.06 seconds.

Redirecting the nested command's output to files proves it: an action running
`timeout 5 koto workflows > /tmp/kw.out 2>/tmp/kw.err` completed with `rc=0` and
the expected JSON in the file. There is no lock. There is a pipe.

Two separate problems are stacked here, and both are worth naming:

1. `run_shell_command` deadlocking above 64KB, which affects every command.
2. koto emitting six figures of migration warnings on stderr for every
   session-touching command, which is what pushes koto itself over the line.
   That volume is its own defect regardless of the deadlock.

### P14. What this means for the workarounds

With output redirected or bounded, a nested `koto context add` inside an action
does work. So the earlier blanket claim — that piping an action's output into
the context store is impossible, that the eight retry-clearing blocks can never
be actions, and that `extract-context.sh` is disqualified — overstated the case.

The accurate statement is narrower and still unfavorable:

- Nested koto calls work only when their output stays under the buffer, which
  in this workspace means never, unless the template author redirects stderr in
  the action's command string. Depending on a template author remembering
  `2>/dev/null` to avoid a 30-second deadlock is not a mechanism to build on.
- `extract-context.sh` calls `koto context add` at line 92. Wrapped in a
  `default_action` in a workspace like this one, it stalls and fails, and the
  `context_artifact` gate blocks. It is not the free conversion round 1 called
  it, though it becomes one if koto's warning volume is fixed.
- `run-cascade.sh` contains no koto calls, so it is unaffected by the nested
  problem — but it is a long, verbose script, which puts it squarely in range of
  the 64KB limit on its own.

### P15. The three-path pattern works today, end to end — with one correction to the proposed YAML

The template-patterns lead argued the target design is reachable with zero koto
changes. Verified, in a scratch git repo, against the shipped binary — with one
compiler constraint that lead's example missed.

**The proposed YAML does not compile.** A state with one transition keyed on
`gates.<gate>.exit_code` and another keyed on `status: override` is rejected:

```
validation error: state "create_branch": transitions to "analysis" and "analysis"
are not mutually exclusive: transitions share no fields, so both could match the
same evidence
```

Renaming the second target does not help — the rule is about the `when` blocks,
not the targets. Every conditional transition in a state must share a field.
This is why `work-on.md`'s real states repeat `status` in every `when`.

**The fix is to repeat the gate field.** This compiles and behaves correctly:

```yaml
create_branch:
  default_action:
    command: "git checkout -b impl/demo 2>/dev/null || git checkout impl/demo"
  gates:
    on_impl_branch:
      type: command
      command: 'test "$(git rev-parse --abbrev-ref HEAD)" = "impl/demo"'
  accepts:
    status: { type: enum, values: [override, blocked], required: true }
    detail: { type: string, description: What you did instead }
  transitions:
    - target: analysis
      when: { gates.on_impl_branch.exit_code: 0 }
    - target: analysis
      when: { gates.on_impl_branch.exit_code: 1, status: override }
    - target: done_blocked
      when: { gates.on_impl_branch.exit_code: 1, status: blocked }
```

**Happy path, verified.** With the action succeeding, `koto next` returned
`{"action":"done","advanced":true,"state":"analysis"}` and the working tree was
left on `impl/demo`. koto created the branch; the agent never saw the
`create_branch` state, its directive, or any instruction to run git. Verified
both with and without the `accepts` block present — the block does not force an
evidence round trip on success.

**Failure path, verified.** With the action failing, `koto next` returned
`action: "evidence_required"`, `advanced: false`, the state's directive as
written for the manual case, `blocking_conditions` carrying the gate's
`{exit_code: 1, error: ""}`, and an `expects` block listing the `status`/`detail`
fields and enumerating all three transition options. The agent has everything it
needs to take over and report back.

So the shape the user described — koto runs it, the agent is handed prose only
when it fails — is available now, for any step whose success a cheap gate
command can verify independently. What the pattern still cannot do is show the
agent *why* the action failed: the `blocking_conditions` entry carries the
gate's exit code, not the action's stderr, so a `git checkout` that failed on a
dirty tree is indistinguishable from one that failed on a detached HEAD.

## Implications

- The three-path pattern being available today changes the recommendation's
  shape: shirabe can adopt the target design for a real subset of steps without
  waiting on any koto change, and the koto work is what widens that subset and
  makes failures diagnosable rather than what unlocks it at all.
- The 64KB deadlock is the highest-severity finding of the whole exploration,
  and it is not about `default_action` at all. It affects gates that shirabe
  ships and runs today, converts passing checks into 30-second false failures,
  and hides the evidence by discarding the output. It should be fixed before any
  conversion work expands the number of commands koto runs.
- Every option in the output-routing design space assumes koto has the output.
  Above 64KB it does not — it has nothing. Whatever routing mechanism gets
  built, it needs the concurrent-drain fix underneath it or it inherits a silent
  hole exactly where output is most voluminous and most worth reading.
- The migration-warning volume is a small, independent fix with an outsized
  effect: it is what makes koto unusable as a nested command in a mature
  workspace.
- Any "script per state" pattern — the counter-case's preferred alternative —
  is subject to the same limit the moment koto is the one invoking the script.

## Surprises

- The bug is in the most basic layer, shared by the mechanism everyone already
  trusts. Gates have been running this way since before `default_action` existed.
- A 30-second stall per occurrence is the *good* outcome. The bad outcome is the
  false negative: a command that succeeded, reported as timed out, with its
  output destroyed.
- koto's own CLI noise being the thing that makes koto unable to call koto.

## Open Questions

- Does the same pattern appear anywhere else output is captured — the polling
  path, the integration closure, batch child spawning?
- Is the migration scan supposed to run on every invocation, or is it a
  first-run migration that never records completion?
- What is the right ceiling? Draining concurrently and truncating at 64KB
  preserves the intended guard; keeping everything risks unbounded memory on a
  runaway command.

## Summary

`run_shell_command` — shared by both gate evaluation and `default_action` —
deadlocks whenever a command writes more than the 64KB pipe buffer, because the
parent waits on the child before draining the pipes; 60KB succeeds, 70KB stalls
for 30 seconds and reports exit -1 with the output discarded. Gates have the
same defect, which makes it a live bug in shirabe's shipped `/work-on` template,
whose `tests_passing` gate runs `go test ./...`. It also explains, and corrects,
this probe's earlier claim about nested koto calls: koto emits roughly 106KB of
migration warnings on stderr per session-touching command in this workspace, so
it deadlocks itself — there is no lock involved.
