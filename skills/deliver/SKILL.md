---
name: deliver
description: >-
  Take a feature from scoping to its PRs in one session: run `/scope` with
  `--intent=continue` and then `/execute` on the PLAN it produces, merging
  (when the repository's own rules allow it, and in an interactive run only
  after a review pause) unless run with `--no-merge`. Use
  it when the author wants a topic done end to end without re-invoking
  anything between the two -- "scope and build this", "deliver the
  plugin-system feature", "take this from idea to PR" -- and to pick such a
  topic up again, since every invocation re-enters through `/scope`, which
  knows where the topic stopped. Do NOT use it to write only the documents
  (`/scope`), to run a PLAN that already exists and needs no re-scoping
  (`/execute`), or to fix one known issue (`/work-on`).
argument-hint: '<topic-slug> [--auto|--interactive] [--no-merge] [--upstream <path>] [--max-rounds=N] [--coordinated|--no-coordinated] [--review-floor=<level>] [--review-ceiling=<level>] [--koto-leg=<request-id>:deliver]'
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh deliver 2>&1 || true`

# Deliver

`/deliver <topic>` runs `/scope <topic> --intent=continue` and then
`/execute docs/plans/PLAN-<topic>.md` in one session, without the author
re-invoking anything. It passes `--merge` to `/execute` unless `--no-merge` is
given. An `--auto` run ends `merged` wherever the repository's protection lets
`/execute` merge, and in a named, resumable state everywhere else. An
interactive run, the default when neither flag nor the repository's
`## Execution Mode:` header asks for `auto`, stops before the merge, at
`paused-for-review`: `/execute`'s review pause, with the home PR still draft.

`/deliver` is a koto workflow, and it is thin in behaviour: it writes nothing
to the repository itself. `/scope` and `/execute` do all of that, as the same
root sessions (`scope-<topic>`, `execute-<topic>`) a person running them
directly would get. Visibility is checked where content is written: each
child checks its writes against the repository it writes to, so `/deliver`
runs in private repositories as well as public ones. What `/deliver` adds is the sequence and the checks
between the two, and those live in its template,
`skills/deliver/koto-templates/deliver.md`, not in this file. koto's request
store is local, so a `/deliver` run, children included, happens on one machine.

## Flags

| Flag | Effect |
|------|--------|
| `--auto` / `--interactive` | The execution mode, resolved once and passed to both children. With neither, the repository's `## Execution Mode:` header in CLAUDE.md decides, and without one the run is interactive. Interactive runs get one confirmation from `/deliver` before `/execute` starts, naming the PLAN's mode. |
| `--no-merge` | `/execute` runs without `--merge`, so the run ends at best `ready-awaiting-merge`. Without it, `/execute` gets `--merge`. |
| `--upstream <path>`, `--max-rounds=N`, `--coordinated` / `--no-coordinated` | Forwarded to `/scope` unchanged. |
| `--review-floor=<level>`, `--review-ceiling=<level>` | The review-level bound (`light`, `standard` or `full`), forwarded to `/execute` unchanged, which hands it to every `/work-on` run it starts. Without them `/execute` gets neither. |
| `--koto-leg=<request-id>:deliver` | Binds this run's `deliver-<topic>` session to a leg of a caller's koto request; see Answering a Caller's Leg. Not forwarded to either child. |

koto checks every argument a koto variable can express, not this file: a
repeated flag, both mode flags, both coordination flags, a malformed topic or
upstream, a `--max-rounds` outside 1 to 50, or a `--review-floor` or
`--review-ceiling` that isn't `light`, `standard` or `full` is refused at `koto init` with
exit 2 and no session. `--koto-leg` is the one exception: `deliver-open.sh`
checks it before any koto call, because without a well-formed value there is
no leg to record a refusal on (see Answering a Caller's Leg).

`--merge` and the mode belong to one invocation. Nothing is remembered from an
earlier run: a re-invocation without `--no-merge` merges, and one with it
doesn't, whatever the previous run did.

## Answering a Caller's Leg

`--koto-leg=<request-id>:deliver` (or `--koto-leg <request-id>:deliver`) lets
a coordinator run `/deliver` as a worker and read its result from koto's
request store instead of from what the worker says. The leg must be named
`deliver`; that is the one leg `/deliver` answers. A value given twice, a leg
with another name, or a request id outside `^[a-z0-9_][a-z0-9_-]{0,63}$` is
refused by `deliver-open.sh` itself, with `step=deliver:refused` and no koto
call, because without a well-formed value there is no leg to record anything
on.

With a well-formed value, the one `koto init` that opens the fresh
`deliver-<topic>` session carries `--koto-leg`, and koto either binds the
session to the leg or records its refusal there: `result_source: refused`
(`source: refused` on a `request-leg` gate), with `outcome: refused` and a
`reason` such as `invalid-var:TOPIC`. A same-named session this run won't
touch (another worktree's, or one from another template) is refused with the
code the run prints, `origin-mismatch` or `template-mismatch` on the leg. Once
bound, the run's terminal result reaches the leg by promotion on the terminal
tick, `--no-cleanup` notwithstanding: the same `outcome`, `step`, `reason`,
`pr`, and other keys `deliver-report.sh` prints.

What the coordinator puts on the leg, so koto admits the session:

| Leg field | Value |
|-----------|-------|
| name | `deliver` |
| `template` | `deliver.md` |
| `inputs` | `TOPIC`: the topic slug, as passed to `/deliver`. Optionally `COORDINATION` and `UPSTREAM`, which must then equal the value the invocation resolves to: `COORDINATION` is `coordinated`, `no-coordinated`, or `none` when neither flag is given; `UPSTREAM` is the `--upstream` value, or the empty string when it isn't given. |

koto compares only the inputs the leg names, and only against variables that
aren't `rebind`: `MODE`, `MERGE`, `MAX_ROUNDS`, and `PLUGIN_ROOT` are
re-applied per invocation and can't be pinned from the leg, so an input for
one of them is never compared. A leg whose `TOPIC` differs from the
invocation's is refused as `input-mismatch` on the leg.

A leg is named `deliver` and nothing else, so one request holds at most one
`/deliver` worker; a coordinator running several gives each its own request.
koto records a refusal only on a leg that is still open and unbound. koto's
refusal of this run's open reaches the leg, including a same-named session the
probe stopped on. Nothing that stops before that open does: no topic, a failed
preflight, `deliver-open.sh`'s usage refusals, `failed=jq_missing`, or
`failed=cleanup`. Neither does a run that stops before its terminal. In those
cases the leg stays open, and a `request-leg` gate would wait on it
indefinitely, so the coordinator needs its own fallback for a worker that
ended without a result.

Keep the two requests apart. The caller's request and its `deliver` leg
belong to the caller: `/deliver` never lists, closes, or abandons it, and the
Close step below touches only the run's own request. That inner request,
under coordinator `deliver-<topic>`, still carries the `scope` and `execute`
legs its children answer, exactly as it does without the flag. The one thing
the caller must not do is create its request under coordinator-of-record
`deliver-<topic>`: every open request under that name is abandoned when the
run opens its own. The flag changes where this run's own result goes and
nothing else.

## Running the Workflow

1. **Write the args file.** Split `$ARGUMENTS` into tokens as typed, the topic
   included, and write them in order as a JSON array of strings to a private
   directory outside the work tree:

   ```bash
   ARGS_DIR=$(${CLAUDE_PLUGIN_ROOT}/scripts/koto-open.sh --alloc-dir)
   ```

   Write `$ARGS_DIR/args.json` with the Write tool or `jq`, never by pasting
   tokens into a shell command and never with `eval`: a token is data, and the
   file is the only route by which it reaches koto. If `$ARGUMENTS` holds no
   topic, ask the author for one and stop instead.

2. **Open the session.**

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/deliver/scripts/deliver-open.sh --plugin-root ${CLAUDE_PLUGIN_ROOT} "$ARGS_DIR/args.json"
   ```

   It maps each token to a variable with `jq`, resolves the mode, and opens a
   fresh `deliver-<topic>` session. The args file and its directory are
   removed on every exit path, refusals included. On success it prints
   `session=deliver-<topic>`. A refusal prints koto's reason on stderr and then
   `outcome=error` and `step=deliver:refused`; print them and stop. A
   same-named session from another worktree or another template is refused
   this way and left untouched.

3. **Tick.** Call `koto next deliver-<topic> --no-cleanup`, do what the
   directive says, submit the evidence it asks for, and repeat.
   **Every `koto next` carries `--no-cleanup`, on every tick.** The flag keeps
   the run's record readable after its terminal; see
   `${CLAUDE_PLUGIN_ROOT}/references/koto-session-retention.md`. The directives
   tell you when to run `/scope` and `/execute` (as Skill calls, with the exact
   arguments they list) and when to ask the one confirmation. Run each child to
   its end as its own directives say, then tick `/deliver` again.

4. **Report.** When `koto next` answers `"action": "done"`, print the report,
   verbatim, and compose no line of your own:

   ```bash
   koto status deliver-<topic> | ${CLAUDE_PLUGIN_ROOT}/skills/deliver/scripts/deliver-report.sh
   ```

   Every `outcome=` token it can print, and what each one means, is listed in
   the header of `skills/deliver/scripts/deliver-report.sh`.

5. **Close the request.** On the way out, close this run's request:

   ```bash
   koto request list --coordinator-of-record deliver-<topic> --state open
   koto request close <request-id>
   ```

   A request left open is abandoned by the next `/deliver <topic>` anyway, so
   a run that stops before this step leaves nothing that can be mistaken for a
   later run's.

If you lose a directive, `koto status deliver-<topic>` returns the current
state's directive without ticking. Never run a cleanup or cancel verb against
a session this run did not open, and never `koto request resolve` a leg by
hand: the one value `/deliver` ever writes to a leg is its own fixed
child-absent record, written by the template.
