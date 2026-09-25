---
name: deliver
description: >-
  Take a feature from scoping to its PRs in one session: run `/scope` with
  `--intent=continue` and then `/execute` on the PLAN it produces, merging
  (when the repository's own rules allow it) unless run with `--no-merge`. Use
  it when the author wants a topic done end to end without re-invoking
  anything between the two -- "scope and build this", "deliver the
  plugin-system feature", "take this from idea to PR" -- and to pick such a
  topic up again, since every invocation re-enters through `/scope`, which
  knows where the topic stopped. Do NOT use it to write only the documents
  (`/scope`), to run a PLAN that already exists and needs no re-scoping
  (`/execute`), or to fix one known issue (`/work-on`).
argument-hint: '<topic-slug> [--auto|--interactive] [--no-merge] [--upstream <path>] [--max-rounds=N] [--coordinated|--no-coordinated]'
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh deliver 2>&1 || true`

# Deliver

`/deliver <topic>` runs `/scope <topic> --intent=continue` and then
`/execute docs/plans/PLAN-<topic>.md` in one session, without the author
re-invoking anything. It passes `--merge` to `/execute` unless `--no-merge` is
given, so a run ends `merged` wherever the repository's protection lets
`/execute` merge, and in a named, resumable state everywhere else.

`/deliver` is a koto workflow, and it is thin in behaviour: it writes nothing
to the repository itself. `/scope` and `/execute` do all of that, as the same
root sessions (`scope-<topic>`, `execute-<topic>`) a person running them
directly would get. What `/deliver` adds is the sequence and the checks
between the two, and those live in its template,
`skills/deliver/koto-templates/deliver.md`, not in this file.

## How the Run Is Held Together

Each invocation opens a fresh `deliver-<topic>` session and a fresh koto
request with two legs, `scope` and `execute`. Each child joins its leg through
its own `--koto-leg=<request-id>:<leg>` flag and reports through its terminal
result, which koto records on the leg. `/deliver` reads each leg only through
a `request-leg` gate in its template. It never parses what a child printed,
and nothing you submit can stand in for a child's result.

A child's word never moves the run forward on its own. Every forward step is
re-checked against durable state first: the PLAN tracked and the scoping PR
recording `intent=continue` after `/scope`, the PLAN's mode before `/execute`,
the owned PR re-read after `/scope` reports an already-executed topic, and
GitHub re-read before `merged` is reported. Those re-checks find the PR
themselves through the shared ownership filter; a PR a leg names is never
trusted. The gates that route on a leg or a re-check refuse
`koto overrides record`, with or without `--with-data`.

The request id is also the stale-run fence. Before this run's request is
created, every request still open for the topic is abandoned, so a late
result from an earlier run is refused at promotion and never read as this
run's.

## Flags

| Flag | Effect |
|------|--------|
| `--auto` / `--interactive` | The execution mode, resolved once and passed to both children. With neither, the repository's `## Execution Mode:` header in CLAUDE.md decides, and without one the run is interactive. Interactive runs get one confirmation from `/deliver` before `/execute` starts, naming the PLAN's mode. |
| `--no-merge` | `/execute` runs without `--merge`, so the run ends at best `ready-awaiting-merge`. Without it, `/execute` gets `--merge`. |
| `--upstream <path>`, `--max-rounds=N`, `--coordinated` / `--no-coordinated` | Forwarded to `/scope` unchanged. |

koto checks every argument, not this file: a repeated flag, both mode flags,
both coordination flags, a malformed topic or upstream, or a `--max-rounds`
outside 1 to 50 is refused at `koto init` with exit 2 and no session.

`--merge` and the mode belong to one invocation. Nothing is remembered from an
earlier run: a re-invocation without `--no-merge` merges, and one with it
doesn't, whatever the previous run did.

## Running the Workflow

1. **Write the args file.** Split `$ARGUMENTS` into tokens as typed, the topic
   included, and write them in order as a JSON array of strings to a private
   directory outside the work tree:

   ```bash
   ARGS_DIR=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/koto-open.sh --alloc-dir)
   ```

   Write `$ARGS_DIR/args.json` with the Write tool or `jq`, never by pasting
   tokens into a shell command and never with `eval`: a token is data, and the
   file is the only route by which it reaches koto. If `$ARGUMENTS` holds no
   topic, ask the author for one and stop instead.

2. **Open the session.**

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/deliver/scripts/deliver-open.sh --plugin-root ${CLAUDE_PLUGIN_ROOT} "$ARGS_DIR/args.json"
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
   **Every `koto next` carries `--no-cleanup`, on every tick.** The session is
   a root, so the flag withholds nothing from anyone and keeps the run's
   record readable after its terminal; see
   `${CLAUDE_PLUGIN_ROOT}/references/koto-session-retention.md`. The directives
   tell you when to run `/scope` and `/execute` (as Skill calls, with the exact
   arguments they list) and when to ask the one confirmation. Run each child to
   its end as its own directives say, then tick `/deliver` again.

4. **Report.** When `koto next` answers `"action": "done"`, print the report,
   verbatim, and compose no line of your own:

   ```bash
   koto status deliver-<topic> | bash ${CLAUDE_PLUGIN_ROOT}/skills/deliver/scripts/deliver-report.sh
   ```

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

## Resume

There is no resume state in `/deliver` itself. Every invocation opens a fresh
session and a fresh request, and always enters through `/scope`, which owns
every "where did this topic stop" question:

- an unfinished `/scope` run in this working copy resumes inside `/scope` at
  the hop it stopped; its session is re-pointed from the abandoned request to
  this run's leg, so no second `scope-<topic>` session appears;
- a topic whose PLAN exists passes through `/scope`, which re-runs its publish
  step (opening the branch's PR if none is open), and then `/execute` adopts
  that PR; no BRIEF, PRD, or DESIGN is written again;
- a topic whose PLAN was already executed and removed isn't re-scoped: `/scope`
  reports it, `/deliver` re-reads the owned PR, and the run ends `merged` or
  `ready-awaiting-merge` without running `/execute`;
- an unfinished `/scope` run started with a different intent isn't converted:
  the run ends `outcome=error` with `step=deliver:intent-mismatch`.

A `multi-pr` PLAN is never handed to `/execute`: the run ends
`handed-off-multi-pr` and lists the startable items.

## Final States

`deliver-report.sh` prints `outcome=<token>` first, then the lines the result
calls for.

| Token | Meaning |
|-------|---------|
| `merged` | Every PR the PLAN needs reads MERGED on GitHub, coordination PR included, confirmed by `/deliver`'s own live read. |
| `ready-awaiting-merge` | The PRs are open and ready, and at least one is unmerged; each is listed with `waiting=human` or `waiting=predecessor`. |
| `paused-awaiting-merges` | Coordinated only: some PR can't start until a predecessor merges. Each unmerged PR is listed, with the `resume=` command. |
| `paused-for-review` | Interactive only: `/execute`'s review pause, with the home PR still draft. |
| `scoped` | The author declined the confirmation; the report prints `next=/deliver <topic>`. |
| `handed-off-multi-pr` | The PLAN is `multi-pr`; `/execute` was not started, and the startable items follow. |
| `scope-ended-early` | `/scope` ended at `re-evaluation`, `abandonment`, or a clean cancel; `reason=` names which. |
| `error` | A step failed; `step=` names it: `/scope`'s and `/execute`'s own steps, `scope:refused` and `execute:refused` (a child's arguments or attach refused), `deliver:intent-mismatch`, `deliver:child-outcome` (a result `/deliver` doesn't recognise, or a re-check that failed), `deliver:child-absent` (a child returned without ever recording a result), `deliver:request-abandoned` (this run's request was abandoned under it), or `deliver:refused` (the repository isn't public, `reason=private-repo`, or koto refused this invocation's own arguments). |

The report also carries, where the run produced them, `repos=` (the
repositories `/execute` wrote to), `pr=`, `pr_state=`, and `wip_paths=` (the
`wip/` paths `/scope` published with its branch). Every value is checked
against a closed pattern before it is printed.

## Write Targets

`/deliver` has one write of its own: the per-run koto request, in koto's local
request store. Its template's default actions touch only that store and this
run's own session context; none of them pushes, opens or edits a PR, or merges.

Every repository write happens through its children, under their own
declarations: `/scope`'s artifact commits, its `git push`, and its one
`gh pr create` for the scoping PR; `/execute`'s commits, pushes, PR creation,
readying, and, with `--merge`, its one `gh pr merge` call site. The re-checks
`/deliver` runs between them only read git and GitHub.

## Security Considerations

- **Repository binding.** `/deliver` runs public-repo tactical chains only, the
  binding `/scope` has. The `preflight` state reads the `## Repo Visibility:`
  header; `Private`, or no header at all, ends the run `outcome=error` with
  `reason=private-repo` before any request is opened.
- **Arguments are data.** Tokens reach koto only through the args file and
  `--vars-file`, mapped with `jq`; koto enforces each variable's pattern before
  any gate sees a value, and every gate command quotes its variables.
- **Leg results are checked, not trusted.** Only a promoted result that passes
  the gate's closed `expect` set can move the run; an explicit or refused
  result reaches only an error. Every value the report prints from a leg is
  checked against a closed pattern and dropped otherwise, so a leg can't carry
  control characters or prose into the report.
- **Merges stay gated by the repository.** `/execute --merge` merges only what
  its merge decision table allows, and `/deliver` reports `merged` only after
  its own live read. An unattended `--auto` run can merge only where the
  repository's rules would let an ordinary contributor merge.
- **Single machine.** koto's request store is local, so a `/deliver` run is a
  single-machine flow.

## Reference Files

| File | Purpose |
|------|---------|
| `skills/deliver/koto-templates/deliver.md` | The workflow: states, gates, routing, results |
| `skills/deliver/scripts/deliver-open.sh` | The koto entry: tokens to variables, a fresh session |
| `skills/deliver/scripts/deliver-report.sh` | The printed report, from the terminal result |
| `${CLAUDE_PLUGIN_ROOT}/references/koto-session-retention.md` | Why every tick carries `--no-cleanup` |
| `skills/scope/SKILL.md`, `skills/execute/SKILL.md` | The children, including `--koto-leg`, `--intent`, and `--merge` |
