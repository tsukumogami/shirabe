---
schema: design/v1
status: Planned
upstream: docs/prds/PRD-staleness-check-portability.md
problem: |
  /work-on's staleness_check gate runs `check-staleness.sh --issue N` by bare
  name. shirabe doesn't ship that script, and the one copy a separately
  installed plugin provides takes the issue number positionally and rejects
  `--issue`. The gate fails before assessing anything on every issue-backed
  run, the state offers no honest way past for an unattended agent, and every
  run takes a hand override.
decision: |
  Port the check into shirabe as skills/work-on/scripts/check-staleness.sh,
  reached through the template's existing PLUGIN_ROOT variable, with
  `--issue N` as its only argument form and the verdict carried in its exit
  status: 0 fresh, 1 stale, 3 unavailable, 2 usage. The gate command runs it
  directly, with no jq pipe, and exits 3 itself when the script isn't
  executable. staleness_check gains a fifth evidence value, `unavailable`,
  routed to analysis only when the gate's exit code is 3 or koto's timeout
  code -1, so it can't stand in for a stale verdict.
rationale: |
  Porting is the only option that keeps the staleness signal on a
  shirabe-only host without waiting on another project, and the check needs
  nothing shirabe doesn't already declare. Exit codes, rather than a jq pipe,
  let the gate carry three outcomes through koto's {exit_code, error} output,
  and they survive koto running gates without pipefail. A conditional gate
  alone would keep the gate honest but never check anything on the hosts this
  issue is about; koto has no staleness concept to host the logic; and
  dropping the gate gives up a cheap guard against implementing an overtaken
  issue. The availability branch of the conditional option survives inside
  the port as the `unavailable` outcome.
---

# DESIGN: staleness-check portability

## Status

Planned

## Context and Problem Statement

The requirements are in the upstream PRD; this section restates only the
technical shape of the gap.

`skills/work-on/koto-templates/work-on.md` declares `staleness_check` with one
command gate:

```yaml
staleness_fresh:
  type: command
  command: "check-staleness.sh --issue {{ISSUE_NUMBER}} | jq -e '.introspection_recommended == false'"
```

and four evidence values: `fresh` (routes to `analysis` only when
`gates.staleness_fresh.exit_code` is 0), `stale_requires_introspection`,
`override`, and `blocked` (routes to `done_blocked`).

Three facts about the engine and the host shape the design:

1. **koto runs a command gate through `sh -c` without `pipefail`**, and the
   gate's output the agent sees is `{"exit_code": <n>, "error": ""}`; a
   timeout reports `exit_code: -1`. With the script missing, the pipeline's
   status is `jq`'s, which is 4 on empty input under `-e`. The agent can't
   tell "not found" from "stale" by anything but guessing at that number.
2. **The gate's working directory is the repository being worked**, not the
   shirabe checkout, so a repo-relative path to a shirabe script resolves only
   when `/work-on` runs on shirabe itself. The template already solves this
   for `cascade_entry` with a `PLUGIN_ROOT` variable passed at `koto init`,
   and a `test -x ... || exit 2` guard for an empty value.
3. **This state requires evidence even when its gate passes.** A probe
   template with the same shape (a required enum, a gate-conditioned `fresh`
   edge, a trailing unconditional edge) stops with `evidence_required` and no
   blocking condition on a passing gate, and the same probe shows that a
   gate-conditioned edge refuses evidence when the exit code doesn't match: it
   leaves the workflow in place rather than falling through to the
   unconditional edge. A gate-only edge that routes without evidence can't
   coexist with the evidence edges; koto's compiler rejects the pair as not
   mutually exclusive. The current directive's claim that a passing gate
   auto-advances is therefore wrong, and the design doesn't depend on it.

The check being replaced reads four signals from GitHub and git: the issue's
age against a 14-day threshold, milestone siblings closed since the issue was
created, the issue's position in its milestone, and files named in the issue
body that have commits since creation. It uses GNU `date -d` for the age, and
it treats a failed milestone query as "no siblings", which reads as fresh.

## Decision Drivers

- A shirabe-only host must get a real verdict, not only a graceful skip.
- Nothing may depend on, reference, or accommodate a privately distributed
  plugin; the other script's argument form is not an input.
- Only `gh`, `jq`, `git` and POSIX utilities, at the bash 3.2 floor shirabe's
  scripts run on (macOS system bash).
- The gate must carry three outcomes through a `{exit_code, error}` result.
- The degraded outcome must be distinct from `override` and `blocked`, must
  continue the run, and must be impossible to submit on a stale verdict.
- Change the template as little as possible next to open work (#420 edits
  other states of the same file).

## Considered Options

### Decision 1: Where the staleness logic lives

**Chosen: port the check into shirabe.** A script under
`skills/work-on/scripts/`, shipped with the plugin, reached through
`{{PLUGIN_ROOT}}`. It meets every PRD requirement, uses only declared tools,
and puts the definition of "stale" where shirabe maintainers can read and
test it. Cost: shirabe now owns about 200 lines of shell and a test suite,
and a GitHub-API-shaped check whose tuning is shirabe's problem.

**Rejected: make the gate conditional on availability.** Prefix the gate with
`command -v check-staleness.sh || exit 3` and add the degraded outcome. This
is cheap and makes the gate honest, and it is the right short-term fix the
issue thread suggested. On its own it fails the goal: on a shirabe-only host
the check never runs, so every issue-backed run records "unavailable" forever
and the staleness signal is still gone. It also keeps a bare-name `PATH`
lookup, so a same-named script elsewhere on the host is still picked up and
still rejects `--issue`, which the PRD rules out. Its availability branch is
kept, inside the port, as the path for an empty `PLUGIN_ROOT` or an
unreachable GitHub.

**Rejected: move the logic into koto.** koto has gates, evidence and context,
but no notion of issues, milestones, or GitHub; a staleness gate type would
put a GitHub client in a workflow engine whose gates are deliberately generic
(command, context-exists, request-leg). A narrower koto feature that would
help, gate commands declaring named result classes so a template could route
on "stale" versus "unavailable" without magic exit codes, is plausible but not
needed here: exit-code-conditioned edges already express the three outcomes.
If koto chose to build either, shirabe would still need an interim answer on
every current koto, and that answer is this port. No koto proposal is filed by
this work.

**Rejected: drop the gate.** Delete `staleness_check`, route setup straight to
`analysis`, and ask agents to notice staleness during analysis. The argument
for it is that the gate has checked nothing for as long as anyone has run
shirabe alone, and nobody noticed. The argument against is that the check is
cheap (three API calls), its failure mode (a re-read of the issue) is cheap,
and the failure it guards against, implementing an issue the codebase has
already overtaken, is expensive and is exactly what an unattended agent
doesn't notice unprompted. The introspection state also has no other entry
point, so dropping the gate orphans it.

### Decision 2: How the gate carries three outcomes

**Chosen: the verdict is the script's exit status.** 0 fresh, 1 stale, 3
unavailable, 2 usage error. The gate runs the script directly:

```yaml
command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-staleness.sh" || exit 3; "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-staleness.sh" --issue "{{ISSUE_NUMBER}}"'
```

No pipe, so `pipefail` doesn't matter; the `test -x` guard turns an empty or
wrong `PLUGIN_ROOT` into the unavailable code rather than 127. The script
prints its JSON report on stdout regardless; koto discards it, and the agent
re-runs the script to read it when it needs reasons (R9).

**Rejected: keep the JSON contract and a `jq -e` pipe, with a pre-check for
availability.** `jq -e` collapses "false", "null" and "error" into its own exit
codes (1, 1, 4, 5), which overlap the script's. Without `pipefail` a script
failure is masked by `jq`'s status. Wrapping it in `sh -c 'set -o pipefail'`
isn't portable to every `sh`.

**Rejected: exit 0 always and route on a context key the script writes.** A
`context-exists` gate on a key like `staleness.json` would need the script to
call `koto context add`, coupling a GitHub check to the session's name, and
the gate would pass on a stale key left by an earlier run.

### Decision 3: The degraded outcome

**Chosen: a fifth evidence value, `unavailable`, with two gate-conditioned
edges to `analysis`**, one for `gates.staleness_fresh.exit_code: 3` and one
for `-1` (koto's timeout code). Submitted with any other exit code it matches
no edge and the workflow stays in `staleness_check`, which the probe in the
Context section confirmed for the same shape. `detail` carries the reason.

**Rejected: reuse `override` with a conventional `detail`.** Cheapest, but it
is the defect restated: `override` stays the routine path, and a reader can't
tell a skipped check from an unavailable one without parsing prose.

**Rejected: route "unavailable" to `blocked`.** The PRD's decision: a
staleness check is advisory, and an unattended run must not end because `gh`
is unauthenticated.

**Rejected: an evidence-free edge on exit code 3.** Would record nothing the
agent wrote, and koto rejects a gate-only edge next to evidence edges.

### Decision 4: Which signals, and what differs from the prior check

**Chosen: keep the four signals and the 14-day threshold unchanged, and
change only what portability and honest failure require.** The PRD puts
retuning out of scope, and identical signals make the port comparable. The
differences, all stated in the signals reference the script ships with:

| Area | Prior check | Ported check |
|------|-------------|--------------|
| Argument | positional `<N>` | `--issue <N>` only; a bare number is a usage error |
| Verdict carrier | JSON field, read by a `jq -e` pipe | exit status 0/1/3, JSON kept on stdout |
| Age arithmetic | GNU `date -d` (fails on BSD `date`, then reads as age 0) | `jq`'s `fromdateiso8601` and `now`, same on Linux and macOS |
| Milestone query failure | counted as 0 siblings, reads as fresh | unavailable (exit 3); no verdict from partial data |
| `gh` calls | 4 (closed milestone list fetched twice) plus `gh auth status` | 3: issue, closed milestone list, open milestone list |
| Missing `gh`/`jq`/`git` | exit 2 | unavailable (exit 3) |

Everything else is unchanged: 14 days; any sibling closed after the issue's
creation; position `middle` or `last` as stale; the same file-reference
heuristic (paths with one of the listed extensions, at most 20); a file counts
as modified when `git log --since=<created>` finds a commit touching it.

**Rejected: retune while porting** (drop the milestone-position signal, which
marks nearly every milestone issue stale). Worth doing, but a behaviour change
hidden inside a portability fix makes both harder to review. It's named in
Consequences as follow-up.

## Decision Outcome

Port the check, carry its verdict in the exit status, and add `unavailable` as
a gate-conditioned evidence value. On a shirabe-only host with `gh`
authenticated, every issue-backed run gets a real fresh or stale verdict. On a
host where the check can't run, the gate exits 3, the directive tells the
agent to submit `unavailable` with the reason, and the run continues with that
outcome in its evidence. `override` and `blocked` keep their edges and go back
to meaning what the directive says. The pieces fit because each carries one
thing: the script decides, the exit status transports, the gate-conditioned
edges enforce, and the directive tells the agent which value matches which
code.

## Solution Architecture

### `skills/work-on/scripts/check-staleness.sh`

```
check-staleness.sh --issue <N>
  exit 0  fresh        no signal fired
  exit 1  stale        at least one signal fired
  exit 2  usage        missing/extra/malformed argument (incl. bare positional)
  exit 3  unavailable  gh/jq/git missing, gh call failed, response unparsable
  stdout  JSON report on 0, 1 and 3; nothing on 2 (usage text on stderr)
```

Flow:

1. Parse arguments; `--issue` must be a positive integer. Anything else exits
   2.
2. `command -v gh jq git`; any missing exits 3 with
   `{"verdict":"unavailable","reason":"<tool> not found"}`.
3. `gh issue view "$issue" --json number,title,createdAt,body,milestone`.
   Failure (auth, network, unknown issue) exits 3 with `gh`'s first stderr
   line in the reason. The repository is whatever `gh` resolves from the
   working directory, which is the repository the session is working in; this
   is the same resolution every other `gh` call in `/work-on` relies on (phase
   1 reads the issue the same way), so the check can't disagree with the run
   about which issue `N` is.
4. Age in whole days: `jq '((now - (.createdAt | fromdateiso8601)) / 86400) | floor'`.
5. With a milestone: `gh issue list --milestone "$milestone_title" --state
   closed --json number,closedAt --limit 100` and the same with `--state open
   --json number`. The title is always one quoted argv element, never part of
   a string handed to `sh -c` or `eval`. Either call failing exits 3.
   Siblings closed since creation are closed items with `closedAt >
   createdAt`; position is `first` when none are closed, `last` when exactly
   one is open, else `middle`. Without a milestone: 0 siblings, position
   `unknown`, no calls.
6. File references: the prior heuristic, run over the body with `grep -oE`
   and `sed`, capped at 20. A candidate that is absolute or has a `..`
   segment is dropped before any file test, so every path checked is inside
   the working tree. Each remaining path that exists as a file and has at
   least one commit since `createdAt` (`git log --since=... --format=%H -1 --
   "$path"`) counts as modified; a `git log` that fails on such a path exits
   3, like the `gh` calls.
7. Build the report with `jq -n`, print it, exit 0 or 1.

The report:

```json
{
  "verdict": "fresh | stale | unavailable",
  "introspection_recommended": true,
  "issue": {"number": 80, "created_at": "...", "age_days": 3, "milestone": null},
  "signals": {
    "issue_age_days": 3,
    "age_threshold_days": 14,
    "sibling_issues_closed_since_creation": 0,
    "milestone_position": "unknown",
    "files_modified_since_creation": []
  },
  "reason": "no staleness signals detected"
}
```

`introspection_recommended` is kept so a reader of the old report finds the
same field. An unavailable report carries `verdict`, `reason`, and the issue number;
partial signals are left out so nothing reads a half-measured value.

The script is written for bash 3.2: no associative arrays, no `mapfile`, no
`${var,,}`, no GNU-only flags. It doesn't use `set -e`, so that an unexpected
failure can't exit 1 and read as stale; every external call is checked and
routes to exit 3.

### `skills/work-on/references/staleness-signals.md`

The one statement of the signals, thresholds and exit codes, including the
table of differences from the prior check (Decision 4). The script's header
points to it; the `staleness_check` directive points to it for "what does
stale mean".

### Template changes (`work-on.md`)

```yaml
staleness_check:
  gates:
    staleness_fresh:
      type: command
      command: 'test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-staleness.sh" || exit 3; "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-staleness.sh" --issue "{{ISSUE_NUMBER}}"'
      override_default: {exit_code: 0, error: ""}
  accepts:
    staleness_signal:
      values: [fresh, stale_requires_introspection, unavailable, override, blocked]
  transitions:
    - {target: introspection, when: {staleness_signal: stale_requires_introspection}}
    - {target: analysis, when: {staleness_signal: fresh, gates.staleness_fresh.exit_code: 0}}
    - {target: analysis, when: {staleness_signal: unavailable, gates.staleness_fresh.exit_code: 3}}
    - {target: analysis, when: {staleness_signal: unavailable, gates.staleness_fresh.exit_code: -1}}
    - {target: analysis, when: {staleness_signal: override}}
    - {target: done_blocked, when: {staleness_signal: blocked}, context_assignments: ...}
```

The state's trailing unconditional `- target: analysis` is removed. It is the
edge koto falls through to when evidence matches nothing else and the gate
passed, so with it in place `unavailable` submitted on a passing gate would
reach `analysis` and record "not assessed" for a check that ran. Without it,
every route out of the state is explicit, and a probe of the same shape
confirms `unavailable` on exit 0 stays in the state while `fresh` on exit 0,
and `override` on any exit, still advance. The edge carried no route the five
values don't already name, because the state requires evidence.

The directive is rewritten to: say the gate runs shirabe's own check; map each
exit code to the evidence value it calls for (0 `fresh`, 1
`stale_requires_introspection`, 3 or -1 `unavailable` with the reason in
`detail`, 2 `blocked` because the template passed a bad argument); tell the
agent how to re-run the check to read the JSON reasons, written in the
agent-shell form `"${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/check-staleness.sh"
--issue {{ISSUE_NUMBER}}` the way the file's other agent-run commands are
(koto substitutes `{{PLUGIN_ROOT}}` in gate commands, not in prose the agent
runs); keep `override` for an explicit instruction to skip and `blocked` for a
run that must stop; and drop the auto-advance claim. The `PLUGIN_ROOT`
variable's description adds this gate to the gates that use it. The mermaid
companion is regenerated from the compiled template.

### Tests

`skills/work-on/scripts/check-staleness_test.sh`, in the style of
`closing-keyword-gate_test.sh`:

- A `gh` stub on `PATH` serves canned issue and milestone JSON chosen by
  environment variables, and appends one line per call to a counter file.
- A throwaway git repository supplies files with and without commits after a
  chosen date.
- Script cases: fresh (exit 0, verdict fresh); each signal alone gives exit 1;
  `gh` failing on the issue call and on a milestone call gives exit 3; missing
  `jq` on a scrubbed `PATH` gives 3; bare positional and missing `--issue` give
  2; at most three `gh` calls per run; the JSON carries every signal.
- Gate cases: the gate command is extracted from the template, `{{PLUGIN_ROOT}}`
  and `{{ISSUE_NUMBER}}` substituted as koto would, and run with `sh -c`: fresh
  exits 0; stale exits 1; empty `PLUGIN_ROOT` exits 3; a `check-staleness.sh`
  that rejects `--issue`, first on `PATH`, doesn't change a fresh result.
- Engine cases, skipped when koto is absent: a copy of the shipped template
  with the gate command replaced by `exit <n>`, driven through koto to
  `staleness_check`, checks that `unavailable` advances on 3 and -1 and stays
  on 0, 1 and 2; `fresh` advances on 0 and stays on 1 and 3;
  `stale_requires_introspection` reaches `introspection`; and `override` and
  `blocked` route as before whatever the exit code, including 2.

The suite is registered in `check-work-on-scripts.yml` (both legs; the engine
cases run on Linux) and in `scripts/check-bash-floor.sh`'s work-on list.

## Implementation Approach

One pull request; the pieces are small and only meaningful together.

1. Add `check-staleness.sh` and `references/staleness-signals.md`.
2. Add `check-staleness_test.sh` with the script and gate cases, and register
   it in CI and the bash-floor runner.
3. Edit `staleness_check`: the gate command, the `unavailable` value and
   edges, the directive, the `PLUGIN_ROOT` description. Regenerate the mermaid
   companion. Add the engine cases to the test.
4. Run the work-on suites, `koto template compile`, the template checks
   (`check-template-interpolation.sh`, `check-template-directives.sh`,
   `validate-template-mermaid.sh`), and `check-skill-requires.sh`.

## Security Considerations

- **Argument handling.** `ISSUE_NUMBER` reaches the gate through koto's
  variable substitution into a shell string. The gate quotes it, and the
  script refuses anything but a positive integer before any `gh` call, so a
  crafted value can't become a flag or a command.
- **Issue body as input.** The body is untrusted text. It is read only by
  `jq`, `grep` and `sed` as data. Extracted paths that are absolute or contain
  a `..` segment are dropped; the rest go to `git log` after `--`, and only
  when `[ -f "$path" ]` holds, so a path can't be read as an option and can't
  name a file outside the working tree. No part of the body is evaluated.
- **Milestone title.** Also untrusted GitHub content. It reaches `gh` only as
  a single double-quoted argument to `--milestone`, never through a string
  built for `sh -c` or `eval`, so spaces, `$()`, backticks or a leading `-` in
  it are one opaque value to `gh`'s own parser.
- **Report content.** The JSON report includes the issue title, which is
  untrusted. It's built with `jq --arg`, so it can't break the JSON; agents
  quoting it into `detail` treat it as data, as they already do for the issue.
- **PLUGIN_ROOT.** An empty value is caught by `test -x`. A wrong value
  pointing at an attacker-controlled executable requires control of the
  `koto init` invocation, which already implies control of the session.
- **Credentials.** The script uses `gh`'s existing authentication and never
  reads or prints tokens. `gh`'s stderr is quoted only as its first line, cut
  to 200 characters, and replaced with a fixed message when it contains a
  token-shaped substring (`ghp_`, `gho_`, `ghs_`, `github_pat_`), because the
  reason can travel into evidence and from there into PR text.
- **Repository resolution.** `gh` resolves the repository from the working
  tree, as every other `gh` call in `/work-on` does. In a checkout whose
  remotes are ambiguous `gh` refuses, which reads as unavailable; in a fork
  whose default repository is set to the fork, the check reads the fork's
  issue `N`, but so does the rest of the run, so the two can't disagree.
- **No new network surface.** Three read-only `gh` API calls per run, against
  the repository the session is already working in.

## Consequences

### Positive

- An unattended issue-backed run on a shirabe-only host needs no override at
  this gate; `override` in a run's evidence means someone chose to skip.
- The staleness signal exists again for shirabe-only users, and the
  definition of "stale" is readable and testable in shirabe.
- The age check works on macOS, which the prior check's GNU `date` did not.
- The directive's false auto-advance claim is gone.

### Negative

- shirabe owns a GitHub-querying shell script and its test suite.
- The ported check keeps the prior check's noise: milestone position marks
  most milestone issues stale, so many runs will route to introspection. That
  is the prior behaviour, now visible; retuning is a follow-up issue.
- `--limit 100` on the milestone lists undercounts milestones with more than
  100 closed or open issues, as the prior check did.
- The staleness check adds up to three API calls, and some seconds, to every
  issue-backed run.
- The template edit sits in the same file as open work (#420) and touches the
  mermaid companion and the work-on CI workflow, which #420 also edits, so one
  of the two will rebase.

### Mitigations

- The signals reference names the noisy signal and the limit, so the
  follow-up has a stated starting point.
- The unavailable path means an API outage costs a recorded skip, not a
  stopped run.
