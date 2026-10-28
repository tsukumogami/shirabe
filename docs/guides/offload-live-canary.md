# The Live Offload Canary

How to turn the live offload canary on for a host, turn it off, and read its
result in Datadog. The canary leaves one rule, `pr-body/no-heading-in-part1`
(PB4, no markdown heading in Part 1 of a pull request body), out of the
PR-body conformance text about half of `/work-on` runs read, keeps it in the
other half, and lets a query split the rule's broken rate between the two.
The design is `DESIGN-offload-live-canary.md`.

## What a run does

A `/work-on` run takes part only when all of these hold:

- the template's `OFFLOAD_CANARY` variable is `on` (its default);
- the host has opted in (below);
- the rule registry marks `pr-body/no-heading-in-part1` `withhold: eligible`;
- the run isn't an `/execute` child on a shared branch, which opens no pull
  request of its own.

So the canary withholds nothing until the registry marks PB4 eligible and the
host opts in: until both hold, every run reads the full conformance text.

When its analysis plan is ready, the run passes through `offload_canary` on
its way to `review_level_choice`. That state draws a group from
`/dev/urandom`, records it in the session directory, and routes the run
through one of two marker states:

| Group | Marker state | What the run reads at `pr_creation` |
|---|---|---|
| withheld | `offload_arm_withheld` | a copy of `references/pr-body-conformance.md` without PB4's lines |
| preloaded | `offload_arm_preloaded` | `references/pr-body-conformance.md` |
| neither | none | `references/pr-body-conformance.md` |

A run that can't be assigned, for any reason, is in neither group and goes on
as if the canary were off. Once a run has a group it keeps it: a rewind reads
the recorded group back, and `OFFLOAD_CANARY` can't be rebound. A run that was
in neither group has nothing recorded, so a rewind into the assignment state
draws again; that run then counts in the group it drew.

In every group, when the `pr_body_conformant` gate fails on PB4, its output
carries the finding, whose message opens with PB4's summary. From the second
failure on PB4 in the run, the escalation ladder (`references/rule-registry.md`,
"Escalating a rule's text") also hands over PB4's full text, so a withheld agent
whose first fix misses gets the whole rule.

On an opted-in host, `shirabe pr-body-hook`, the PreToolUse hook that checks a
`gh pr create` or `gh pr edit` before it runs, no longer denies one for PB4,
in either group: otherwise it would stop a PB4 violation before the pull
request exists and the koto gate would never count it. It still denies PB1 to
PB3 there, and it denies PB4 on every other host. The koto gate holds the
run on a PB4 finding, and the PR-body CI check, a required status check on
shirabe's `main`, keeps the pull request from merging while it fails.

The same exception holds in the plugin's own pre-action hook,
`hooks/pre-action-deny.sh`, which runs `shirabe pre-action-hook` and shares
the evaluator with `shirabe pr-body-hook`. It reads the same opt-in file, so
on an opted-in host it lets a `gh pr create` or `gh pr edit` through on PB4
alone and still denies it for PB1 to PB3; on every other host it denies PB4
too.

## Turning it on for a host

Create the opt-in file with `on` as its first line:

```bash
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/shirabe"
echo on > "${XDG_CONFIG_HOME:-$HOME/.config}/shirabe/offload-canary"
```

Only hosts whose koto events reach the backend you read results from should
opt in: a run on any other host would withhold the rule without being
measured. The host also needs a shirabe release that carries the canary, for
both the plugin's files and the `shirabe` binary the hook runs.

To turn one host off, delete the file or change its first line.

## Turning it off everywhere

Change the default of `OFFLOAD_CANARY` in
`skills/work-on/koto-templates/work-on.md` from `"on"` to `"off"`. The line
to change is:

```yaml
    default: "on"
```

under `OFFLOAD_CANARY:` in the `variables:` block. Every run started after
the change is in neither group; a run already in progress keeps its group.

## Reading the result

koto exports names, not values, so a run's group is read from the marker
state it entered. Three event kinds carry what the readout needs, joined on
`koto.session.id`:

| Event | Attribute | Meaning |
|---|---|---|
| `state_entered` | `koto.state` = `offload_arm_withheld` or `offload_arm_preloaded` | the run's group |
| `state_entered` | `koto.state` = `pr_creation` | the run reached the gate: the denominator |
| `check_rule` | `koto.rule.id` = `pr-body/no-heading-in-part1` | the gate found PB4 broken: the numerator |

Run it from a session with Datadog's log analytics (the
`analyze_datadog_logs` tool), over the window you want:

- filter: `(state_entered @koto.state:(offload_arm_withheld OR offload_arm_preloaded OR pr_creation)) OR (check_rule @koto.rule.id:"pr-body/no-heading-in-part1")`
- extra columns: `@koto.session.id`, `@koto.state`, `@koto.rule.id`, each `varchar`

```sql
WITH ev AS (
  SELECT "@koto.session.id" AS sid, message AS kind,
         "@koto.state" AS st, "@koto.rule.id" AS rid
  FROM logs),
arm AS (
  SELECT DISTINCT sid,
         CASE WHEN st = 'offload_arm_withheld' THEN 'withheld' ELSE 'preloaded' END AS arm
  FROM ev
  WHERE kind = 'state_entered' AND st IN ('offload_arm_withheld', 'offload_arm_preloaded')),
reached AS (SELECT DISTINCT sid FROM ev WHERE kind = 'state_entered' AND st = 'pr_creation'),
broken AS (SELECT DISTINCT sid FROM ev WHERE kind = 'check_rule' AND rid = 'pr-body/no-heading-in-part1')
SELECT a.arm, COUNT(r.sid) AS runs, COUNT(b.sid) AS broken_runs
FROM arm a JOIN reached r ON r.sid = a.sid LEFT JOIN broken b ON b.sid = a.sid
GROUP BY a.arm
```

Each row is a group: `runs` is how many of its sessions reached
`pr_creation`, and `broken_runs` how many of those had PB4 broken at least
once. The broken rate is `broken_runs / runs`. A session counts once however
often it entered `pr_creation` or broke the rule, a group with runs and no
broken run shows 0, and a session with no marker state (canary off, a shared
branch, a host that didn't opt in, a failed assignment, a run started before
the canary) is left out by the join.

### Why the denominator is runs

A passing check records no rule: `check_rule` is written only when a gate
fails. Before 2026-10-14T20:12Z a passing `check_evaluated` didn't even carry
its gate's name in Datadog, because its `koto.check` string collided with the
`koto.check.*` fields. So the query's denominator is sessions that reached
`pr_creation`, where the gate runs, which works for any window.

From 2026-10-14T20:12Z, `check_evaluated` carries the gate name as
`koto.check.name` (`check_rule` keeps `koto.check`). For windows that start
after that, per-check counts are also available: `check_evaluated` events with
`@koto.state:pr_creation @koto.check.name:pr_body_conformant`, split by
`@koto.check.outcome`. Use the per-run count for any window that reaches back
before it.

## Reading it honestly

- **The sample is small.** Expect a few dozen runs a week to reach
  `pr_creation` across both groups, and PB4 rarely breaks, so a difference
  shows as a count over several weeks.
- **It counts first failures.** After a run breaks PB4 once, the gate hands
  it the rule's summary, and from a second break its full text, so both groups
  have the rule from then on. A run counts once either way.
- **Summary or full text.** Each PB4 `check_rule` carries
  `koto.rule.session_count`. A broken run whose highest count is 1 fixed PB4
  from the summary; 2 or more needed the full text. Adding
  `@koto.rule.session_count` as a column to the query above splits
  `broken_runs` that way, per group.
- **A gate run before the pull request is readable isn't a break.** When
  the gate runs before the pull request or its body exists, it fails with
  `pr-body/pr-missing` or `pr-body/body-missing`, and with
  `pr-body/read-failed` when the read itself fails, never with PB4, so
  those `check_rule` records don't reach `broken_runs`. The first two also
  mark the evaluation not ready. A failure carrying only the gate's name,
  `pr_body_conformant`, comes from a plugin version before these rules
  existed.
- **Runs from one plan are correlated.** Each `/work-on` run in a `multi-pr`
  plan draws on its own, but runs from one plan share an author and a task,
  so they aren't independent samples.
- **Only runs that reach a ready plan are drawn.** A run that stops before
  its analysis plan is ready is in neither group; it never reaches
  `pr_creation` either, so both groups lose the same runs.
- **Some contamination narrows the difference.** `phase-6-pr.md` points the
  agent at its project's own PR-creation skill for Part 2, and an agent may
  know the convention already. Either can carry the rule into a withheld
  run.
