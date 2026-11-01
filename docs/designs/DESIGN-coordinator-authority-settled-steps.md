---
schema: design/v1
status: Accepted
problem: |
  The coordinate skill decides who settles a merge, a close, a release or a
  step a worker hands back from one authority read taken at start, folded
  into permit, deny or confirm and kept in coord/posture.json, plus its own
  bound-or-root rule. Only the merge reads again, and need-check.sh routes a
  held step by the stored copy's bound state. A workspace can't declare that
  a step needs review and have it hold mid-run, and the copy can be edited.
decision: |
  One new script, authority-read.sh, becomes the only code under
  skills/coordinate/ that runs niwa authority check. A koto check action,
  settle-check.sh, runs at each finishing state, asks the one point that
  step maps to, and prints a sealed take, route or hold verdict the state's
  transitions follow; it writes what the read said into a per-step evidence
  key that nothing reads back. The merge reads at land and again at
  land_merge and takes only when both say take. Teardown and the
  always-expected review keep their current sources, and every missing piece
  of the workspace authority work is a named dependency the step holds on.
rationale: |
  A check action runs the read itself, so the coordinator never supplies the
  answer, and its sealed token is koto's capture rather than a key the agent
  can rewrite; that is what keeps a forged record from moving a step. One
  reader and one verdict script keep the step-to-point mapping and the take
  rule in one place instead of four. Holding where the answer is silent, and
  never falling back to a parent or a reports-to address, costs root
  coordinators their finishing steps until niwa answers for them, which is
  why the implementation waits on that work.
upstream: docs/prds/PRD-coordinator-authority-settled-steps.md
decision_provenance: inline-resolved
---

# DESIGN: Coordinator Authority-Settled Steps

## Status

Accepted

## Context and Problem Statement

A coordinator (a manager running one lane, or a director over managers)
reaches finishing steps: it merges a pull request, closes an issue, a pull
request or a roadmap, cuts a release, tears down a worker's instance, or takes
one of these when a worker hands it back. The requirement this design answers
is that who settles each of those steps comes from the workspace's authority
answer, read at the step, and from nothing the skill decides for itself.

Today four pieces of code stand between the workspace and that answer.

`posture-read.sh` runs at `start_posture`. It asks
`niwa authority check --json --session <id> -C <instance root>` once, with
`--point merge-pr --point close-issue --point cut-release`, and folds each point
together with the Claude Code permission lists into `permit`, `deny` or
`confirm`. The fold is a table of its own: a held grant with `session` as decider
and author exclusion off is `permit`; anything else is `deny`, except that a
close with `person` or author exclusion on reads `confirm`. The whole answer
lands in `coord/posture.json` under `grant_check`, a context key the
coordinator can write.

`board-lib.sh`'s `bl_merge_posture`, which `land-check.sh` calls at its eighth
check and `land-merge.sh` calls again before the merge command, is the only
place a step reads again. It takes the stricter of the start capture and a
fresh `posture-read.sh` run, and an `unread` result becomes `permit` when the
human's relayed answer at `posture_ask` permitted the merge. That relayed
answer is a row in the coordinator's own record widening what the workspace
said.

`need-check.sh`, at `surface_check`, words a worker's
`reserved-step <merge|release|close|teardown>` need. It reads
`grant_check.state` from `coord/posture.json`: `bound` words the need for the
dispatcher's instance, and anything else for a person. The per-point decider
the answer already carries is never looked at, so a bound session whose point
names `person` still hands its step to its dispatcher.

`state-stored-set.sh --rules`, the standing-rule read added by
tsukumogami/shirabe#1473, is a second caller of `niwa authority check` (with no
`--point`), which it uses to print `under_session_grant` and `session_allows`
beside each Standing row. No gate reads those fields.

Around the code, the template and the references repeat one sentence about
twenty times: a merge, close or release the coordinator can't take "goes to the
coordinator that dispatched you when your session is bound, and to a person only
when you are a root coordinator". That is a rule about parents, and the
requirement removes it.

The technical problem is therefore four things at once. Every finishing step
has to read the answer for its own point at the visit that acts, through one
reader. The read has to be taken somewhere the coordinator can't feed it an
answer or edit it afterwards. What the read said has to reach the record as
evidence without becoming an input. And the parts of the answer niwa doesn't
give yet (a declaration that a step needs review, an answer for a root session,
an addressable target, a teardown point, where a review goes when the session
is the settler) have to show up as a held step, never as a guess.

## Decision Drivers

From the PRD, carried here as what each asks:

- **Each step asks one point (R1).** A merge, a verdict or reopen pull
  request's merge included, asks `merge-pr`; closing an issue, a pull request
  or a roadmap asks `close-issue`; a release asks `cut-release`. A handed-back
  step asks the point of the step it is. That mapping is the skill's only
  table (R13), and it asks no point niwa doesn't define.
- **Read at the step (R2, R12).** Each visit to a finishing step reads its point
  fresh, bounded at `NIWA_LOOKUP_SECONDS` (3 seconds by default), and acts on
  that read in the same visit: one read per visit, two when the act reads
  again. The start read stays only for the board and the start report.
- **One reader (R3).** One script is the only code under `skills/coordinate/`
  that runs `niwa authority check`, and it accepts an answer only on exit 0
  with schema `niwa.authority.check/v1` and every value in the vocabulary
  `posture-read.sh` accepts today.
- **Act on the answer, add nothing (R4, R5).** The coordinator takes a step only
  when the answer says the grant is held, names `session` as settler and has
  author exclusion off, and then only after the review it always does. Every
  other case goes to the settler the answer names, at the target the answer
  gives. No settler is derived from a level, a parent, `bound`, a missing field
  or the reports-to address, and the close-confirm versus merge-deny split goes.
- **Hold when the answer can't decide (R6).** A failed, timed-out or skipped
  read, a refused answer, no entry for the point, or a settler with no target
  holds the step: not taken, recorded as held with the reason, reported where
  other reports go. The report hands nothing over.
- **The record is evidence, never input (R7, R8).** The step's entry records
  state, settler, author exclusion, target and read time. No gate, router or
  later step reads that entry or `coord/posture.json` to pick a settler. A row
  may hold a step; none may let the session take one, change the settler or
  stand as proof another settler acted. Done for a routed step is what GitHub
  records.
- **Two passages keep today's source (R9, R10).** Teardown's settler stays the
  permission posture until niwa names a teardown point. The review the skill
  always expects before a merge stays sourced from the Verdicts rules (whoever
  writes a verdict never approves its own Done; the reviewer is the dispatching
  coordinator when bound and a person at the root).
- **Workers unchanged (R11).** A worker brief's `Named authority:` line stays
  as tsukumogami/shirabe#1449 left it.
- **Narrow claim (R14).** `SKILL.md` says the coordinator never acts more widely
  than the answer and no row widens it; it claims nothing about the answer
  being unforgeable.

Implementation drivers the PRD doesn't name:

- **Fit the template's existing checks.** Finishing states already decide
  through koto check actions whose stdout is captured and sealed to the visit
  (`land-check.sh`, `need-check.sh`); a new mechanism should look like them.
- **Keep the permission lists as a floor.** Claude Code's own deny and ask rules
  still apply to a command the answer allows; the design can't route around
  them.
- **Test against a fake niwa.** Every outcome has to be checkable with a fake
  `niwa` first on PATH, as the #1473 engine suites do.

## Considered Options

### Decision 1: The shape of the one reader

Resolved inline. Two places run `niwa authority check` today, and the per-step reads would add
more. R3 needs exactly one, with one vocabulary check, and a search for the
command has to find one file.

Key assumptions:
- niwa keeps `--point` and the `niwa.authority.check/v1` schema.

#### Chosen: A new script, `authority-read.sh`

`authority-read.sh --session <id> [--instance-root DIR] [--point <p>]...`
finds the instance root as `posture-read.sh` does today, runs the one
`niwa authority check` call bounded at `NIWA_LOOKUP_SECONDS`, checks the schema
and every value against niwa's vocabularies, and prints either the accepted
answer as JSON or a one-word failure (`skipped`, `timeout`, `failed`,
`refused`) with the reason on stderr. `posture-read.sh`, `state-stored-set.sh
--rules` and the new per-step check all call it, and nothing else under
`skills/coordinate/` names the command. It is small, has one job, and makes
R3's acceptance test a plain `grep`.

#### Alternatives Considered

**A `--point` mode of `posture-read.sh`.** Rejected: it ties a 3-second per-step
read to a 550-line settings parser that the step doesn't need, and leaves the
start read and the step read sharing flags that mean different things.

**A function sourced from `state-common.sh`.** Rejected: every script that
sources it carries the call, and the one-file search R3 asks for can't tell a
caller from a definition.

### Decision 2: Where each step reads, decides and records

Resolved inline. The step's read has to happen at the visit that acts, somewhere the coordinator
can't hand it an answer, and what it said has to land in the record without
anything reading it back to route.

Key assumptions:
- Each finishing step is a template state, or gains one, whose check runs
  before the act.
- koto's capture of a check action's stdout isn't writable by the agent, and
  `coord-log.sh seal` binds a token to the visit as it does for `need-check.sh`.

#### Chosen: A check action, `settle-check.sh`, at each finishing state

`settle-check.sh --session S --step <merge|close|release>` runs as a koto check
action on entry to each finishing state. It maps the step to its one point
(R1), calls `authority-read.sh --point <p>`, applies R4's take rule and R6's
holds, and prints a sealed verdict: `take <point>`, `route <settler> <point>`
or `hold <point> <reason>`. The state's transitions follow the captured token
and accept no submitted evidence field in its place, so the coordinator acts
on what koto captured, not on anything it submits.
Before printing, it writes the read into the step's evidence key with
`coord-log.sh seal --file --key`. No gate or script reads that key.

#### Alternatives Considered

**An agent-run read in each directive.** Rejected: the coordinator would run the
read and submit the result, so it could submit any answer it liked.

**A read inside each existing check** (`land-check.sh`, `need-check.sh` and each
close-out's own check). Rejected: four copies of R1's mapping and R4's take rule
drift, which is the failure R3 exists to stop.

**One start read kept in a sealed key.** Rejected: R2 forbids acting on a start
read, and a declaration changed mid-run would never apply.

### Decision 3: How the merge's two reads combine with the rest

Resolved inline. The merge is the one step whose act reads again today, and its posture also
folds in the start capture, the permission lists and the `posture_ask` answer.

Key assumptions:
- `land-merge.sh` keeps a read immediately before the merge command.

#### Chosen: Take only when both reads say take and the permission lists allow it

`land-check.sh`'s eighth check calls `settle-check.sh --step merge` in place of
`bl_merge_posture`, and `land-merge.sh` calls it again just before the merge
command. The merge runs only when both print `take`; either `hold` or `route`
holds or routes it (R2). The start capture stops deciding the merge, and the
`posture_ask` answer can no longer lift an unread result to `permit`, since a
relayed row can only hold (R8). When the answer lets the session take a merge
but a Claude Code deny or ask rule covers the command, the step is held with
the reason `permission`: the lists are the workspace's own narrowing, not a
settler, so the step goes nowhere the answer didn't name.

#### Alternatives Considered

**Keep the start capture as a floor.** Rejected: a stored copy deciding a later
step is the problem R2 removes.

**Drop `land-merge.sh`'s re-read.** Rejected: the merge loses the check at the
moment of the act it has today.

**Send a permission-denied merge to a person.** Rejected: that invents a settler
the answer didn't give, which R4 rules out.

## Decision Outcome

Every finishing step except teardown runs one check action, `settle-check.sh`,
on entry to its state. It asks `authority-read.sh` for the step's one point,
turns the answer into take, route or hold by R4 and R6, seals that verdict to the
visit, and writes the read into a per-step evidence key nothing reads back. The
state's transitions follow the sealed token. The merge runs the check twice,
at land and at land_merge, and takes only when both say take and the permission
lists allow the command.

The pieces fit because each answers a different half of the forgery question.
The check action keeps the coordinator from supplying the answer. The sealed
token, not a context key, carries the verdict to the transitions. The evidence
key gives R7 its record without giving any router something to read. And
because a record row can only hold, no ordering of settlers is needed anywhere.

## Solution Architecture

### Overview

The skill gets one reader, one verdict script and one evidence key per step
visit. The start read stays for the board and teardown. The bound-or-root
sentences and the `grant_check.state` routing go, except in the teardown and
reviewer passages.

### Components

**`skills/coordinate/scripts/authority-read.sh` (new).** The only code under
`skills/coordinate/` that runs `niwa authority check`. It finds niwa (PATH, else
an executable `$NIWA_BIN`), the session id (`CLAUDE_CODE_SESSION_ID`) and the
instance root, and with any of them missing prints `skipped`. Otherwise it runs
`niwa authority check -C <instance> --session <id> [--point <p>]... --json`
under `NIWA_LOOKUP_SECONDS`, and accepts the answer only on exit 0 with schema
`niwa.authority.check/v1` and every `state`, `decider`, `author_exclusion`,
`level` and grant value inside the vocabularies `posture-read.sh` accepts today.
It interprets nothing: it hands back the answer or the failure word.

**`skills/coordinate/scripts/settle-check.sh` (new).** The check action at each
finishing state. It holds R1's mapping as its one table: `merge` to `merge-pr`,
`close` to `close-issue`, `release` to `cut-release`. Its decision, in order:

1. A read that isn't an accepted answer holds: `hold <point> read-skipped`,
   `read-timeout`, `read-failed` or `answer-refused`.
2. No entry for the point holds: `hold <point> no-entry`.
3. Grant held, settler `session`, author exclusion off: `take <point>`, unless a
   Claude Code deny or ask rule covers the step's command, which holds as
   `hold <point> permission` (Decision 3).
4. Settler `person`, whether or not the grant is held: `route person <point>`.
5. Settler `dispatcher`, or `session` with author exclusion on, whether or not
   the grant is held: `route target
   <point>` when the answer gives an addressable target, else
   `hold <point> no-target`.
6. Grant not held, settler `session`, exclusion off: the answer names the session
   but doesn't let it act, and names no one else: `hold <point> no-grant`.

"Grant held" means the answer's grant lists the step's point. An answer whose
`state` or any other value is outside niwa's vocabulary never reaches this
logic: `authority-read.sh` refuses it, so every accepted answer has a defined
outcome above. The permission lists in step 3 come from the same settings
reading `posture-read.sh` does today, run unsealed for the one step; they can
only turn a take into a hold.

It writes the evidence key, then seals and prints the token. Run as a state's
own check action it seals its token to the visit. Called from inside another
check action (`land-check.sh`, `land-merge.sh`, `need-check.sh`) it runs
unsealed and returns its verdict to the caller, whose one sealed token carries
it, so each state has one seal and its transitions follow that token. It never
reads `coord/posture.json`, a Standing or Reversals row, the `posture_ask`
answer, a review round or any earlier evidence key. A hold's reason is always
one word from the closed list below, never text taken from the answer.

**Each finishing state.** The states that settle a step gain the check, or swap
their posture read for it:

| Step | Where it runs | Point |
|------|---------------|-------|
| Merge a worker's pull request | `land` (in `land-check.sh`) and `land_merge` (in `land-merge.sh`) | `merge-pr` |
| Merge a verdict or reopen pull request | `milestone_verdict`, `milestone_reopen` | `merge-pr` |
| Close an issue or pull request in a close-out | the close-out's state, per `references/loop.md` | `close-issue` |
| Close a roadmap | `roadmap_close_step` | `close-issue` |
| Release the coordinator runs itself | the state that runs it | `cut-release` |
| A merge, close or release a worker hands back | `surface_check` (in `need-check.sh`) | the step's own |
| Teardown, own or handed back | `teardown` and its states | none (R9) |

A release unit dispatched to a worker settles under the worker's own grant and
brief (R11), so only a release the coordinator runs itself reads `cut-release`
here.

**`need-check.sh`.** A `reserved-step <merge|close|release>` need calls
`settle-check.sh` for that step. `take` means the coordinator takes the step
itself; `route person` words the cell for a person; `route target` names the
answer's target; `hold` words the cell as held with its reason. The
`grant_check.state` branch and the `for dispatcher <instance>` wording go.
`reserved-step teardown` stays for a person, as the permission posture reserves
it (R9).

**`posture-read.sh`.** Keeps the settings reading, the verdict token and
`coord/posture.json` for the board, the start report and teardown. Its grant
fold table goes (R13): it calls `authority-read.sh` and stores the answer as
data under `grant_check` for display only.

**`board-lib.sh`.** `bl_merge_posture` and `bl_human_holds_merge` go;
`land-check.sh` and `land-merge.sh` call `settle-check.sh` instead.

**`state-stored-set.sh --rules`.** Calls `authority-read.sh` with no `--point`
in place of its own call. `under_session_grant` and `session_allows` print as
they do today, and still no gate reads them.

**`progress-view.sh`.** `--dispatcher` goes. A held or routed step's cell shows
the settler and reason from `need-check.sh`'s stored need.

**Skill text.** In `SKILL.md`, `koto-templates/coordinate.md` and
`references/*.md`, every sentence that routes a merge, close or release by bound
or root becomes "the step goes to the settler the authority answer names; when
it names none you can reach, hold it and report". `SKILL.md` names the read as
`niwa authority check -C <instance> --session <id> --point <p>`, says a record
row may restrict its answer but never widen it, and claims nothing about the
answer being unforgeable. The teardown passage and the Verdicts reviewer
passage keep their wording.

### Key Interfaces

`authority-read.sh` prints one of:

```
{"schema":"niwa.authority.check/v1", ...}     # the accepted answer, exit 0
skipped | timeout | failed | refused          # exit 3, reason on stderr
```

`settle-check.sh` prints one sealed token:

```
take <point> keyseal:<seq>:<sha256>
route person <point> keyseal:<seq>:<sha256>
route target <point> keyseal:<seq>:<sha256>
hold <point> <read-skipped|read-timeout|read-failed|answer-refused|no-entry|no-target|no-grant|permission> keyseal:<seq>:<sha256>
```

The evidence key, `coord/settle/<state>-<visit>.json`, holds:

```json
{"step": "merge", "point": "merge-pr", "read_at": "<UTC time>",
 "result": "answer|skipped|timeout|failed|refused",
 "state": "<answer's state>", "settler": "session|dispatcher|person",
 "author_exclusion": true, "target": "<as given, or null>",
 "verdict": "take|route|hold", "reason": "<hold reason or null>"}
```

The target's shape is whatever the answer gives; the design assumes none.

### Data Flow

A finishing state is entered. koto runs `settle-check.sh`, which calls
`authority-read.sh`, which calls niwa once. The verdict is written to the
evidence key, sealed and printed; koto captures it. The state's transitions
route on the captured token alone: `take` goes to the act (for a merge, through
`land_merge`, whose own check must also print `take`); `route person` goes to the
surface path for a person; `route target` sends the step to the answer's target;
`hold` records the step as held, sends one report naming the step, point and
reason to where the coordinator sends its other reports, and leaves the step to
be read again at its next visit. Which transition each state uses for a held
step (for `roadmap_close_step`, a held outcome beside `closed` and
`handed_over`) is settled per state in the plan. A routed step is marked done only when GitHub
shows the pull request merged, the issue closed or the release published.

### Where this meets the earlier work

tsukumogami/shirabe#1449 made review before merge something the skill always
expects and sent a step a worker can't take to its dispatcher. This design keeps
the first half whole: a coordinator the answer lets merge still reviews at its
land step and sends a pull request it authored to its Verdicts reviewer first,
and where the answer names another settler the step goes there with the
coordinator's own reading (#1449's R8). It replaces the second half's
bound-or-root routing with the settler the answer names, and leaves workers'
`Named authority:` line alone.

tsukumogami/shirabe#1473 gave Standing rows `under_session_grant` and
`session_allows`, read from the session's grant, with a row's words never
widening the grant and no gate reading either field. This design is that rule
applied to finishing steps: a row can hold a step, never let one be taken. The
two meet in `authority-read.sh`, which both now call.

## Implementation Approach

The implementation doesn't start in this unit. It waits on the workspace
authority work below, and on root coordinators getting an answer above all,
because shipping first would hold every root coordinator's finishing steps.

### Phase 1: The reader

`authority-read.sh` and its tests against a fake niwa; `posture-read.sh` and
`state-stored-set.sh --rules` moved onto it with no change in output. This can
land before the dependencies: it changes no routing.

### Phase 2: The verdict and the merge

`settle-check.sh`, its evidence key and seal; `land-check.sh` and
`land-merge.sh` moved off `bl_merge_posture`; the forged-record and mid-run
suites.

### Phase 3: The other steps and the text

The close, release and handed-back states wired to the check, `need-check.sh`
and `progress-view.sh` changed, the bound-or-root sentences replaced, and the
wording `grep` from the PRD's acceptance criteria added as a test.

### Dependencies on the workspace authority work

None of these is assumed shipped, and the skill builds nothing around their
absence. Until each lands, the step it affects holds and is reported, and never
falls back to the reports-to address or the bound-or-root rule.

- **A per-point declaration that a step needs review** (the author may not settle
  its own work), shown in the answer. niwa has the slot and no declarations yet.
  PRD D1.
- **An answer for a root session.** A root or not-dispatched session gets no
  points today, so every root coordinator's finishing step holds as `no-entry`.
  What niwa answers for a root session is that work's interface to design.
  PRD D2.
- **An addressable target** for a step the answer sends to the dispatcher or
  keeps from the author. Today the answer gives only the parent's dispatch id
  and optionally its instance, which the skill can't address. This belongs to
  the work making a workspace's gates honour the authority a session was
  dispatched with. PRD D3.
- **A teardown point.** niwa names none, so teardown's settler stays the
  workspace permission posture (R9). PRD D4.
- **Where a review goes when the answer names the session as settler.** Until
  then, the Verdicts rules' reviewer stays (R10). PRD D5.
- **tsukumogami/niwa#422**, a separate dispatch bug: a grantless session can
  dispatch a granted child by unsetting its session variable, so an answer that
  lets a session take a step is only as sound as dispatch's cap. PRD D6.

## Security Considerations

The feature is about who may take an irreversible step (a merge, a close, a
release), so its security question is whether anything in the coordinator's
reach can widen what the workspace allows.

**Forged record.** The coordinator can write any key in its own session. The
design puts nothing it can write on the decision path: the read runs inside a
koto check action, the verdict reaches the transitions as koto's captured and
sealed stdout, the transitions accept no submitted field in its place, and
`settle-check.sh` reads no context key. That rests on koto not letting the
agent write a check action's capture; an acceptance test submits a forged
verdict field at a finishing state and expects the transition unchanged. Editing
`coord/posture.json`, an evidence key, a Standing or Reversals row, a relayed
`posture_ask` answer or a review round changes nothing, and the PRD's
forged-record criterion tests exactly that.

The settings files behind the permission lists may be within the agent's
reach, but those lists can only turn a take into a hold, never widen one.

**Forged answer.** A process that can put its own `niwa` first on PATH, or set
`NIWA_BIN` or `KOTO_BIN`, can answer anything, and one that sets
`CLAUDE_CODE_SESSION_ID` or moves the instance root chooses whose answer is
read. A short `NIWA_LOOKUP_SECONDS` can only cause holds. The design doesn't claim otherwise (R14): the
workspace's own gate on the command stays the control, and the skill's promise
is only that it never acts more widely than the answer it read.

**Failure direction.** Every failure (no niwa, no session id, timeout, bad
schema, unknown value, missing entry, no target, no grant, a permission rule) holds the
step. Nothing fails open, and no failure routes the step to a settler the
answer didn't name.

**Stale answer.** Reading at each visit, and twice for the merge, closes the
window in which a declaration tightened mid-run would be ignored. A
declaration changed between `land_merge`'s read and the merge command itself is
the remaining window, a few seconds, and the workspace gate still applies to
the command.

**Permission scope and data exposure.** The new scripts run one bounded niwa
call and write one context key. They read no settings file's `env` block, print
no credential, and add no network call beyond niwa's own.

**Residual risk.** Until niwa#422 is fixed, a child dispatched around the cap
can carry a grant its parent lacked, and its answer will say so. Teardown and
the Verdicts reviewer keep today's sources (R9, R10), so they get none of the
protection above: whatever teardown reads today, it still reads, and that is
accepted until niwa names a teardown point and says where a review goes.

## Consequences

### Positive

- A workspace that declares a step needs review gets it held or routed at the
  next visit, without restarting the coordinator.
- Merge, close, release and handed-back steps read the same answer through the
  same code, so they can't disagree about what it means.
- Nothing the coordinator writes can move a step, and a reviewer can check that
  by reading one script.
- The bound-or-root sentence leaves about twenty places.

### Negative

- Root coordinators hold every finishing step until niwa answers for them, and
  a supervised coordinator holds every step sent to its dispatcher until the
  answer gives a target. That's why the implementation waits.
- One more niwa call per finishing-step visit (two for a merge), each up to
  3 seconds.
- Teardown and the reviewer passage still name a parent, by design, until their
  dependencies land.

### Mitigations

- Phase 1 lands on its own and changes no routing, so the reader can be proved
  before anything depends on it.
- Each held step's report names the step, point and reason, so a hold that comes
  from a missing dependency is visible rather than silent.
- The PRD's acceptance criteria run against a fake niwa, so every outcome is
  testable before niwa ships the pieces.
