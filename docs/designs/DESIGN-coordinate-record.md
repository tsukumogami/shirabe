---
schema: design/v1
status: Planned
upstream: docs/prds/PRD-coordinate-record.md
problem: |
  `/coordinate` is prose, so the four checks it asks for (the record exists once with its
  four sections, a predecessor's deferrals are disposed of before the first dispatch, a
  verified head exists before any land step, and the CI board really ran) can each be
  skipped or satisfied by the coordinator's word, and the record is hand-written markdown
  nothing finds, renders or rewrites.
decision: |
  Carry the loop as a koto workflow: an event hub the coordinator ticks on each message,
  with a check state in front of each protected step. Every check state has no evidence to
  submit; its default action reads GitHub and prints a sealed verdict token the engine
  captures, routed by a non-overridable command gate. Every GitHub write is an agent-run
  script that re-reads GitHub and the session log first. The record is its visible tables,
  written and parsed by one codec with a byte-exact round trip.
rationale: |
  Captures are the only koto channel that carries a script's output and that no CLI verb
  lets the agent write; context keys and evidence are the agent's to write. Keeping writes
  agent-run follows shirabe's default-action rule. Visible tables keep what the checks read
  and what a person reads the same. The hub fits a loop whose input is one message at a
  time about any holding. `koto next --to` still skips gates (koto#251); a seal on each
  token and a log scan in every write script make that visible until koto fixes it.
---

# DESIGN: The coordination record and the coordinator's workflow

## Status

Planned

## Context and Problem Statement

`/coordinate` today is a prose skill: `skills/coordinate/SKILL.md` plus four references
(`loop.md`, `brief-template.md`, `verification-checklist.md`, `record-template.md`) and nine
eval scenarios. It has no koto template and no scripts. Every check it asks for is a
sentence the coordinator can skip, and the record is markdown the coordinator writes by
hand from a template.

The PRD asks for four checks that no value the coordinator supplies can satisfy: the record
exists exactly once before any dispatch (found by listing every open issue at roadmap scope,
or the rotation's draft pull request at discipline scope, never by search); the record has
its four sections; no deferral raised before the run started is undisposed when the run
first dispatches, including every deferral in a predecessor rotation's handoff; and the land
step is reachable only after the workflow itself has read the pull request's head from the
remote and found a board that really ran at that head (non-empty, finished, each non-skipped
job on a named runner with a succeeded step, every required check present and green, not
`DIRTY`), with the head re-read on entering land.

The technical problem is that koto gives shirabe three ways to decide a transition, and only
some of them resist a coordinator that wants to skip a step:

- **Evidence** the agent submits. Anything here is the agent's word.
- **Context keys** read by `context-matches` or `context-exists` gates. The agent can write a
  context key itself with `koto context add`, so a gate over a key is only as good as the
  guarantee that the key was written by the check and not by the agent.
- **Command gates** and **default actions** the engine runs. A command gate exposes only an
  exit code; a default action runs on entry, before the state's gates, and can write
  context. shirabe's rule (`references/default-action-conversion.md`) keeps any command whose
  success is an externally visible write, such as opening an issue or merging, out of
  default actions.

So the design has to put each check where the agent can't pre-empt it, keep every GitHub
write agent-run (opening, rewriting and closing the record; merges), and still carry a loop
that runs for days, is driven by cross-session messages rather than engine wakes (koto's
leg waker is a stub, koto#250), and hands most workers no koto leg at all (when this was written only `/scope`
and `/execute` accepted `--koto-leg`, shirabe#401; shirabe#407 has since added it to `/deliver`
and `/work-on`).

The record's shape is the second problem. The PRD fixes four sections with fixed columns (R14),
requires a body that parses back to the input it was rendered from, and cells that can't break a
table whatever the coordinator quotes into them. It also requires the same renderer to write the
discipline handoff file, and a find that tells apart the discipline branch's situations and a
predecessor's still-open rotation (R19).

The third is the loop itself. The PRD's pick rules (a cap of five active workers kept full,
scoping ahead, asking up when the scope runs dry, a parked bound of three) and its two shadow
deciders (pick, report classification) must sit in states whose inputs koto can gate, and
every one of the prose skill's roughly 190 rules has to land in the state that uses it.

## Decision Drivers

- **No check satisfiable by the agent's value (PRD R7-R13).** Each of the four checks reads
  GitHub itself, and the gate that routes on it can't be overridden or pre-written.
- **Every GitHub write stays agent-run (R17).** Default actions may read GitHub and write koto
  context; they may not open, edit, close or merge anything.
- **Prose rules survive (R4) and the skill file gets thin (R5).** Step guidance moves into
  states behind details markers; the four references stay and are named from the states.
- **Message-driven, no unbounded watcher (R26).** The workflow is advanced by the coordinator
  on each message or notification; any bounded wait states its deadline.
- **Deciders in shadow only (R25).** Inputs are gated context keys or variables; an automatic
  answer can't end the run or pass a confirmation; the coordinator's answer always wins.
- **shirabe CI constraints.** The template passes compile, directives (every state with
  `accepts` has a `when`), mermaid freshness, interpolation (no `$VAR` in command fields, so
  logic lives in scripts reached through a `PLUGIN_ROOT` variable), decider declarations
  (TSV rows and at least 40 fixtures per decider), the entry floor, and bash 3.2.
- **koto 0.13.0 floor.** Non-overridable gates, constrained variables and result maps need it;
  the template carries the `# koto-floor: pinned` marker.
- **Default actions run within 30 seconds and re-run on every entry.** A GitHub read in one
  must be bounded and idempotent, and must clear the keys it owns before rewriting them.
- **Offline tests (R29).** Every script is testable with stand-in `gh` and `koto` on `PATH`,
  following `/deliver`'s and `/execute`'s test harnesses.
- **Out of scope stays prose.** Dispatch tooling and mechanised reconcile are later work; the
  dispatch and reconcile states call the prose procedure.

## Considered Options

### Decision 1: How the four checks are enforced

koto offers three channels for deciding a transition: evidence, context keys read by context
gates, and commands the engine runs. Reading koto's source settled what each is worth. In one
advance the engine runs a state's default action, then (only if it succeeded) the state's
gates, then resolves transitions, with no agent turn in between; a failed action returns
before gates. The action is skipped whenever the state's current epoch holds evidence, and
`--with-data` is refused on a state with no `accepts` block. `capture_stdout_as` values are
written only by the engine, from an action's stdout; no CLI verb writes one. Context keys, by
contrast, are written by anyone who runs `koto context add`.

Two findings changed the problem. `koto next --to <target>` takes any declared edge without
evaluating the source state's gates, `overridable: false` included, and a template can't forbid
it (filed as koto#251). And one precedent isn't safe to copy: a check state that also has an
escape `accepts` block lets evidence skip the action, so an agent-written verdict key reaches
the gate. `/deliver`'s `scoped_check` and `merged_check` (no `accepts`, non-overridable gates)
are the safe shape.

Key assumptions:

- The agent acts through koto's CLI and shirabe's scripts. File edits under the session
  directory, a `gh` shim on `PATH`, or a raw `gh pr merge` defeat any koto-level check; only
  GitHub branch protection or a PreToolUse hook in the posture can prevent them.
- The paginated open-issue listing and the land head read fit the 30-second action limit.
- koto keeps its capture semantics (engine-only writer, `capture_unset` stop on an undelivered
  read, later value wins) and the session header's once-set `created_at`.

#### Chosen: Read-only check states that capture a sealed verdict token, routed by non-overridable command gates over the capture

Each check is its own state with a read-only default action and no `accepts` block, so
evidence can't be submitted and the action runs on every entry before the gates. The script
reads GitHub, writes any bulky detail to a context key as data, and prints exactly one sealed
token on stdout, delivered with `capture_stdout_as`. The state's gate is a `type: command`,
`overridable: false` gate running `coord-verdict.sh` over the substituted capture, with one exit
code per verdict and a `when` arm for each. No gate reads a context key, so a key the agent
wrote is simply ignored.

The seal ties a token to the visit that produced it. It's a consistency check, not a secret:
its hash has no key and covers only what the coordinator can read, so it proves nothing about a
token the coordinator hands a script. What makes it hold is where the token comes from. Every
agent-run script reads the capture it needs from the session log itself (the engine's
`variable_captured` event) rather than taking it as an argument. The shared helper `coord-log.sh` (the one
seal helper this feature ships and the reconcile feature reuses) reads the session log:
`coord-log.sh seal <state> <token>` prints `<token> sealed:<seq>:<sha256>`, where `<seq>` is the
sequence number of the latest entry into `<state>` and the hash covers the token, the seq and
the session name. `coord-log.sh check <state> <sealed-token>` exits 0 only when the hash matches
and `<seq>` is still the latest entry into that state. A downstream reader (land reading the
verified head, the record step reading its expectation, the merge script reading land's token)
runs the same check, so a capture left over from an earlier visit can't be carried forward by a
`--to` jump. `coord-log.sh directed-since <seq>` lists `directed_transition` events after a
sequence number. Every check script and every agent-run write script scans the whole run (from
sequence 0) and refuses when one is found, naming the event, so any directed transition blocks
every write until the coordinator restarts, which opens a new run. This is the skill's own integrity rule
for its record and merges while koto#251 lets `--to` skip gates. That's detection, not prevention: koto#251 is the defect and the
seal is the interim.

Run facts come from the engine too. The run's start is the session header's `created_at`,
which koto sets once at init; the deferral check reads it through `coord-log.sh run-start`. Each `/coordinate` invocation
opens a fresh session under a per-run name, `coordinate-<scope-slug>-<UTC stamp>`, after
cancelling (never cleaning) any live coordinate session for the same scope, so a restart is a
new run with its own start, a full start and reconcile, and the old run's log stays readable.

Land re-reads the head live. `land`'s action runs the board script's head-only read, checks the
seal on `{{VERIFIED}}`, and captures `land-ok <pr> <sha>` only when the remote head equals the
verified sha and the merge state isn't `DIRTY`. The merge itself goes through `land-merge.sh`, a coordinate-owned
wrapper: it reads land's capture from the session log, checks it against the latest entry into
`land`, scans the run for directed transitions, re-reads the posture for the merge step, and only
then calls `skills/execute/scripts/merge-exec.sh` (unchanged) with the verified sha, which merges
with `gh pr merge --match-head-commit`, so GitHub refuses a head that moved in the seconds after the
check. No directive names `merge-exec.sh` directly. The wrapper isn't a permission rule of the skill's own: it's the skill
reading the workspace's denial at the level of the step. A hook that matches the typed command
never sees a script that calls `gh pr merge` inside itself, so the wrapper asks the posture the
same question the hook would have answered.

#### Alternatives Considered

- **Context-key record scripts with non-overridable context-matches gates (the `/deliver` and
  `/execute` precedent).** Rejected because context keys are agent-writable: any key read after
  the tick that wrote it, the verified head above all, can be replaced, and even within a tick a
  background `koto context add` can race the gate. Its structure (check states with no
  `accepts`, the lint, the prediction in its own state) survives.
- **Command gates that re-derive every property at gate time.** Rejected as the whole answer
  because a command gate exposes only an exit code, so the record number, the ambiguous matches
  and the verified head can't reach the directive, the renderer or land's comparison, and a
  second GitHub read defends against no agent value while `--to` skips it anyway.
- **Context data plus re-derivation gates at the consumers.** Rejected because `--to` skips
  consumer gates exactly as it skips check states, so they close neither gap and double the
  reads. The re-check moves into the agent-run write scripts instead.
- **Attach a restart to the live session.** Rejected because it keeps the first run's start time
  and passed checks, so a restart would never re-run start, reconcile and the deferral check.
- **A fixed session name, cleaned before each init.** Rejected because cleanup deletes the old
  run's log, which R1 and the `--to` scan both need.

### Decision 2: The record body's source of truth

The PRD's checks are defined over what's on GitHub and what a person reads there: the deferral
check parses the Disposition column, and the section check asks for fixed-column tables. The
body must round-trip, and a cell must not be able to break a table.

Key assumptions:

- People rarely edit the record on GitHub, and a structural edit stopping the run with the first
  differing line named is acceptable.
- Records stay well under GitHub's 65,536-character body limit.
- GitHub renders tables per GFM: rows split on unescaped pipes before inline parsing.

#### Chosen: Visible tables are the truth, with a canonical round-trip

The rendered markdown is the only representation. One jq program,
`skills/coordinate/scripts/record-codec.jq`, holds both directions, called by `record-render.sh`
(JSON in, markdown out) and `record-parse.sh` (markdown in, JSON out). A body is valid only when
rendering its parse, stamped with the parsed `Written:` time, reproduces it byte for byte after
CRLF-to-LF and trailing-newline trimming. That comparison is the four-section check. Cells are
encoded in a fixed reversible order (`&`, `<`, `>`, backslash, pipe as `\|`, CR, LF as `<br>`,
edge whitespace), so a pipe, newline, backtick run or fence opener can't change a column count.
The renderer refuses unknown keys (with a named message for status, CI and merge-state columns),
worker values containing `/`, a UUID or 32-hex run, a `session_` prefix or only digits, and any
structured cell outside its grammar. The same codec writes the discipline handoff file, whose
reasoning section is kept verbatim and, when copying a predecessor, replaced by a fixed "not
recorded" sentence.

#### Alternatives Considered

- **A hidden JSON block as the truth.** Rejected because the visible tables a person reads and
  the check names could drift from the truth without anything noticing, and it would put a hidden
  block in a committed handoff file.
- **Both, with a consistency check.** Rejected because the check needs the full table parser
  anyway, so the block is a second copy that can disagree with the first and stops the run on a
  valid human edit.
- **Truth kept off GitHub in koto context or a local file.** Rejected because the checks must read
  GitHub, and a restart or successor would lose the state.

### Decision 3: How the board is read and judged

R10 asks whether the board at a head really ran. The live reads behind this decision, against
public repositories, found three things: a re-run attempt makes `filter=all` return the failed
earlier attempt beside the passing one, so only the default latest-attempt filter matches the
PRD; a required check that never reported appears in neither the status-check rollup nor
`gh pr checks --required`, so the required set must come from branch protection and rulesets;
and a skipped job reads `runner_name: null` with no steps.

Key assumptions:

- A read-only token can see the classic branch endpoint's required contexts and the branch rules
  endpoint; when it can't, verification ends in an error rather than a pass.
- Required checks match rollup entries by name.

#### Chosen: One bounded read script over a GraphQL snapshot, REST runs and latest-attempt jobs, a union required set, and the remote ref read last

`board-verdict.sh --repo <owner/repo> --pr <n>` makes one GraphQL snapshot (head, merge state,
every check context with `isRequired`, paginated), reads every workflow run at the head through
`actions/runs?head_sha=`, every job per run at its latest attempt (in parallel, at most six at
once), the required set as the union of classic protection, rulesets and rollup `isRequired`, and
the remote ref last so a push during the read shows as a moved head. It checks every collected
count against its reported total, matches a required check on its integration when protection or a
ruleset names one, lists any change to `.github/workflows/` in the report, stops itself at 24 seconds, and prints one JSON verdict
(`verified`, `pending`, `unverified`, or an `error:` form) with a closed set of reason codes, the
skipped jobs and the superseded attempts. `--head-only` does the snapshot's head and the ref in
about a second, for land. A typical board reads in three to four seconds.

#### Alternatives Considered

- **The checklist's porcelain reads.** Rejected because `gh run list` stops at 20 runs with no
  total, `gh pr checks` reads the current head rather than the verified one and misses a required
  check that never reported, and `filter=all` invites judging the wrong attempt.
- **Rollup-only judgement.** Rejected because the rollup has no runner name and no step
  conclusions, so a job whose steps were all skipped reads green, which is the case R10 guards.
- **Reads split or cached across states.** Rejected because a split read stops being one snapshot
  at one head, and a cache in context is a key the coordinator can write.

### Decision 4: The loop's state-machine shape

The coordinator's input is one message at a time, about any of its holdings, in any order.
koto can't pass through the same state twice in one advance, re-delivers details on every
arrival, and keeps the whole session log, parsed on every advance.

Key assumptions:

- A run stays well under 20,000 log events (estimated worst case about 8,000 for a seven-day
  rotation at the cap).
- Shadow answers are recorded only where a user opted in to deciders; the coordinator's own
  answer is always in the session log.

#### Chosen: An event hub in one session per run, with a check state in front of each protected step and a record-confirm funnel back to pick

After a linear start and record phase, `wait` is a hub with no action, gate or details, ticked on
every message and routing on the event the coordinator names. Every edge out of `wait` lands on a
state that starts with a GitHub read, so a `--to` out of the hub skips nothing. Every spoke that
changes what the record must hold returns only through `record`, whose action re-reads the record
from GitHub and whose gate holds until the expected change shows. From `record` the loop goes
round through `pick_facts` and `pick`, which dispatches until the cap is full and then returns to
`wait`. The two shadow deciders sit at gate-free evidence stops (`pick`, `classify_report`) fed by
context keys that the state just before writes and gates.

#### Alternatives Considered

- **A linear cycle.** Rejected because `wait` must route on the event anyway, so a compiling
  ring is this hub with reconcile and the deferral check spliced into every return path, at more
  log per lap.
- **A parent session with one child per holding.** Rejected because `--parent` children lose
  their logs when they finish, which R1 forbids, and a wait on every child stalls the cap on the
  slowest unit.
- **A run session plus a session per event.** Rejected because run facts passed as variables can
  be forged, and reading them from the run session is a cross-session read of context the agent
  can write.

### Decision 5: The discipline lifecycle and the close-outs

The discipline find has more outcomes than the roadmap find, and the close-outs mix reads,
GitHub writes and judgment.

Key assumptions:

- GitHub's git-data and contents APIs are an acceptable way to make the record branch's commits
  (they skip local hooks).
- A roadmap feature's status is its `**Status:**` line under `## Features`.

#### Chosen: Read scripts as check-state actions, three agent-run write scripts that re-read GitHub first, `merge-exec.sh` reused, judgment in prose

`record-find.sh` reports one of `found`, `predecessor` (open record past its end date), `foreign`
(an open pull request without the declaration line), `ambiguous`, `stale-branch` (last pull
request merged or closed), `unopened` (a branch that never had a pull request, what a crash
between push and open leaves), `none`, or an error. `predecessor-handoff.sh` renders a
predecessor's handoff from its body. `closeout-read.sh` reports the stage of a rotation or roadmap
close-out. The writes are `record-open.sh`, `record-write.sh` (whole body, `--end` to correct the
title, `--close` at roadmap scope) and `rotation-close.sh` (`--step handoff|ready|delete-branch`),
each refusing when a fresh read disagrees. The merge is `skills/execute/scripts/merge-exec.sh`,
unchanged, behind the `land-merge.sh` wrapper, so shirabe keeps one `gh pr merge` caller. The
declaration line alone isn't authority, because anyone can open an issue or pull request in a
public repository: the find accepts a candidate only when its author and its last editor have
write access to the host repository, and reports any other declared candidate without adopting
it. That still lets a successor under another login adopt the record. This is an authorization read on
GitHub data, made before adopting a record as the run's truth. It's distinct from the rule that the
skill never scrutinises who sent it a message: who may message a session stays the harness's and the
workspace's to decide. The predecessor's close-out
is split the same way as everything else: `predecessor-handoff.sh` is the read, and every commit,
ready and merge in the ladder is an agent-run step.

#### Alternatives Considered

- **One lifecycle script that finds and acts, gated by exit code.** Rejected because the find
  would be the agent's to run and a command gate loses the outcome.
- **Read scripts only, with writes as literal commands in prose.** Rejected because hand-typed
  titles and multi-step re-cuts drift or stop half-done, and nothing re-reads GitHub first.
- **Local git writes.** Rejected because the coordinator usually has no checkout of the host
  repository, and a leftover local branch is state the find can't see.

## Decision Outcome

The five decisions fit together as one rule: the workflow reads, the coordinator writes, and
nothing the coordinator writes is read by a check. Every check is a state with no `accepts`
whose default action reads GitHub and prints a sealed token the engine captures; a
non-overridable command gate routes on it the same advance. Every GitHub write is a script the
coordinator runs from a directive, and each re-reads GitHub and the session log before it acts.
The record is the visible tables, parsed and rendered by one codec, so what the checks read is
what a person reads. The loop is a hub that routes one event at a time into spokes, and the only
way back from a record-changing spoke is through a state that confirms the change on GitHub.

Three reconciliations were made across the decisions:

- Decisions 4 and 5 were written against context-key gates; both move to decision 1's sealed
  captures. The context keys they named stay as data for directives, reports and deciders.
- Decision 4 had no Return path column; the PRD now carries one (`leg <request-id>:<leg>` or
  `message`), which the dispatch path fills and reconcile reads. This feature adds no request-leg
  gate: binding one at dispatch is the dispatch path's work, whichever entry point
  accepts it (all four do since shirabe#407 closed shirabe#401). The `wait` guidance says
  which is which.
- Leg names stay fixed, one request per worker (from shirabe#407). A skill that answers a leg
  answers exactly one (`/deliver` answers `deliver`, `/work-on` answers `work-on`), so the
  coordinator opens one request per dispatched worker and records it in Return path as
  `leg <request-id>:<leg>`. The other choice was letting the skills accept any leg name and relying
  on koto's template and input check; a worker never answers two legs, so that widens the input
  every skill must validate and buys nothing. Fixed names also make a Return path readable
  without the request in hand.
- Decision 1 ran the deferral check only before the run's first dispatch; decision 4 ran it before
  every dispatch. Both hold: `dispatch_check` runs before every dispatch and always checks that no
  record row raised before the run started is undisposed, but it compares the predecessor's handoff
  only until the session log shows the check passed once in this run, because disposed rows drop
  out of the record at the first rewrite after the first dispatch.

## Solution Architecture

### Files

```
skills/coordinate/
  SKILL.md                         thin contract: flags, open, tick, report, final states
  requires.tsv                     koto floor, gh, git, jq, date, awk, sha256sum or shasum
  koto-templates/
    coordinate.md                  the workflow
    coordinate.mermaid.md          generated companion
    coordinate.pick.choice.decider.jsonl
    coordinate.classify_report.classification.decider.jsonl
  references/                      loop.md, brief-template.md, verification-checklist.md,
                                   record-template.md (updated, not removed)
  scripts/
    coordinate-open.sh             args to variables; host at roadmap scope; cancel earlier
                                   live run of the scope; fresh per-run session
    coordinate-report.sh           report from the terminal result, closed patterns
    coord-log.sh                   shared seal helper, log scans, run facts, provenance
    coord-verdict.sh               gate helper: capture -> exit code, seal checked
    record-codec.jq, record-render.sh, record-parse.sh
    record-find.sh                 check: find the record, author authority, four sections
    record-open.sh                 agent-run: open exactly one record
    record-write.sh                agent-run: whole-body rewrite, --end, --close
    record-holding.sh              agent-run: add, update or read one holding row by topic
    record-confirm.sh              check: the change the source step implies is on GitHub
    start-check.sh                 check: roadmap exists and reads Active
    posture-read.sh                check: merge, close, teardown -> permit|deny|confirm|unread
    pick-facts.sh                  check + data: route token, coord/pick.json
    deferral-check.sh              check: record once, pre-run deferrals disposed, cap
    report-facts.sh                check + data: holding by topic, scope and branch, report.json
    board-verdict.sh               board read (JSON)
    board-record.sh                check: board-verdict.sh -> sealed token, board.json
    land-check.sh                  check: head re-read against the unit's verify capture
    land-merge.sh                  agent-run: capture from the log, posture, merge-exec.sh
    merge-confirm.sh               check: merged, default-branch blobs vs the verified head
    merged-facts.sh                check: a person's merge of a parked pull request
    quiet-check.sh                 check: quiet and silent workers from the log
    predecessor-handoff.sh         check: render a predecessor's handoff
    closeout-read.sh               check: the next close-out stage
    rotation-close.sh              agent-run: --step handoff|ready|delete-branch
    <each>_test.sh, testdata/      stand-in gh and koto, fixtures, rule-coverage.tsv
```

### Variables

`SCOPE` (`roadmap` or `discipline`), `ROADMAP` (a `docs/roadmaps/.../ROADMAP-*.md` path, empty at
discipline scope), `DISCIPLINE` (`^[a-z0-9][a-z0-9-]*$`, empty at roadmap scope), `HOST_REPO`
(`owner/repo`), `ROTATION_DAYS` (default 7), `CAP` (default 5), `PARKED_BOUND` (default 3),
`PLUGIN_ROOT`. None is rebindable, because every invocation opens a fresh session.

The opener sets `HOST_REPO` at roadmap scope from the repository it runs in (the roadmap's own
repository, per the record's container rule). At discipline scope it takes `--host owner/repo`;
without one it opens no session and prints one question for the human with a recommendation,
never defaulting to the repository it runs in. So "ask once" happens before any session exists,
and the answer comes back as the next invocation's argument, which koto's pattern checks. Free
text after the scope isn't a variable: it reaches the coordinator as its decisions and changes no
setting the workflow enforces.

### The check-state contract

Every check state has a default action and no `accepts` block. Its script exits 0 only when it
reached a definite verdict, printing one line, `<verdict> <args> sealed:<seq>:<sha256>`, which the
engine captures; it exits non-zero when a read failed, which takes koto's action-failure path (no
gates evaluated; the fallback says to tick again, and the state re-runs the read). Its gate is one
`type: command`, `overridable: false` gate running `coord-verdict.sh <state> "{{CAPTURE}}"`, which
checks the seal and exits with the verdict's code; each code has its own `when` arm, and a verdict
with no arm (such as "not yet") leaves the state gate-blocked for the coordinator to act and tick
again. Data a later evidence state or a decider needs goes to a context key as data; a
`context-exists` gate on that key sits beside the command gate and every arm repeats it, which is
what the decider-input rule asks for.

Every return to a check state passes through an evidence stop first, so no advance can enter the
same state twice (koto's "cycle detected").

`coord-log.sh` is the one helper every script uses to read the session:

- `seal <state> <token>` and `check <state> <sealed-token>`: the seal described under Decision 1.
- `capture <name> [--for <key>]`: the latest engine-written capture of that name, or the latest
  whose token names `<key>` (a pull request number, for per-unit reads), with the seq it was
  sealed against checked against that state's entry events.
- `directed-since <seq>`: `directed_transition` events; write scripts pass 0.
- `run-facts`: `{scope, name, repo, ref}` from the session's init variables and its latest
  `RECORD_FIND` capture; exits non-zero when the run has no found record.
- `run-start`: the header's engine-written `created_at`.
- `provenance`: exits non-zero unless the header's template hash equals the hash of the template
  the opener compiled for this plugin root, and `PLUGIN_ROOT` resolves to the directory the
  calling script lives in.
- `live-session <scope-slug>`: the one live coordinate session for the scope, so a write script
  finds its session itself rather than trusting a `--session` pointed at an older run's log.

### States

Start and record phase:

| State | Kind | Routes |
|---|---|---|
| `start` | check: `start-check.sh` (roadmap scope: the roadmap on the host's default branch reads Active; discipline scope: always `discipline`) | active, discipline -> `start_posture`; `not-active` -> `done_not_active` |
| `start_posture` | check: `posture-read.sh`, read-only, never runs a hook | any verdict -> `record_find` (the verdict stays in its capture for land and the close-outs) |
| `record_find` | check: `record-find.sh` (a title or branch match without the declaration line is `foreign`) | `found` -> `reconcile`; `none`, `stale-branch`, `unopened` -> `record_open`; `foreign`, `ambiguous`, `malformed`, `unauthorized` -> `record_conflict`; `predecessor` -> `predecessor_handoff` |
| `record_open` | evidence `opened` after `record-open.sh` | -> `record_find` |
| `record_conflict` | evidence `recheck` or `stop` | -> `record_find` or `done_stopped` |
| `predecessor_handoff` | check: `predecessor-handoff.sh` | `rendered` -> `predecessor_close`; `unparseable` -> `record_conflict` |
| `predecessor_close` | check: `closeout-read.sh --predecessor` | `handoff-missing`, `land` -> `predecessor_step`; `merged` -> `predecessor_done`; `closed-unmerged` -> `record_conflict` |
| `predecessor_step` | evidence `done` after the stage's agent-run step (`rotation-close.sh`, `land-merge.sh --closeout`) or `handed_over` | done -> `predecessor_close`; handed_over -> `predecessor_handed_over` |
| `predecessor_done` | evidence `recheck` after `rotation-close.sh --step delete-branch` | -> `record_find` |
| `predecessor_handed_over` | evidence `recheck` | -> `record_find` |
| `reconcile` | evidence `reported`; guidance is `references/loop.md`'s full reconcile; a non-overridable command gate over the posture capture | readable -> `pick_facts`; unread -> `posture_ask` |
| `posture_ask` | evidence per finishing step, `held` or `reserved` (default reserved) | -> `record`, which confirms the Reversals row recording the human's answer |

The turn:

| State | Kind | Routes |
|---|---|---|
| `pick_facts` | check + data: `pick-facts.sh` prints `pick`, `scope-complete` or `rotation-over`; writes `coord/pick.json` (units in order with blocked and blocker-landed flags, holdings with phase, active and parked counts) | `pick` -> `pick`; `scope-complete` -> `roadmap_close`; `rotation-over` -> `rotation_close` |
| `pick` | evidence `choice: dispatch, scope_ahead, send_execution, ask_up, hold` with a shadow decider over `coord/pick.json`, `CAP` and `PARKED_BOUND`; optional `unit` | dispatch, scope_ahead, send_execution -> `dispatch_check`, writing `dispatch_topic` from `unit`; ask_up -> `ask_up`; hold -> `wait` |
| `ask_up` | evidence `sent` | -> `wait` |
| `dispatch_check` | check: `deferral-check.sh` (record found once with four sections; no deferral raised before the run start undisposed; the predecessor's committed handoff file, read from the host's default branch, compared until the first pass in this run; the cap and parked bound, where `send_execution` doesn't add an active worker; a `dispatch` or `scope_ahead` topic a Holdings row already names is refused, since worker session names are machine-wide); passes `dispatch_topic` through | ok -> `dispatch`; `deferral-open` -> `deferral_dispose`; `record-changed` -> `record_find`; `at-cap` -> `wait`; `duplicate-topic` -> `pick_facts` |
| `deferral_dispose` | evidence `rewritten` after `record-write.sh` | -> `dispatch_check` |
| `dispatch` | evidence `sent` or `failed`, `topic`; the dispatch path fills its procedure | sent -> `record`; failed -> `failure` |
| `record` | check: `record-confirm.sh`, which reads the source state and its evidence from the log and checks the change it implies (below) | confirmed -> `pick_facts`; a `--to` in the run or an unconfirmable change -> `record_conflict` |

The hub and its spokes:

| State | Kind | Routes |
|---|---|---|
| `wait` | evidence `event: report, quiet, decision, deferral, merged, retire, end`, optional `unit`; no action, gate or details | report -> `report_facts`; quiet -> `quiet_check`; decision, deferral -> `decision_apply`; merged -> `merged_facts`; retire -> `teardown`; end -> `rotation_close` when `DISCIPLINE` is set, else `done_stopped` |
| `report_facts` | check + data: `report-facts.sh` finds the holding by topic; refuses a pull request outside the scope's repositories, a cross-repository head, or a head branch that differs from the Branch cell (skipped only while Branch and Pull request are both empty); writes `coord/report.json` | found -> `classify_report`; unknown or refused -> `wait` |
| `classify_report` | evidence `classification: done, blocked, needs_fix` with a shadow decider over `coord/report.json` | done -> `verify`; blocked -> `surface`; needs_fix -> `rebrief` |
| `rebrief` | evidence `sent`; the dispatch path fills it | -> `wait` |
| `verify` | evidence: the prediction (R12) | -> `verify_board` |
| `verify_board` | check: `board-record.sh` (refuses unless the log shows the prediction since the last arrival at `verify`); writes `coord/board.json` | verified -> `verified_confirm`; unverified -> `failure`; pending -> `wait` |
| `verified_confirm` | check: `record-confirm.sh --verified`, the holding's Verified head equals the unit's verify capture; blocks until the coordinator writes it, so it is where the verify report is written | confirmed -> `land`; `moved` (the remote head changed meanwhile) -> `verify` |
| `land` | check: `land-check.sh` (the unit's verify capture, head re-read, posture) | `permit` -> `land_merge`; `deny`, `confirm` -> `surface`; `moved` -> `verify`; `dirty` -> `failure` |
| `land_merge` | evidence `attempted` or `failed` after `land-merge.sh` | attempted -> `merge_confirm`; failed -> `failure` |
| `merge_confirm` | check: `merge-confirm.sh` | merged, unconfirmed -> `record` |
| `merged_facts` | check: `merged-facts.sh`, for a pull request a person merged after a hand-over: the unit's own verify capture from the log, the pull request's state and the default branch's blobs | merged, unconfirmed -> `record`; not merged -> `wait` |
| `surface` | evidence `surfaced: merge_table` or `surfaced: blocker` | merge_table -> `record`; blocker -> `wait` |
| `teardown` | evidence `done` or `kept`; prose inventory rules; the dispatch path extends it | -> `record` |
| `quiet_check` | check: `quiet-check.sh` sweeps every holding; silent counts come from the log | nothing -> `wait`; first silence -> `status_message`; second -> `failure` |
| `status_message` | evidence `sent` | -> `wait` |
| `failure` | evidence `redispatch` or `escalate`; never tears down | redispatch -> `dispatch_check`; escalate -> `wait` |
| `decision_apply` | evidence `reversal`, `deferral` or `none` | reversal, deferral -> `record`; none -> `pick_facts` |

What `record-confirm.sh` checks, by the state the run came from: after `dispatch`, a Holdings row for
the dispatched topic; after `surface: merge_table`, the unit's row with its verified head; after
`merge_confirm` or `merged_facts` reading merged, no Holdings row for the unit, and reading
unconfirmed, a Side effects row for its pull request with the verified head; after `teardown`, no
Holdings row for the topic when `done`, and only the newer `Written:` time when `kept`; after `decision_apply` or `posture_ask`, a Reversals or
Deferrals row added since the event. Every case also needs a `Written:` time later than the event.

Close-outs:

| State | Kind | Routes |
|---|---|---|
| `roadmap_close` | check: `closeout-read.sh --scope roadmap` | `ready` -> `roadmap_close_step`; `features-open`, `holdings`, `side-effects`, `deferrals` -> `roadmap_blocked`; `closed` -> `done` |
| `roadmap_blocked` | evidence `noted` (the blocker is named in the directive) | -> `wait` |
| `roadmap_close_step` | evidence `closed` after `record-write.sh --close`, or `handed_over` | closed -> `roadmap_close`; handed_over -> `done_handed_over` |
| `rotation_close` | check: `closeout-read.sh --scope discipline` | `handoff-missing`, `title-stale`, `land` -> `rotation_step`; `merged` -> `rotation_done`; `closed-unmerged` -> `record_conflict` |
| `rotation_step` | evidence `done` after the stage's agent-run step (`rotation-close.sh --step handoff`, `record-write.sh --end`, or `rotation-close.sh --step ready` then `land-merge.sh --closeout`), or `handed_over` | done -> `rotation_close`; handed_over -> `done_handed_over` |
| `rotation_done` | evidence `deleted` after `rotation-close.sh --step delete-branch` | -> `done` |

Terminals: `done`, `done_handed_over`, `done_stopped` and `done_not_active`, each with
a `result:` map `coordinate-report.sh` renders.

`closeout-read.sh` reports `land` for a rotation's record pull request only when `board-verdict.sh`
verifies the board at its head after the handoff commit, and `land-merge.sh --closeout` merges that
head, so the record's own merge meets the same bar as any unit's.

Posture is named only in `start_posture`, `reconcile`, `posture_ask`, `land*`, `surface`,
`teardown` and the close-outs. When the posture was unreadable, `land-check.sh` treats a step the
human said the coordinator holds as `permit` only when the Reversals row recording that answer is
on GitHub, and as `confirm` otherwise. `land-check.sh` and `land-merge.sh` re-read the posture
rather than trusting the start's read: R6 bounds each finishing step by the workspace's declared
posture, and a posture tightened during a run should apply at once. The re-read can only narrow
what the start read allowed, never widen it.

A restart is a new run, so its deferral check compares the predecessor's handoff again; deferrals
the previous run filed or closed have already dropped out of the record, and the coordinator
re-adds each with its disposition before the run's first dispatch. The `dispatch_check` directive
says so.

Reference pointers: `references/loop.md` from `reconcile`, `pick`, `quiet_check`, `failure` and
`decision_apply`; `references/brief-template.md` from `dispatch`, `rebrief` and `failure`;
`references/verification-checklist.md` from `verify` through `merged_facts`;
`references/record-template.md` from every record and close-out state.

### Seams for the dispatch path and reconcile

The dispatch path fills `dispatch`, `wait` and `rebrief`, adds its leg-reading and report-taking
states beside `report_facts`, writes the `worker_report` key (which it adds as a second input to
`classify_report`'s decider, gated where it's written), and extends `teardown` with its sealed
inventory (through `coord-log.sh`) and the states after it. This feature owns `classify_report` and
the prose `teardown`; the dispatch path extends both and duplicates neither. `pick` writes
`dispatch_topic` on its edge to `dispatch_check`, which passes it through to `dispatch`. Reconcile
hardens `reconcile` and reuses `coord-log.sh`. Every holding row changes only through
`record-holding.sh`:

```
record-holding.sh --session <s> --topic <dispatch-topic> --row-file <json>
record-holding.sh --session <s> --topic <dispatch-topic> --read
record-holding.sh --session <s> --list
```

The session gives it the scope, name, repository and record number (`coord-log.sh run-facts`); the
explicit `--scope --name --repo --ref` flags exist for tests only. The write reads the live body,
parses it, replaces the row whose Worker equals `--topic` or appends one, drops deferrals already
filed or closed when the log shows a dispatch in this run, renders, self-checks and writes the
whole body. The row file holds the Holdings keys (`unit, entry_point, mode, phase,
dispatch_status, return_path, worker, repo, branch, verified_head, dispatched, pull_request`); its
`worker` must equal `--topic`. `--read` prints the row as one compact JSON object; `--list` prints every Holdings
row, in record order, as a JSON array (empty when there are none). Exit codes: 0
written or printed, 1 no row for the topic (`--read` only), 10 refused because the target isn't an
open record, the session fails `coord-log.sh provenance`, or the run log shows a directed
transition, 11 the write failed, 2 a read failed, 64 usage, 65 the row was refused by the renderer
(the reason on stderr).

### Record format

Holdings: Unit, Entry point, Mode, Phase, Dispatch status, Return path, Worker, Repo, Branch,
Verified head, Dispatched, Pull request. Deferrals: Deferral, Reason, Raised, Disposition. Side
effects in flight: Action, Target, Verified head, Attempted, How to confirm. Reversals: Date,
Reversed, Now, Reason, From, where Date is `YYYY-MM-DDTHH:MMZ` so "added since the event" can't be
met by an earlier reversal the same day. Phase is `scoping-ahead`, `executing` or `held` (a verified pull request whose merge the human
directed held although the workspace permits it; `merge: held` at land_merge routes to surface); Dispatch status is
`dispatching`, `dispatched` or `dispatch-failed`; Return path is `message` or
`leg <request-id>:<leg>`; Branch is empty until known; Raised, Attempted and a carry-forward's
time are `YYYY-MM-DDTHH:MMZ`; Disposition is empty, `filed #<n>`, `closed: <text>` or
`carried <time>: <text>`. A discipline rotation's handoff is committed to
`docs/disciplines/<name>.md` on the host's default branch, which is where the next rotation's
deferral check reads it.

### Data flow of one report

A worker messages that its pull request is ready. The coordinator ticks `wait` with
`event: report, unit: <topic>`. `report_facts` finds the topic's holding in the record, checks its
repository and branch, and writes `coord/report.json`; `classify_report` takes the coordinator's
classification (the shadow decider records its own; `blocked` goes to `surface`, `needs_fix` to
`rebrief`); `verify` takes the prediction; `verify_board` reads the board and captures
`verified <pr> <sha> sealed:...`; the coordinator writes that sha into the holding with
`record-holding.sh`; `verified_confirm` sees it on GitHub; `land` re-reads the head and routes by
the posture; `land_merge` runs `land-merge.sh`, or `surface` hands the merge-order table over;
`merge_confirm` (or, after a person merges, `merged_facts`) and `record` confirm the outcome on
GitHub; `pick_facts` and `pick` refill the freed slot.

## Implementation Approach

The order follows dependency: the codec and the log helper are read by everything else, the
template skeleton proves the koto behaviour the rest relies on before any check is built on it,
and the template's full states come last because they name every script.

1. **Codec and CI.** `record-codec.jq`, `record-render.sh`, `record-parse.sh` and tests (the round
   trip, the refusals, the handoff format); `references/record-template.md` updated to the new
   columns; a `check-coordinate-scripts.yml` workflow that runs every `_test.sh` from the start;
   `requires.tsv` grows with each phase's scripts, so preflight passes at every step.
2. **Log helper and a skeleton template.** `coord-log.sh` and `coord-verdict.sh`, tested against a
   three-state skeleton template driven by real koto: a capture delivered to the same state's gate
   in one advance, seal sequence numbers, a blocked stop on an unrouted verdict, the
   `directed_transition` event a `--to` writes, and the provenance check.
3. **Record find, open, write, holding, confirm; start and posture.** `record-find.sh` (both scopes,
   every discipline outcome, the author-authority read failing closed), `record-open.sh`,
   `record-write.sh`, `record-holding.sh`, `record-confirm.sh`, `start-check.sh`, `posture-read.sh`,
   with a stand-in `gh` that serves 150 open issues and fails any search path.
4. **Board, land and merges.** `board-verdict.sh`, `board-record.sh`, `land-check.sh`,
   `land-merge.sh`, `merge-confirm.sh`, `merged-facts.sh`, one fixture per PRD board criterion.
5. **Close-outs.** `predecessor-handoff.sh`, `closeout-read.sh`, `rotation-close.sh`.
6. **Turn and spokes.** `deferral-check.sh` (after the handoff reader it compares against),
   `pick-facts.sh`, `report-facts.sh`, `quiet-check.sh`.
7. **Template and skill.** `coordinate.md` and its mermaid companion, decider fixtures and
   declaration rows, `coordinate-open.sh`, `coordinate-report.sh`, the thin `SKILL.md`, the
   reference updates (the cap in the bounds; the invariant that a koto session binds to the
   directory it starts in, so a worker starts it where it will work, in `brief-template.md`), the
   rule-coverage fixture, a hygiene test over added files, and structure and engine tests.
8. **Packaging.** The koto records in `requires.tsv`, the entry-floor workflow's lists, the retention adopters row, and
   the evals (the nine kept and tightened per shirabe#403, plus the new scenarios).

## Security Considerations

The workflow reads GitHub with the coordinator's own `gh` credentials and never writes on its own. Every
default action and gate runs a read-only script; a structure test fails if a write script appears in either, if a
check script calls `gh api` without `--method GET` or sends a GraphQL mutation, or if a directive names
`merge-exec.sh` rather than the coordinate merge wrapper. Every GitHub write is a script the coordinator runs,
and each re-reads GitHub and the session log first, refusing when the read disagrees or when the log shows any
`koto next --to` in the run.

**Who can speak for the record.** In a public host repository anyone can open an issue or pull request, so the
declaration line alone isn't authority. The find accepts a candidate only when its author and last editor have
write access to the host repository; others are reported and ignored. Before a holding's pull request is
verified, its repository must be one of the scope's repositories and its head branch must match the holding's
Branch cell. This keeps a planted record or row from steering a merge.

**Text from GitHub and workers is data.** Issue bodies, job and check names, pull request titles and worker
reports are parsed into JSON or cell-encoded, never evaluated and never used to build a command. Captured tokens
follow an anchored grammar (verdict, number, sha, closed reason code) checked when printed and again at the gate,
so nothing from GitHub reaches a command line through a capture. Free text shown to the coordinator is stripped of
control characters, length-capped and labelled with its source, and the guidance says a report or job name never
changes a route. That lowers but doesn't remove the risk of instructions hidden in such text reaching the
coordinator.

**The posture.** The posture is read from the workspace and instance `.claude/settings.json` and hook scripts,
located from niwa's instance metadata, never from a cloned repository. Files are parsed, never executed; a hook the
reader can't classify makes the step reserved. Because Claude Code's permission rules match the command the agent
types, a rule on `gh pr merge` doesn't cover a script that calls it; the posture reader treats rules on `gh pr merge`,
on `merge-exec.sh` and on the merge wrapper as one step, and the wrapper re-reads the posture before merging. When
the posture can't be read, the human's answer to the one question about which steps the coordinator holds arrives
through the coordinator; it's recorded in the record's Reversals table with the human as its source, so it's
auditable, and it's the one posture fact the workflow takes on the coordinator's word.

**`--to` is detected, not prevented.** `koto next --to` takes a declared edge without the source state's gates
(koto#251). Check states capture a token tied to the log's latest entry into that state; agent-run scripts read that
capture from the log rather than taking it as an argument, and any `directed_transition` in the run makes every
write script refuse until the run restarts. A coordinator acting outside koto's CLI (editing session files, shimming
`gh`, calling `gh pr merge` directly) isn't stopped by the template; GitHub branch protection and the workspace's
own hooks are what stop that.

**What's public.** The record and the discipline handoff file are public in a public host repository. When the host
is public, the renderer refuses a repository-naming cell (Repo, Pull request, Target) for a repository that isn't
public, and refuses session ids, koto session names, instance names and paths in the Worker cell. Free-text cells
(deferral reasons, dispositions, reversal reasons, the handoff's reasoning) rely on guidance to keep private names out.
No script prints a credential: scripts don't trace or echo the environment, and `gh` error text written to context is
capped and scrubbed of token patterns. koto context holds private repository names and worker text, so whoever can read
the session's context store can read those.

**Where the session came from.** Every write script trusts the session log it reads, so it first
checks the session's provenance through `coord-log.sh provenance`: the header's template hash must
equal the template the opener compiled for this plugin root, and `PLUGIN_ROOT` must resolve to the
scripts' own directory. It finds the live session for the scope itself rather than trusting a
`--session` pointing at an older run's log. A session started from an edited copy of the template,
or pointed at stand-in scripts, is refused by every write. Scripts call their siblings from their
own directory, never from `PATH`.

**Fork heads and failed reads fail closed.** `report-facts.sh` refuses a pull request whose head
is in another repository, and `record-find.sh` does the same for a discipline record. When the
write-access read for a record candidate fails, the candidate isn't adopted. A `filed #<n>`
disposition must name an issue that exists in the host repository, and a record body over
GitHub's size limit is refused before parsing. A change under `.github/workflows/` or
`.github/actions/` is a fixed reason code, `workflows-changed`, in the verify report and again at
`land`.

**Residual.** The board check proves a board ran at the head, not that it tested the right thing: a pull request's own
workflow files decide its jobs. Required checks are matched on their integration when protection names one, and a pull
request that changes workflow files is named in the verify report, but a required check matched by name alone can be
satisfied by any job with that name. Holding a pull request that changes workflows for a person would be a permission
rule of the skill's own, which it doesn't carry; the workspace's posture and branch protection decide it. `--match-head-commit` pins the pull request's head, not the merged tree: when the base moved and
branch protection doesn't require branches to be up to date, the tree that merges is one CI never
saw. With an unreadable posture, an unattended merge rests on the coordinator's relay of the
human's answer, recorded in Reversals. The coordinator's `gh` credentials are usually broader than
the run needs; a
fine-grained token limited to the host and unit repositories narrows what a mistaken or misled merge can reach.

## Consequences

**Positive.** Each of the four checks is a read the coordinator can't answer for; a restart finds
the record it has; the record reads the same every time and a successor can parse it; the
dispatch path and reconcile have fixed seams and one shared helper to build on.

**Negative.** The template is large (about forty states) and the scripts are many. Authors have
to remember that a check state takes no evidence, that a gate never reads context, and that a
capture is one line. A `--to` is detected, not prevented, until koto#251 is fixed. A check reads
through the tools on the coordinator's `PATH`, and an exported shell function reaches every bash a
check starts, so a coordinator that rewrites its own tools, or a shim left first on `PATH`, can answer a check
(koto#261). The checks don't defend against that, and prefixing one interpreter call with `bash -p`
wouldn't either while `PATH` is the coordinator's. A restart
resets the quiet-worker counts, which errs toward one more status message.

**Mitigations.** A structure test lints every check state (no `accepts`, non-overridable command
gates only, no context gate) and fails if a write script appears in any default action or gate;
an engine test walks every event arm from `wait` against the stand-in and fails on a
`template_error`; the run report prints the session's event count so a growing log is visible.
