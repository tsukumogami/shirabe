---
schema: design/v1
status: Proposed
problem: |
  A coordinator starts its successor through the worker dispatch path, which
  needs a unit pick can hand out and recognizes a successor only by a
  roadmap positional. A manager lane whose only open unit owes a verdict, or
  a run with no open unit, can't dispatch its successor, and a discipline
  director's successor brief renders --role manager, because the brief can't
  carry --discipline and --host and the successor test never matches a
  discipline run.
decision: |
  A new --successor mode of dispatch-worker.sh, run by the coordinator from
  the wait hub (or rotation_end), reads no pick facts and checks no unit. It
  builds the invocation from the run's own facts (the roadmap path, or
  --discipline and --host) with --role from the record's Run role row, and a
  script-only successor render field lets the brief carry the discipline
  shape. A pending successor is one Run row, successor, written dispatching
  before the launch, settled by reconcile and by a re-run as a worker's
  holding is, and cleared by the successor's own takeover or rotation carry.
  The mode refuses role words in the coordinator's text, so the invocation
  line is the brief's only role line.
rationale: |
  Running outside the template keeps its structure, and so compat 2, intact:
  any new pick choice, event or state would force compat 3 and make every
  running predecessor's successor fail takeover, the very handover this
  fixes. Deriving the scope from the run's facts makes own-ness, the
  discipline invocation and the refusal of another scope one mechanism. A
  Run row travels with every continuation and no Holdings reader sees it,
  so the successor never holds itself.
upstream: docs/prds/PRD-coordinate-successor-role.md
decision_provenance: inline-resolved
---

# DESIGN: Coordinator successor dispatch with its role

## Status

Proposed

## Context and Problem Statement

A coordinator starts every other session through one script,
`skills/coordinate/scripts/dispatch-worker.sh`, and reaches that script
through one stretch of the coordinate template: `pick_facts` lists the
units, `pick` chooses one and writes its topic as `dispatch_topic`,
`dispatch_check` (`deferral-check.sh`) checks the topic, and `dispatch`
waits until `holding-recorded.sh` sees the holding row the script wrote
ahead as `dispatching`. A successor coordinator goes down the same path as
a worker would: a brief whose entry point is `coordinate` and whose grant
is `own`. Nothing in the template is about handing over. The path was
built for workers, and three of its checks are wrong for a successor.

**The unit gate.** A new dispatch must name a unit `pick_facts` listed in
this pass. `dispatch-worker.sh` reads `coord/pick.json` and exits 10 when
that unit's milestone owes a verdict (`verdict_owed`), a pause holds it, or
a decision parks it. `render-brief.sh --units` then refuses a unit pick
didn't list, and `dispatch-common.sh`'s `dc_unit_forms` gives a
verdict-owed or landed unit no form at all. When no unit is open,
`pick-facts.sh` returns `scope-complete` or `rotation-over` and the
template never reaches `pick`. So a manager lane whose only open unit
owes a verdict can't start its successor (#1862), and neither can a run
with nothing open. The PRD's R2 asks that no unit state blocks a
successor dispatch (an owed verdict, a pause, a parked decision, or no
open unit at all) while every one of those refusals keeps holding worker
dispatch.

**The successor test.** `input_role` in `dispatch-worker.sh` decides
whether a `coordinate` brief starts this run's successor by deriving the
scope slug of the brief's first positional as a roadmap
(`coord-log.sh slug --scope roadmap`) and comparing it with the slug in
this run's session name. Only then is the brief's role the record's Run
`role` row; any other `coordinate` brief is a new lane and gets `manager`.
A discipline run's slug is `discipline-<name>` and it was opened with
`--discipline <name> --host <owner/repo>`, so it never matches, and its
successor brief renders `--role manager` whatever the record holds
(#1861). R3 asks that a brief whose scope, name and host equal the run's
own (as `coord-log.sh run-facts` prints them) be the successor at either
scope, with the role read from the record.

**The brief's shape.** `render-brief.sh` refuses an `entry_args` whose
first token starts with `-`, and the `coordinate` row of
`references/entry-points.tsv` admits no flags, so
`--discipline <name> --host <owner/repo>` can't appear in a brief at all.
`dc_invocation` also puts `--role` directly after the first token, which
for a discipline invocation would split `--discipline` from its value. R4
asks that a discipline successor's brief and dispatch prompt both carry
`/shirabe:coordinate --discipline <name> --host <owner/repo> --role <role>`,
the name and host taken from the run's facts rather than typed by the
coordinator, and that a run whose facts can't be read is refused before
anything is written.

The rest of the PRD constrains what the change may disturb. The role
reaches the successor only as `--role` on the invocation line, written by
the script from the record; the brief input has no role field the
coordinator fills and the template adds no role sentence (R7). The opener
already refuses a `--role` that differs from the record it continues
(`role-mismatch`) unless change flags name an intervention from above, and
the first report's record line already ends "Role: manager." or "Role:
director."; both stay and must hold at both scopes (R8). A successor at
either scope continues its predecessor's run: inside a discipline
rotation's window it takes the rotation over and `coord-log.sh
chain-start` on it prints the predecessor's chain start, and after the
window it opens the next rotation, which carries the last one's record and
role (R5). With no Run `role` row, a successor dispatch exits 1 before any
row, leg or session exists and names `state-stored-set.sh --run role`, at
both scopes (R6). One successor may be pending at a time: the dispatch
writes a record row before it launches, a second dispatch is refused while
that row reads `dispatching` or `dispatched`, a `dispatch-failed` or
`stranded` row doesn't block a new attempt, the next reconcile settles a
`dispatched` row whose session `niwa list` no longer shows as `stranded`,
and a restart that finds the row `dispatching` confirms it when the
session is listed and re-launches it under the same row when it isn't,
never writing a second row (R9). Worker paths don't change: a worker brief
carries no `--role`, a `coordinate` brief naming a different roadmap still
renders `--role manager`, `--rebrief` and `--releg` never read the role
row, a re-brief of a held lane renders no `--role` unless its input names
a `role_change`, and a `role_change` on a successor dispatch is still
refused with exit 1 (R10). Each of these has a test case that fails on the
base commit (R11), and the skill's Roles section and the brief template's
`role` paragraph describe the successor dispatch at both scopes, the
discipline invocation line included (R12).

The opener side already does most of what R5 and R8 need.
`coordinate-open.sh` reads `--discipline`, `--host` and `--role` from the
args file, decides the role against the record it continues
(`role_decide`), applies the discipline window rule before anything else,
takes a run another session drives over through `koto init --continues
--supersede`, and accepts a start whose `--dispatched-by` names the
predecessor only when it takes that predecessor over. What's missing is on
the dispatching side: a way to start a successor that skips the unit
gate, knows the run's own scope at both kinds, renders the discipline
invocation, and records that a successor is on its way.

The milestone verdict on the named-roles work found that neither role
reached a successor in a sandbox run, so the claim that each role hands
off to a successor whose brief and first report name the same role, with
no prose describing the role from scratch, had no evidence behind it.
This design also has to say what a reviewer reads to see that claim hold.

## Decision Drivers

- **No unit state stops a successor (R2).** The route a successor takes
  can't depend on `coord/pick.json`, on `pick` being reachable, or on any
  check keyed to a unit.
- **Worker dispatch keeps every check (R2, R10).** The verdict-owed, pause
  and decision refusals, the unit-form check, and the lane and re-brief
  role rules stay exactly as they are for every brief that isn't a
  successor's.
- **Own-ness at both scopes, from the run's facts (R3, R4).** Whether a
  brief starts this run's successor, and the scope tokens its invocation
  carries, come from what the run was opened with, never from text the
  coordinator typed.
- **The role is data written once (R6, R7).** The script writes `--role`
  from the record's Run `role` row and refuses when there's none; no
  input field or template line carries the role in prose.
- **The successor continues the run (R5, R8).** The successor's opener
  takes the run over (or, after a discipline window, carries it), and its
  role check and record line work unchanged.
- **One pending successor, settled on restart (R9).** The pending
  successor is visible on the record a restart reads, and its settlement
  reuses the worker's confirm-or-relaunch rule.
- **No template structure change.** The template's structural
  fingerprint is in `koto-templates/coordinate.compat.json` at compat 2.
  Moving a state, an accepts enum or a transition raises the compat number,
  and a run compiled at compat 2 is then refused takeover
  (`template-incompatible`). A successor exists to take over a running
  predecessor, so a change that breaks takeover of the runs in flight
  defeats itself. Directive text and gate-script digests can change at the
  same compat number.
- **Few consumers touched.** About thirty scripts read the holdings section.
  A successor's pending state should live where only the scripts that
  need it look.
- **Tested in the script suites (R11).** Each requirement has a case that
  fails on the base commit; the four role and scope pairs are exercised
  end to end through the opener.
- **Documented where coordinators read (R12).** SKILL.md's Roles section
  and `references/brief-template.md`'s `role` paragraph.

## Considered Options

### Decision 1: The route a successor dispatch takes, and where it's triggered

Delegated to /decision.

Every check that stops a successor today is keyed to a unit, and every
stop on the worker route sits behind a template state that only a unit
reaches. The question is which route lets a successor past all of them
(an owed verdict, a pause, a parked decision, no open unit) while workers
keep every one, and where the coordinator starts it.

Two facts shaped the answer. The template's structural fingerprint
covers every state, accepts value (enum values included), gate and
transition, and leaves out only description, directive and details text.
A new pick choice, wait event or state forces compat 3, and a run the
compat table doesn't list at the shipped number is refused takeover as
`template-incompatible`. That includes a compat-2 predecessor that hasn't
restarted and hands over the way it can today. And SKILL.md's rule on
the compat table says a script change that alters what a run does needs
new structure, so any route that stays at compat 2 must leave every
existing gate's verdict unchanged for a record holding no successor
state.

Key assumptions:

- Each installed plugin version keeps its own cache directory, so a
  running coordinator calls the scripts of the root it was last bound to
  until a start rebinds it.
- SKILL.md is read fresh by every session that loads the skill, so its
  text reaches a session that resumes a compat-2 run; directive text
  reaches only runs compiled after the release.
- Re-recording `gate_scripts` at compat 2 is honest because no existing
  gate's exit code changes for a record with no successor row.
- Decided under `--auto`; the decider recorded the choice as assumed.

#### Chosen: A `--successor` mode of `dispatch-worker.sh`, run from the hub, triggered by SKILL.md

`dispatch-worker.sh --session <run> --successor` is a fourth mode beside
`--rebrief`, `--releg` and `--releg-imported`, exclusive with each. It
reads its own context key, `successor_input.json`, the record's Run
section and the run's facts. It never reads `dispatch_topic`,
`brief_input.json` or `coord/pick.json`, and passes `render-brief.sh` no
`--units`. The worker path, with no flag, keeps the verdict-owed, pause,
decision, unit-form and `dispatch_check` refusals exactly as they are.

The coordinator runs the mode itself from the `wait` hub, or at
discipline scope from `rotation_end` before it submits `reasoning:
written`, since after `done` every record write is refused. Nothing in the
template's structure moves. The trigger is text: SKILL.md's Roles section
gives the command, its exit codes, and the rule that no unit is needed;
the `wait` directive gets a one-line pointer (paid for by trims, since the
directive sits under a 10802-byte ceiling); `rotation_end`'s directive
gives the ordering; and the `dispatch` details' sentence about `own` for a
successor points at the mode. The template ships at compat 2 with a
re-recorded `gate_scripts` digest.

Running from the hub needs no edge to `pick`, so a scope with no open
unit, a lane held on an owed verdict and a discipline at `rotation_end`
are all covered. Compat stays at 2, so every run in flight can still be
taken over. The cost is that the trigger is prose rather than a gate: a
coordinator that forgets it simply doesn't hand over, which is today's
behavior and never a bad write.

#### Alternatives Considered

**A new pick choice `successor` with no unit, routed through
`dispatch_check` and `dispatch`.** Exemptions in `deferral-check.sh` and
the unit checks would let it through. Rejected because the enum value,
its decider answer and the new routes to `pick` (which a run with no open
unit never reaches) force compat 3, after which a compat-2 predecessor's
successor is refused takeover. Its compat-2 variant, choice `dispatch` on
a reserved topic reached through `resume`, changes what four gate scripts
return for the same record and costs about eight transitions when the
coordinator's context is scarcest.

**Keep the worker route and exempt the run's own successor brief.** The
verdict-owed, pause and decision checks in `dispatch-worker.sh` and the
unit-form check would skip a brief that starts the run's own successor.
Rejected because `dispatch_check` still holds it for a pause on `all`,
open deferrals, owed decisions and the cap, and with no open unit the
template never reaches `pick`. The strengthened form, a Standing
assignment plus `resume`, changes gate verdicts at compat 2 and leaves the
pending successor in front of the Holdings readers.

**A new `handover` state reached from the `wait` hub.** An explicit
trigger state with a gate on the pending row. Rejected because the new
event value, state and transitions force compat 3 with the same takeover
regression, while it still needs all of the chosen mode's script work. It
is worth reopening only if coordinators are seen skipping the mode, and
only beside a compat raise made for another reason, as a state that calls
this same mode.

**A separate `dispatch-successor.sh`.** Functionally the chosen option,
but R1 names `dispatch-worker.sh` or a mode of it.

**Ending through `wait`'s `end` event and letting the successor carry.**
Rejected because `end` is terminal on a roadmap and the opener refuses a
`--dispatched-by` start it would carry rather than take over; the
predecessor has to stay live until the fence.

### Decision 2: How the dispatch recognizes a successor and gets its role

Resolved inline.

R3 asks that a `coordinate` brief be the run's own successor exactly when
its scope, name and host are the run's own, at either scope, and that its
role then be the record's Run `role` row. R4 adds that a discipline
successor's name and host come from the run's facts, not from anything
the coordinator typed, and that a run whose facts can't be read is refused
before anything is written. Today's test compares only a roadmap
positional's slug with the slug in the session name.

Key assumptions:

- The run's `ROADMAP` variable is repository-relative (its pattern
  requires `docs/roadmaps/.../ROADMAP-<name>.md`), so it is the positional
  the opener takes in the successor's own instance.
- `coord-log.sh run-facts` exiting 1 (no found record) or 2 (a failed read)
  both mean the facts can't be read.

#### Chosen: The mode builds the scope from the run's facts

The mode reads `coord-log.sh run-facts` for the scope, name and host, and
`coord-log.sh vars` for the `ROADMAP` path, and writes the brief's
`entry_args` and `repo` itself: `[<ROADMAP>]` at roadmap scope,
`["--discipline", <DISCIPLINE>, "--host", <HOST_REPO>]` at discipline
scope, and `repo` the run's `HOST_REPO`. An input `entry_args` or `repo`
is optional; when one is given it must equal the derived value token for
token, or the mode exits 1 naming both, so a brief naming another
discipline or host is refused. A run whose facts can't be read exits 1
before anything is written. The role is the record's Run `role` row,
written into the input as `role`; with no row the mode exits 1 naming
`state-stored-set.sh --run role`. An input `role_change` exits 1, as it
does today.

On the worker path, `input_role`'s own-scope test moves to the same facts
at both scopes: a `coordinate` brief whose positional is the run's
roadmap, or whose tokens name the run's discipline and host, is the run's
own. The worker path then refuses it with exit 1, naming `--successor`,
so a successor has one route and always gets the pending row Decision 4
describes. Any other `coordinate` brief is a lane and gets `manager`, as
today.

#### Alternatives Considered

**Extend the positional comparison to `--discipline` and `--host` tokens
the coordinator types in `entry_args`.** Rejected because the coordinator
still types the scope, which R4 rules out, and a typo becomes a refusal
where it could have been impossible.

**Let the mode flag alone mark a successor and use the input's tokens as
typed.** Rejected because nothing then checks the scope is the run's own,
which fails the PRD's refusal for a brief naming another discipline or
host.

### Decision 3: How the brief admits the discipline invocation for a successor only

Resolved inline.

`render-brief.sh` refuses a first `entry_args` token that starts with
`-`, the `coordinate` row of `references/entry-points.tsv` admits no
flags, and `dc_invocation` puts `--role` right after the first token. All
three are right for lanes, which the PRD keeps as roadmap managers. Only a
discipline successor needs the four-token scope.

Key assumptions:

- No Holdings row is written for a successor, so `dc_mode` (the holding's
  mode cell) never sees the discipline flags.

#### Chosen: A script-only `successor` render field

`render-brief.sh` gains a field `successor: true`, which `read_inputs`
deletes from every input and only the `--successor` mode sets, as
`held_rerender` works today. With it, a `coordinate` brief's
`entry_args` may start with a flag, and then must be exactly
`["--discipline", <name>, "--host", <owner/repo>]`, the name matching the
template's `DISCIPLINE` pattern and the host matching `owner/repo`. The
field is refused on any other entry point and beside `held_rerender` or
`role_change_by`, and a successor brief requires `role`. `dc_invocation`
puts `--role` after the whole scope group, the positional at roadmap scope
and all four tokens at discipline scope, so the Goal's line reads
``Run `/shirabe:coordinate --discipline <name> --host <owner/repo> --role <role>` in <owner/repo>.``
and the dispatch prompt carries the same invocation. The
`coordinate` row of `entry-points.tsv` keeps no flags; its header comment
names the successor exception.

#### Alternatives Considered

**Add `--discipline` and `--host` to the `coordinate` row's allowed
flags.** Rejected because it admits the flags on lane briefs, which stay
roadmap managers, and the first-token rule would still refuse the shape.

**A new entry-point row for successors.** Rejected because the
invocation, and the `--skill` niwa is passed, must stay
`shirabe:coordinate`, so a second row would name a skill that doesn't
exist.

### Decision 4: The record row for a pending successor, and how it settles

Resolved inline.

R9 needs a pending successor on the record before the launch, one at a
time, settled by reconcile and by a restart the way a worker's holding
is. The row has to survive every continuation a restart can take, and it
mustn't land in the successor's own record as something the successor
then trips over.

Key assumptions:

- `run_keys` in `state-schema.jq` is a closed set, so an older plugin may
  refuse a record holding the new key; a successor runs the same plugin
  as its predecessor or a newer one.

#### Chosen: One Run row, `successor`

The Run section gains a key `successor`, one row at most, whose value is
`<status> <topic> <YYYY-MM-DD>`, the status one of `dispatching`,
`dispatched`, `dispatch-failed` and `stranded`, its Set by the run that
wrote it. It joins `run_keys` and is written only through a new
`state-stored-set.sh --successor` mode, which checks the value's grammar
and the status moves; `--run successor` stays refused. Each write is told
as an entry, as every stored-set write is.

The mode writes the row `dispatching` before `niwa dispatch` and rewrites
it `dispatched` or `dispatch-failed` after, under a lock named for the
run. A second dispatch with another topic, while the row reads
`dispatching` or `dispatched`, exits 12 naming the pending successor. A
re-run with the row's own topic resumes that dispatch: it confirms when
`niwa list` shows the session and re-launches under the same row when it
doesn't, which is the worker's step-1 rule and never writes a second row.
A `dispatch-failed` or `stranded` row doesn't block a new attempt, which
takes a new topic, as a worker's does.

One settle function, `dc_successor_settle` in `dispatch-common.sh`, turns
a `dispatching` row whose session is listed `dispatched`, and a
`dispatched` row whose session isn't listed `stranded`; an unlisted
`dispatching` row is left for the mode to re-launch. The mode runs the
settle first on every invocation, and `reconcile-settle.sh --successor`
runs it in the reconcile pass, without changing the pass's exit status or
the reconcile gate's verdict.

A start whose `--dispatched-by` names the run in the row's Set by clears
the row: `finish_takeover` in `coordinate-open.sh` for a takeover, in the
same step that writes the successor's coordinator and role rows, and
`state-open.sh --carry` for a discipline successor started after its
rotation's window, reading the new run's `koto/links/dispatched-by/` key.
A crash restart in a new Claude session isn't such a start, so it keeps
the row and settles it.

#### Alternatives Considered

**A Holdings row marked by a new phase.** Rejected because about thirty
scripts read Holdings and none filters on entry point, and the takeover
would hand the successor a holding naming itself: its handover gate would
hold on the not-told gap, it would count against its own cap, and it
would block its own roadmap close.

**A new `record/successor` section key.** Rejected because it needs the
schema, write-core, carry and structure-test changes the Run section
already has, for the same one-row content.

### Decision 5: What a reviewer reads to see the role carried

Resolved inline.

The milestone verdict on the named-roles work needs to see that each role
hands off to a successor whose brief and first report name the same role,
with no prose describing the role from scratch. R7's criterion is literal:
in a rendered successor brief, the only line naming `manager` or
`director` is the invocation line. Two things break that today: goal text
the coordinator writes can name a role, and every brief's fixed keep-alive
line reads "The workspace manager schedules your keep-alive at dispatch."

Key assumptions:

- A successor's brief never needs to name a role in prose: whoever it
  reports to is already its `reports-to` row.

#### Chosen: Three reads, held true by construction

A reviewer reads three things. The predecessor's record carries a
successor entry at launch and at confirm naming the topic, the brief's
path and the role rendered. The brief's invocation line carries `--role
<role>`. The successor's first report's record line, which
`reconcile-report-get.sh --md` prints live from the record the opener
checked, ends "Role: <role>." The two agree or the opener refused the
start as `role-mismatch`.

Two guarantees make the brief's half hold in a real run, not only in a
fixture. The `--successor` mode refuses, with exit 1 naming the field, any
coordinator-written text (`authority`, `goal`, `checkpoints`,
`acceptance`, `decisions`, `read_first`, `out_of_scope`,
`standing_rules`, `surfaces`) that holds `manager` or `director` as a
whole word, in any case. And on a `coordinate` brief `render-brief.sh`
words the keep-alive line "niwa schedules your keep-alive at dispatch.",
as it already says "commit" where a worker brief says "head", so worker
golden files don't change. An engine test for each role and scope pair
then runs the whole handover: a predecessor record, the mode, the
rendered brief, the opener started with the brief's tokens and
`--dispatched-by`, the takeover (or the rotation carry), and the record
line.

#### Alternatives Considered

**Rely on the existing behavior and tests.** Rejected because a goal that
says "director", or the fixed "workspace manager" line, breaks the
one-line criterion in a real brief.

**A dedicated evidence script comparing the brief and the report.**
Rejected as a new surface for a comparison two reads and the end-to-end
tests already make.

### Decision 6: Who names the successor's topic

Resolved inline.

The topic names the brief file, the lock and the niwa session. The
decision on the route left it open.

#### Chosen: The coordinator names it, the mode checks it

The input's `topic` is the coordinator's choice, as for a worker, and
SKILL.md recommends `<scope name>-successor-<n>`. The mode checks the
grammar (`dc_valid_topic`), refuses a topic a live session uses (exit 5),
and refuses a new attempt that reuses the topic of a `dispatch-failed` or
`stranded` row (exit 3), the worker rule for the same case.

#### Alternatives Considered

**The mode derives the topic from the scope slug and a counter.**
Rejected because a discipline slug plus a counter can pass the 64-character
topic bound and niwa cuts session slugs at 40 characters, so two runs'
successors could collide in ways the live-session check would only catch
at launch.

### Decision 7: Refusing while a decision arrival is unrecorded

Resolved inline.

The takeover carries the record but not the run's log, and four of
`decision-next.sh`'s rules (`unrecorded-open`, `unrecorded-answer`,
`unrecorded-evidence`, `unrecorded-raise`) name an arrival the log holds
and the record doesn't yet. A successor launched in that window would
never see it.

#### Chosen: Exit 13 while one is unrecorded

The mode runs `decision-next.sh` first and exits 13 while it names one of
those rules, with a message naming the write that records it. At the hub
in normal routing the rule can't fire, so the refusal never stands in for
a unit check.

#### Alternatives Considered

**A warning instead of a refusal.** Rejected because an arrival lost at a
takeover can't be recovered, and one write clears the refusal. The
decision's reviewers split on this, so it's the first thing to revisit if
the refusal is seen firing.

## Decision Outcome

**Chosen: a `--successor` mode with run-derived scope, a `successor` render
field, a `successor` Run row, and a brief that names its role once**

A coordinator hands over by writing `successor_input.json` (topic, goal,
checkpoints, acceptance and the rest of a brief, with no role, scope or
repository it has to type) and running `dispatch-worker.sh --session
<run> --successor` from the `wait` hub, or from `rotation_end` at
discipline scope. The mode never touches `pick`, `coord/pick.json` or any
unit check, so an owed verdict, a pause, a parked decision or an empty
scope can't stop it, and the worker path keeps every one of those checks.
It reads the run's facts and builds the invocation itself:
`/shirabe:coordinate <ROADMAP> --role <role>` at roadmap scope and
`/shirabe:coordinate --discipline <name> --host <owner/repo> --role
<role>` at discipline scope, the role taken from the record's Run `role`
row. A brief naming another scope, an input `role_change`, a missing role
row, unreadable facts, or role words in the coordinator's own text are
each refused with exit 1 before anything is written.

Before it launches, the mode writes one Run row, `successor`, reading
`dispatching <topic> <date>`, and after the launch rewrites it
`dispatched` or `dispatch-failed`. A second successor with another topic
is refused (exit 12) while the row is pending, and a re-run with the same
topic confirms or re-launches under the same row. Reconcile settles the
row as it settles a worker's holding, and also marks a `dispatched` row
whose session is gone `stranded`. The successor's opener, started from the
brief with `--dispatched-by` naming the predecessor, takes the run over
through koto's fence, checks its `--role` against the record
(`role-mismatch` otherwise), and clears the row in the same step that
writes its coordinator row. A discipline successor started after its
rotation's window opens the next rotation, which carries the record and
role and clears the row in its carry. The successor's first report's
record line then reads "Role: <role>."

Nothing in the template's structure changes, so it stays at compat 2 and
every run in flight can still be taken over. The trigger lives in
SKILL.md's Roles section and in directive text. The predecessor's record
tells the handover as entries a reviewer can follow to the brief, and the
brief's only line naming a role is its invocation line.

### Rationale

The decisions lean on each other. Staying at compat 2 is what lets the
mode exist outside the template, and being outside the template is what
gets it past every unit gate at once. Building the scope from the run's
facts makes the successor test, the discipline invocation and the R4
refusal one mechanism instead of three. Putting the pending successor in
a Run row rather than Holdings means the row travels with every
continuation and no Holdings reader sees it, so the successor never holds
itself. Clearing the row only on the `--dispatched-by` match lets the
takeover, the carry and a crash restart each do the right thing without
another marker. The trade accepted is a prose trigger and a new Run key an
older plugin can't read.

## Solution Architecture

### Overview

The change lives in the coordinate skill's dispatch and record scripts,
its opener's takeover and carry, and its docs. No koto, niwa or template
structure change is needed. The mode is a new branch of
`dispatch-worker.sh` that shares its lock, launch, deadline, listing and
confirm code and replaces the holding row with a Run row.

### Components

- `skills/coordinate/scripts/dispatch-worker.sh`
  - `--successor`: a fourth exclusive mode. Order: take the run lock
    (`$BRIEFS/.successor.<run>.lock`); run `dc_successor_settle`; read
    the `successor` row and refuse (exit 12) a pending one with another
    topic; refuse (exit 13) while `decision-next.sh` names an unrecorded
    arrival; read `successor_input.json`; derive the scope from run-facts
    and `vars`; refuse a differing `entry_args` or `repo`, role words in
    coordinator text, a `role_change`, no role row (exit 1); set `role`,
    `successor: true`, `grant: own`, `reports_to`,
    `dispatcher_session`, a fixed `unit` naming the scope, and `phase:
    executing`; check the brief with `render-brief.sh --stdout` and no
    `--units`; write the row `dispatching` (or reuse a resumed one);
    render the brief; launch; confirm. Output `session=<name>`.
  - `input_role`: the own-scope test reads run-facts at both scopes; an
    own-scope `coordinate` brief on the worker path exits 1 naming
    `--successor`.
  - A confirm write refused because a takeover fenced the run (`coord-log.sh
    fence` names a successor) is a success: the mode prints
    `session=<name>` and `taken_over=<successor run>` and exits 0.
- `skills/coordinate/scripts/dispatch-common.sh`
  - `dc_invocation`: `--role` after the scope group, four tokens when
    `successor` is set and the first token is `--discipline`.
  - `dc_successor_settle <session> <root>`: the shared settle.
- `skills/coordinate/scripts/render-brief.sh`: the `successor` field and
  its checks; the keep-alive wording on `coordinate` briefs.
- `skills/coordinate/scripts/state-schema.jq` and `state-stored-set.sh`:
  the `successor` Run key and the `--successor <status> <topic>` write
  mode.
- `skills/coordinate/scripts/reconcile-settle.sh` and `reconcile-pass.sh`:
  a `--successor` arm launched when the record holds a pending row; the
  reconcile report gets one optional line naming it.
- `skills/coordinate/scripts/coordinate-open.sh` (`finish_takeover`) and
  `state-open.sh` (`--carry`): clear the row when `--dispatched-by` names
  the run that wrote it.
- Docs: `SKILL.md` (Roles; the takeover paragraph's mention of a successor
  brief), `references/brief-template.md` (the `role` paragraph and the
  successor input), `references/state-keys.md` (the Run key),
  `references/entry-points.tsv` (header comment), and directive text in
  `koto-templates/coordinate.md` (`wait`, `rotation_end`, `dispatch`
  details). `koto-templates/coordinate.compat.json` records the new
  `gate_scripts` digest at compat 2.

### Key Interfaces

```
dispatch-worker.sh --session <run> --successor
  reads   successor_input.json (context), record Run section,
          coord-log.sh run-facts / vars
  prints  session=<niwa session>  [taken_over=<run>]
  exit    0 dispatched or confirmed
          1 refused: no role row, role_change, another scope, unreadable
            facts, role words in coordinator text, brief refused
          3 the topic is a failed or stranded row's
          5 a live session uses the topic
          4 / 6 / 7 / 8 / 11 as for a worker
          12 a successor is pending (names its topic and status)
          13 a decision arrival is unrecorded (names the write)

state-stored-set.sh --session S --successor <status> <topic> --by <run>
Run row  {key: "successor", value: "<status> <topic> <YYYY-MM-DD>",
          set_by: <run>, set: <time>}
```

The successor input carries the same fields as a brief input except
`role`, `held_rerender`, `role_change_by`, `successor`, `grant`, `unit`
and `phase`, which the mode writes; `entry_args` and `repo` are optional
and checked.

### Data Flow

```
coordinator at wait/rotation_end
  -> koto context add <run> successor_input.json
  -> dispatch-worker.sh --successor
       settle row -> refuse pending/unrecorded -> derive scope + role
       -> render check -> Run row "dispatching" -> brief file
       -> niwa dispatch "<prompt>" --name <topic> --brief ... --grant ...
       -> Run row "dispatched" (+ entry naming topic, brief, role)
successor session
  -> args.json = invocation tokens
  -> coordinate-open.sh --dispatched-by <predecessor run> args.json
       role_decide (role-mismatch unless from above)
       takeover (fence) -> finish_takeover: coordinator row, role row,
       clear successor row, takeover entry
     or, discipline after window: new run -> predecessor_carry
       (state-open.sh --carry: record, role, clear row)
  -> reconcile -> reconcile-report-get.sh --md: "... Role: <role>."
predecessor restart (no takeover yet)
  -> reconcile pass: dc_successor_settle (dispatched / stranded)
  -> hub: dispatching row unlisted -> --successor again, same topic
```

## Implementation Approach

### Phase 1: The record row

Add `successor` to `run_keys` and `state-stored-set.sh --successor`, with
the value grammar, the status moves and the entry. Add
`dc_successor_settle` and its unit tests. Document the key in
`references/state-keys.md`.

Deliverables:
- `state-schema.jq`, `state-stored-set.sh`, `dispatch-common.sh`
- `state-schema_test.sh`, `state-stored-set_test.sh`, `dispatch-common_test.sh`

### Phase 2: The brief

Add the `successor` field, the discipline shape and the keep-alive wording
to `render-brief.sh`; move `--role` after the scope group in
`dc_invocation`; update `entry-points.tsv`'s header comment.

Deliverables:
- `render-brief.sh`, `dispatch-common.sh`, `references/entry-points.tsv`
- `render-brief_test.sh` cases: discipline shape accepted only with
  `successor`, refused on lanes and other entry points, one role line at
  each scope, worker golden files unchanged

### Phase 3: The mode

Add `--successor` to `dispatch-worker.sh` with every refusal, the run
lock, the write-ahead, the launch, the confirm and the fenced-confirm
case; move `input_role`'s own-scope test to run-facts and refuse an
own-scope brief on the worker path.

Deliverables:
- `dispatch-worker.sh`
- `dispatch-worker_test.sh` cases for R1, R2 (verdict owed, pause,
  decision, no open unit), R3, R4, R6, R7, R9 and R10, each failing on the
  base commit

### Phase 4: Settle and clear

Add `reconcile-settle.sh --successor` and its launch in
`reconcile-pass.sh`, the report line, and the clear in `finish_takeover`
and `state-open.sh --carry`. Re-record `gate_scripts` in
`coordinate.compat.json`.

Deliverables:
- `reconcile-settle.sh`, `reconcile-pass.sh`, `reconcile-report.sh`,
  `coordinate-open.sh`, `state-open.sh`, `coordinate.compat.json`
- `reconcile-settle_test.sh`, `coordinate-takeover_engine_test.sh`,
  `discipline-carry_engine_test.sh` cases

### Phase 5: End to end and docs

A new engine test runs the handover for each role and scope pair, plus the
`role-mismatch` refusal and the accepted change from above at both scopes,
and the discipline successor after its window. Write the SKILL.md Roles
text, the brief-template `role` paragraph, and the directive text, inside
the `wait` ceiling that `directive-ceiling_engine_test.sh` enforces.

Deliverables:
- `successor-handover_engine_test.sh`
- `SKILL.md`, `references/brief-template.md`, `koto-templates/coordinate.md`

## Security Considerations

To be completed in Phase 5.

## Consequences

### Positive

- A lane owing a verdict, a run with no open unit, and a discipline
  director can all hand over, and the successor starts in the role its
  record holds.
- Worker dispatch is untouched: the same verdict-owed milestone still
  exits 10 on the worker path.
- The template stays at compat 2, so every run in flight can still be
  taken over.
- A reviewer can confirm a handover from the predecessor's entries, the
  brief's invocation line and the successor's record line.

### Negative

- The trigger is prose. A coordinator that never runs the mode doesn't
  hand over, and nothing in the template makes it.
- A record holding the `successor` row can't be read by an older plugin,
  because `run_keys` is closed.
- `dispatch-worker.sh`, already long, gains a fourth mode and two exit
  codes.
- An own-scope `coordinate` brief that worked on the worker path is now
  refused, so a coordinator following an old directive text gets a
  refusal it has to read.
- Exit 13 may refuse a handover a coordinator thinks is ready.
- If a person starts a discipline's next rotation by hand while a
  successor is pending, the carry keeps the row, and the arriving
  successor takes the new rotation over.

### Mitigations

- The `wait` pointer, the reconcile report's pending-row line and the
  mode's own messages keep the trigger in front of the coordinator; a new
  `handover` state can follow beside an unrelated compat raise.
- A successor's instance runs the workspace's installed plugin, which is
  at least as new as its predecessor's in practice; the takeover refuses
  rather than reading a record it can't parse.
- The mode shares the worker's lock, launch and confirm code, so it adds a
  branch rather than a second copy.
- The worker path's refusal names `--successor` and the input to write.
- Exit 13's message names the one write that clears it.
- The reconcile report names the pending row, and the arriving
  successor's takeover entry says which run it continued.
