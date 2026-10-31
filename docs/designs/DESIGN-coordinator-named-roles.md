---
schema: design/v1
status: Proposed
problem: |
  The coordinate skill has two coordinator roles, a manager over one lane and a
  director over managers, but no start setting, record row, brief field or
  report line carries which one a session runs. Briefs re-describe the role in
  prose, the top session of a lineage drifts between names, and the skill
  addresses duties only one role owes to "the coordinator". The role has to
  ride the existing start, record, continuation and brief machinery, and must
  never reach an allowance read.
decision: |
  The start takes --role manager|director, checked by coordinate-open.sh before
  any koto call; a missing role is asked for and a role that differs from the
  recorded one is refused, naming both. The record holds it as one Run row,
  role, set once and carried by every existing continuation; a record without
  it is the handover gap no-role. Every report starts with a record line a
  script prints from the live record, ending "Role: manager." or "Role:
  director.". A coordinator's brief carries the role as --role on its
  invocation line, filled by dispatch-worker.sh from the record for a
  successor and as manager for a lane. SKILL.md gains Manager and Director
  Glossary entries, a Roles section with each role's expectation list (the
  manager now reports its lane's merged pull requests up), and one role-blind
  paragraph naming where the director's allocation allowances are read. Every
  occurrence of "coordinator" is classed and one-role duties readdressed.
rationale: |
  A Run row is the one store every continuation already copies, so the role
  survives resume, carry, takeover, import and rotation with no new carry path,
  and avoiding a koto variable keeps the template at compat 2, which keeps the
  pre-change lineages the PRD tests resumable. Rendering the role into the
  invocation line makes the visible line and the setting one field, so no prose
  reaches either. Reading the record line live at print time keeps it right
  when the role is written late at the handover gate. The allowance reads use
  the cap, the scope and decisions, and niwa authority check, none of which
  looks at the role.
upstream: docs/prds/PRD-coordinator-named-roles.md
---

# DESIGN: Coordinator Named Roles

## Status

Proposed

## Context and Problem Statement

The coordinate skill runs two kinds of coordinator: a manager, which runs one
lane (a roadmap's features or one discipline rotation) through the workers it
dispatches, and a director, which runs over managers, dispatches them and
reviews what they finish. The PRD asks that whoever starts a coordinator names
which of the two it runs, that the name shows up in the session's record, in
its first report and in every brief that starts a coordinator after it, and
that the skill's text addresses each duty to the role that owes it. It also
asks that a role change only what a session is expected to do, never what it
is allowed to do.

None of the machinery that would carry a role has a place for one today.

**Start settings.** `scripts/coordinate-open.sh` reads the start's arguments,
maps each flag to a koto variable (`--discipline` to `DISCIPLINE`, `--host` to
`HOST_REPO`, `--cap` to `CAP`, `--parked-bound`, `--rotation-days`,
`--reports-to`), and hands them to `koto init`, which refuses a malformed value
against the variable's pattern with wording from `coordinate-open.wording.tsv`.
A missing discipline host makes the opener print `ask=host` and exit 10 before
any session exists. Text after `--` never becomes a variable; `SKILL.md` says a
setting stated in words there ("host repo: acme/widgets") is passed as its
flag. There is no role flag for the PRD's start setting to attach to, and its
ask for an unnamed role needs the same ask channel the host uses.

**The record.** A run's record is a set of koto context keys in its session
(`references/state-keys.md`): `record/run`, `record/holdings`,
`record/decisions` and the rest, each written by one owning script that
`state-write-core.sh` enforces (a write by any other script exits 65) and read
through `state-read.sh`. The Run section holds rows such as `cap`,
`coordinator` and `reports-to`, written by `state-stored-set.sh --run`. The
handover read, `state-handover.sh`, prints the facts a successor needs and
lists gaps; the `reconcile` state runs it with `--check` as the handover gate,
and a missing `reports-to` row is the gap `no-reports-to`. The PRD asks that
the role be one stored value inside this container, with one writer and read
through the one reader, that the handover read print it, and that a record with
no role be a gap that holds the gate the way a missing `reports-to` row does.
It also asks (its sixteenth requirement) that "role" stop meaning two things:
`reports-to` is described today as `<role>` or `<role> at <address>`, where
"role" means whoever the coordinator reports up to.

The PRD's non-functional requirement says the value stays "within the record's
size budget". The record no longer has one: `SKILL.md` says "The state has no
size budget", and the tests that once pinned it now assert that a record of
about 60,000 bytes still reads. This design reads that requirement as: the role
adds one short row, and the existing large-record tests keep passing.

**Continuations.** Five ways of continuing a run copy different things. A
resume reopens the same session and copies nothing; settings given with the
start are ignored. A carry on the same host copies every `record/` and `legs/`
key into a new session, but takes its variables from the new invocation. A
takeover copies all of the predecessor's variables, `REPORTS_TO` included, and
carries `record/` and `legs/`. An import is a takeover of an imported copy and
accepts only `--discipline` and `--host`. A discipline rotation that carries
its predecessor copies named sections (Run among them) through
`state-open.sh --carry`; one that doesn't is a new run. There is no single list
of carried facts, so nothing yet keeps a recorded role across all five or
refuses a start that names a different one.

**Briefs.** `scripts/render-brief.sh` renders every brief from one input
document. It has no notion of a brief's kind: a successor brief is told apart
from a lane brief only by its grant (`"own"`, allowed only when the entry point
is `coordinate`), and a lane brief gets no grant. The `coordinate` row in
`references/entry-points.tsv` allows no flags, so a brief can pass no setting
at all to the coordinator it starts. Its golden files
(`testdata/brief-golden/*.txt`) pin the worker brief byte for byte, so the
role line the PRD wants in coordinator briefs has to leave worker briefs
unchanged.

**Reports.** `SKILL.md` requires every report to name the record (its session
name and host repository), but fixes no wording for that line. The PRD requires
the role on that same line, in one fixed place, within the first five lines of
the first report, and requires that a report name its own role with `manager`
or `director` and no other word.

**Skill text.** The word `coordinator` occurs 244 times across `SKILL.md` (92),
the koto template (74) and the references (78). "Manager" appears ten times,
every time meaning the workspace manager; "director" appears once; "lane
coordinator" once. There is no Glossary entry for either role and no
expectation list, so every one-role duty is addressed to "the coordinator".

**Allowances.** `scripts/posture-read.sh` reads the session's posture from
settings and hooks and calls `niwa authority check --json --session <id> -C
<instance> --point merge-pr --point close-issue --point cut-release`. niwa's
answer carries the binding, the grant, the level and, for each point asked,
who settles it (session, dispatcher or person), computed from the level and any
declaration for that point; a point with no declaration is answered from the
level alone. A standing row can narrow that answer but never widen it. niwa
also has a `--role` flag on `niwa dispatch` that grants every authority a role
declared under `[authority.roles]` names. That is a third meaning of "role",
and the one this design must keep the coordinator role away from: the PRD
requires that naming a coordinator's role grant nothing and withhold nothing,
so the posture read, the authority check, a dispatched grant and the settler of
every step come out the same for either role.

**Where this meets the dispatcher-review design.** The dispatcher-review design
(`docs/designs/current/DESIGN-coordinator-dispatcher-review.md`) defines "the
reviewer" once in the Glossary as whoever dispatched a coordinator (a person
for a root coordinator), states the review rule in Bounds and Authority, and
tells a coordinator that may not merge to send its own reading up. The role and
the dispatch relationship stay separate: a manager or a director can be root or
bound. The two designs meet where the director's expectation list carries the
own-reading duty, where a manager a director dispatched has that director as
its reviewer, and in the sentences that design pinned, which keep their words.

## Decision Drivers

- **A role is an expectation, never an allowance.** Nothing the design adds may
  make the role an input to the posture read, `niwa authority check`, a grant,
  a cap or the settler of a step. Where the director's allocation duty needs an
  allowance (its worker budget, its lanes, whether it may change a manager's
  cap), the design names the read that answers it instead of building one.
- **No second container.** The role lives in the record's existing container,
  written by an existing section's writer, read by `state-read.sh`, and carried
  by the continuation paths that already exist. No new store, file, GitHub
  surface, carry path or takeover path.
- **Constrained and checked before a session exists.** The role setting
  follows the start's existing rules: a closed set of values, refused before
  `koto init`, and free text after `--` changes it only as the role stated in
  words.
- **Asked, never defaulted or inferred.** A new run with no role asks once
  through the same channel the host uses; nothing reads a role out of prose,
  names or holdings.
- **Survives every continuation, refuses a change.** Resume, carry, takeover,
  import and carried rotation keep the recorded role with no step by hand; a
  start that names a different role is refused before anything is written.
- **The renderer owns the role line.** One fixed line, written from a field,
  on successor and lane briefs only; the worker brief stays byte-identical to
  its golden files.
- **One fixed record line in reports.** The role sits in one fixed place on the
  line naming the record, and that line is printed by a script rather than
  composed by the agent each time.
- **Build on the dispatcher-review design.** "The reviewer" keeps its one
  definition; the fragments the rule coverage test pins keep their words.
- **Old records keep working.** A record with no role row reads, resumes and
  carries; the gap names what is missing and how to fill it.
- **Reviewable change.** The sweep of `coordinator` is a classification a
  reviewer can repeat, and changes to pinned sentences, the template's compat
  record and the brief golden files are named so the plan can sequence them.
- **Public content.** Nothing private, no banned vocabulary, no attribution.

## Considered Options

### Decision 1: How the role is passed at start, stored, carried and guarded

The PRD leaves the setting's name and shape, the record key, the gap's name
and the continuation mechanics to this design. Whatever is chosen has to meet
R1 to R5 together, and adds two constraints of its own: the role stays out of
every allowance read, and the `reports-to` value is described without the
word "role".

Key assumptions:

- A koto template variable would change the template's fingerprint and force a
  compat raise from 2 to 3, which refuses a takeover or import of a live run
  opened on the older template. Those runs are the pre-change lineages the
  PRD's fourth outcome is about.
- An import can only be checked after `koto session import` lands the copy on
  this host, because koto can't read a copy in place. A refused import leaves
  the copy here with nothing in its record written, and that copy is the run
  moved, not a new session.
- A new run has no record while the opener runs (`state-open.sh` seeds it later
  in `record_open`), so the role reaches the seed as a value the opener prints.

#### Chosen: A Run-section `role` row, checked and guarded by the opener, with no template variable

**The flag.** The start takes `--role manager|director`. When the start's
decisions state this run's own role in words ("role: director"), the agent
passes it as `--role`, the way a host stated in words is passed today; a
mention of another session's role ("report to the director") doesn't count,
and when in doubt the agent passes nothing and lets the opener ask. A
coordinator another coordinator dispatched gets `--role` from its brief's
invocation line (Decision 2). The opener never parses the decisions. The flag
belongs to the coordinate opener alone: nothing passes it to `niwa dispatch`,
whose own `--role` grants authorities.

**The check.** `coordinate-open.sh` reads `--role` beside `--continues`, outside
the variable pairs, right after it parses the args file and before any koto
call, on every path including import (whose "no other setting" rule widens to
accept it). Any value but `manager` or `director` prints
`refused=invalid_role` and exits 2 with a new `invalid_role` row in
`coordinate-open.wording.tsv`: "The role `{value}` must be manager or
director." A repeated `--role` is a usage error. Nothing opens.

**The stored value.** One Run row, key `role`, value `manager` or `director`.
`state-schema.jq` adds `role` to the Run keys, accepts only those two values
and at most one row. Every write to an existing record goes through
`state-stored-set.sh --run role <value> --by <who>`, which is set-once: with no
row it writes one, with the same value it changes nothing, and with a
different value it exits 65 naming both. The one other place a row is born is
`state-open.sh`'s seed, the write that already creates a record's sections.
Readers use a new `state-read.sh --run` mode, which reads `record/run` without
a sealed find and treats a failed read as an error. A structure test pins the
two writer scripts (`state-stored-set.sh`, and `state-open.sh` for both its
seed and its `--carry --role` path), and pins the readers as an allow-list: only the scripts this
design names (the opener, `state-handover.sh`, the report's record line and
`dispatch-worker.sh`'s brief path) may read the `role` row, so a script added
later that reads it fails the test. That keeps `posture-read.sh`,
`need-check.sh`, `board-lib.sh` and `dispatch-worker.sh`'s grant path off the
row without naming each one, and the same test pins that no script passes
`--role` to `niwa dispatch`.

**Who writes it, path by path.** Whenever the opener knows the role it prints
`role=<value>` with its result lines.

| Path | How the row gets there |
|---|---|
| New run (roadmap, a discipline's first rotation, a fresh start with no legacy record) | `state-open.sh` requires `--role` on a fresh seed and writes the row in the seed; the `record_open` directive passes the printed `role=` |
| Rotation that carries its predecessor | the Run section, row included, comes over with `state-open.sh --carry`; for a role-less predecessor, `--carry --role` adds the row only when the copy has none |
| Resume | carried in place; for a role-less record given `--role`, the opener writes the row through `state-stored-set.sh` before printing `outcome=resumed` |
| Takeover, and an import on koto 0.32 or later | the row rides `--carry record/`; for a role-less record given `--role`, `finish_takeover` writes it beside the `coordinator` row |
| Import on an older koto | a resume of the copy, written as for a resume |
| Carry, and a fresh start that imported a role-less legacy record | the row rides the copy when the source has one; otherwise it is written at `reconcile` through the `no-role` gap fix, from the printed `role=` |

**Asking.** After the candidate read and before anything is written, the
opener prints `ask=role` and exits 10 when the start has no `--role` and there
is no recorded role to continue. Its message says the role is the person's
call, manager or director, asked once with no recommendation drawn from the
scope, cap, holdings or names, and that the start is then re-run with
`--role`. A discipline start missing both host and role asks for the host
first. An import never asks after its copy lands (a re-run would be refused
`import_name_taken`); a role-less import with no `--role` goes on, and the
`no-role` gap asks at reconcile before anything is dispatched.

**The gap.** `state-handover.sh` prints `role` (the row's value, or null). With
no row it lists the gap `no-role`, fix `state-stored-set.sh --run role
<manager|director> --by <who named it>`. The reconcile directive says to fill
it from the `role=` the opener printed or, if it printed none, by asking the
person once, never from names, briefs, entries or the dispatch topic. The
handover gate holds until it is filled, as it does for `no-reports-to`.

**Refusing a change.** Right after the candidate read and before
`takeover_check`, the rebind, `koto init` or a carry, the opener reads the
candidate run's role through `state-read.sh --run`. That one place covers
resume, carry, takeover (including a re-run after a cut-short fence) and a
carried rotation, whose candidate is the ended rotation. A given `--role` that
differs from the recorded one exits 2 with `outcome=refused`,
`reason=role-mismatch`, and a `role_mismatch` wording row: "{run} is recorded
as {recorded}; this start names {asked}. A run keeps its role across every
continuation; nothing was written and {run} goes on as it was. Start again
naming {recorded}, or no role, or start {asked} as a new lineage." An import
runs the same check on the copy right after it lands, before the
`record/host` write, the rebind and the fence. Naming the recorded role again
is accepted; naming one for a role-less record isn't a change.

**`reports-to` in other words.** The value is described as `<name>` or `<name>
at <address>`: who this run reports up to (a person, or the coordinator that
dispatched it) and, for a coordinator, its messaging address. The new wording
replaces the old in `SKILL.md`, `references/state-keys.md`, the comment and
refusal message in `state-schema.jq`, `state-stored-set.sh`'s usage and the
`no-reports-to` fix string in `state-handover.sh`. The schema accepts the same
values, so `the human` still passes.

No template variable, state or gate is added, so the template stays at compat
2; `coordinate.compat.json` re-records its gate-script digest because
`state-handover.sh` runs behind the reconcile gate.

#### Alternatives Considered

**A template variable `ROLE` only.** Checked by `koto init` against a pattern,
as `CAP` is. Rejected because a variable isn't in the record and has no
section writer, so it can't be read through the record's one reader or printed
by the handover read; a resume applies no settings, so it can't reach a run
opened before the change; and it forces the compat raise that strands live
pre-change lineages.

**A variable and a Run row.** The pattern check for free, plus a stored value.
Rejected because it pays the same compat raise to remove one agent copy of a
value the opener has already checked, and holds the role in two places.

**A `record/meta` field written by the opener.** The opener can write meta
without a sealed find, so it could fill a carried run while it runs. Rejected
because `core_carry`, the seed and the legacy import all rebuild `record/meta`,
so every carry and rotation would drop the role unless three sites learned a
new field, and meta has no section writer whose fix line could close a gap.

### Decision 2: How a coordinator's brief carries the role

R7 and R8 settle what the role line says and who reads it. What's left to this
design is where the renderer gets the role (the record for a successor,
`manager` for a lane) and how a worker brief keeps no role line and stays
byte-identical to its golden files.

Key assumptions:

- `--role` is a token in the args file, as Decision 1 has it. If it were an
  option on the opener's own command line, as `--dispatched-by` is, the brief
  route wouldn't reach it.
- Fixed text in every rendered brief already uses lowercase "head" (the review
  round line and the grant line). The PRD's grep allows only `HEAD` in
  capitals, and rewording that text would break the worker golden files. This
  design reads the allowance as git's head ref in either case; the
  implementation's reviewer applies it so.
- A brief can start a roadmap coordinator only: the `coordinate` row of
  `references/entry-points.tsv` takes a positional and no flags, so no brief
  starts a discipline coordinator today, and this design adds no route for one.

#### Chosen: The invocation line is the role line

`render-brief.sh` takes a new input field `role`, with the values `manager` and
`director`. It is required when the entry point is `coordinate`, refused on
every other entry point, and absent from worker briefs, so the `base`, `min`
and `leg` golden files don't change. `dc_invocation` in
`dispatch-common.sh` appends `--role <role>` after the positional, so the
Goal's existing invocation line becomes the one role line, with the fixed
wording:

`Run \`/shirabe:coordinate <roadmap-path> --role <role>\` in <owner/repo>.`

The `niwa dispatch` prompt carries the same invocation, so the started session
runs `/shirabe:coordinate <roadmap> --role <role>`; its first step writes those
tokens into the args file and the opener checks `--role` as Decision 1 says.
One field drives both the visible line and the setting, so they can't
disagree, and no prose reaches either.

`dispatch-worker.sh` writes `.role` itself in `read_inputs`, beside the
`reports_to` and `dispatcher_session` writes and before `resolve_grant`,
overwriting anything the input gave:

- an entry point other than `coordinate`: the field is deleted;
- `coordinate` with a positional naming this run's own roadmap (the scope
  comparison `dispatch-worker.sh` already makes): a successor, whose role is
  the record's Run `role` row; with no row the dispatch is refused at exit 1,
  naming the command that sets it;
- `coordinate` with any other roadmap: a lane brief, role `manager`.

Scope decides, not the `"own"` grant, because scope is what makes the started
session take the run over, and a grant is an allowance.

`references/brief-template.md` documents the field (written by the script,
never by hand, absent from worker briefs), and where it describes the Goal it
says: the Goal names the concrete scope and work (which roadmap or lanes, which
units, which decisions) and makes no general statement of what a role owes; it
names no role for the coordinator the brief starts, except that a manager's
brief may name the director it reports to as its reviewer and a director's
brief the managers it dispatched or reviews; the role travels only as
`--role` on the invocation line; and the started coordinator reads its duties
from the skill's list for that role. `render-brief.sh`'s header and the
`entry-points.tsv` header comment say where `--role` comes from; the
`coordinate` row stays without flags.

Tests: the worker golden files stay as they are; `render-brief_test.sh` gains
a section asserting exactly one role line for each role, `--role manager`
rendered even when the Goal says "you are the director", refusals for `lead`,
`Director`, an empty or missing role on `coordinate`, a role on another entry
point and `--role` in `entry_args`, and the PRD's grep over a rendered lane and
successor fixture; `dispatch-worker_test.sh` points its successor input at the
fixture run's own roadmap with a `director` row, and adds lane, worker and
missing-row cases.

#### Alternatives Considered

**A separate role line, with `--role` also on the opener command.** A line such
as "Role: manager" above the Goal, and the setting passed on the opener's
command line. Rejected because the role then appears on two lines, which fails
the one-role-line test, the opener would need two ways in for one setting, and
the dispatch prompt wouldn't carry it.

**A separate role line plus `--role` in the invocation.** Rejected for the same
two-line failure.

**A role line only, transcribed by the started coordinator.** Rejected because
it relies on the agent copying a line into its arguments; a miss either stalls
on an ask or is refused, and a wrong copy is the drift this change exists to
stop.

**Successor told apart by the `"own"` grant.** The existing marker. Rejected
because a grant is an allowance, and a lane wrongly given `"own"` would start
as a director over a new scope with nothing to refuse it.

### Decision 3: The record line every report carries

Every report already has to name the record (its session name and host
repository). R6 puts the role on that line; this design fixes the line's
wording, where it sits in the first report, and when its role is read.

Cross-validation shaped this decision. Under Decision 1, a carry of a role-less
record (and a fresh start that imported a role-less legacy record) gets its
role row only in `reconcile`, through the `no-role` gap fix. The reconcile
report is sealed earlier, in `reconcile_pass`. A record line sealed with the
report would therefore miss the role in exactly the case the PRD's lineage
criteria test, so the decision was re-run with that constraint.

Key assumptions:

- Once the handover gate passes, the role row exists on every path.
- No state, gate or variable is added; directive prose changes don't move the
  template's fingerprint.

#### Chosen: The record line is read from the live record when a report is printed, never sealed

**The wording.** `SKILL.md` documents one template, with the role always the
last word before the closing period:

```text
Record: session `<session>` on `<owner>/<repo>`, address `<address>`. Role: manager.
Record: session `<session>` on `<owner>/<repo>`. Role: director.
```

The address clause appears only when the Run `coordinator` row exists and
differs from the session name. The role slot holds exactly `manager` or
`director`; there is no form for a missing role, because a line without one is
never printed. A test can check the line against
``^Record: session `[^`]+` on `[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+`(, address `[^`]+`)?\. Role: (manager|director)\.$``.

**One producer.** `reconcile-report.sh` holds the template once, as a jq
`def record_line`, behind a new pure `line` mode that reads `{session, host,
address, role}` on stdin. `coordinate-report.sh --session S --record-line` is
the only reader of the live values: the Run `role` and `coordinator` rows
through `state-read.sh --run`, and the host through `coord-log.sh run-facts`.
It prints the line and nothing else; it exits 4 when the record holds no role
row (its stderr names the `no-role` fix) and 65 when the record can't be read.

**The first report.** The sealed reconcile report stays as it is: no record
line, no role, the same facts, schema and seal. `reconcile-report-get.sh --md`
adds the line when it prints, after its seal and import checks: it calls
`coordinate-report.sh --record-line` and passes the result to
`reconcile-report.sh md --record-line <line>`, which prints `# Reconcile
report`, a blank line, the record line as line 3, a blank line, and the
unchanged `Scope: ...` line as line 5. With no role row, `--md` exits 4 and
prints nothing, so a first report can't go up without its role. `--check` and
the JSON mode don't read the line, so the reconcile gate and the seal are
untouched.

**The order in `reconcile`.** The directive's paragraphs swap: close every gap
`state-handover.sh --check` names first (the `no-role` fix among them), then
print with `reconcile-report-get.sh --md` and report that up, then submit
`reconciled: reported`. A role-less carry's very first report therefore names
the role written by the gap fix, with no second reconcile visit.

**Later reports.** Every later report, the closing one included, starts with
the line `coordinate-report.sh --session <session> --record-line` prints, pasted
as printed. Both paths call the same command over the same record, so the
lines are the same template from the same values.

**Where the docs say it.** `SKILL.md`'s Reporting section replaces "Name the
record in every report (its session name and its host repository)" with the
template in a fenced block, followed by where the first and later reports take
it from and that a report calls its own role only by that word.
`references/loop.md` and the template's `reconcile_pass` prose point the agent
at `reconcile-report-get.sh --md` rather than the stored report key for what
goes up; the `state-keys.md` and template sentences that say to report the
session name as the record point at the record line.

**A defect fixed on the way.** `coordinate-report.sh` accepts its closing
`record=` line only as a GitHub URL, but the record is now named by its session
name, so that line appears never to print. The script and its test are edited
anyway, so the change accepts a session name beside the legacy URL and adds a
test case. No acceptance criterion depends on it.

#### Alternatives Considered

**Seal the record line with the report.** Rejected because the role can be
written after the seal (the role-less carry) and the address can change, so the
sealed line would be stale or roleless in the first report.

**Seal the opener's role with the report.** Rejected because it needs a second
stored copy of the role (a context key, or a variable and the compat raise),
and the address would still go stale.

**Write the role row before `reconcile_pass`.** Rejected because it adds a
state, which raises compat, and a carry has no sealed find until
`record_find`.

**Print `Role: not recorded.` and let the gate hold.** Rejected because the
first report of a role-less carry would then name no role, failing the
first-report criteria.

**The agent writes the line from the template in `SKILL.md`.** Rejected because
a line composed by hand each time is how the role drifts; a script prints it.

### Decision 4: The expectation lists, the allocation allowance, and the manager's report of its lane's pull requests

R10 fixes what each role's list must hold at the least, and R11 the Glossary
entries; both leave the wording and the place to this design. The director's
allocation duty is the one item that touches an allowance, so this decision
also names the read that answers it.

The PRD also leaves one gap. The director's alignment reading covers "the
worker pull requests each manager reports ready or landed in its lane", but
nothing in the manager's list says the manager reports them.

Key assumptions:

- A director's lanes are read from its scope, its decisions and its Run
  arguments row; no new row names them.
- The authority effort names the decision point for changing a dispatched
  coordinator's cap. Until it does, every cap change is escalated.
- Ready worker pull requests already reach the director: `land` is entered
  only from `verified_confirm`, which sends the verify report up, and the
  progress table carries `Ready to merge` rows. Landed ones don't: a merge
  clears the holding's link, so a director learns of a merge in a lane only
  by reading GitHub.

#### Chosen: A Roles section after the Glossary; the manager reports its lane's merged pull requests in the report it already owes; allowances read role-blind in Bounds and Authority

**Place.** A new `## Roles` section sits between `## Glossary` and `## The
Record`. The Glossary keeps definitions only: the Coordinator entry keeps its
pinned opening phrase and adds that it runs in either role; `- **Manager** --`
(a coordinator that runs one lane, a roadmap's features or one discipline
rotation, through the workers it dispatches) and `- **Director** --` (a
coordinator over managers: it dispatches them and reviews what they finish)
follow it directly; a `- **Workspace manager** --` entry names the tool and
says it is never the role. The template's start state, which already lists the
Glossary's words, gains `manager` and `director` and a clause telling the
session to read the Roles list for the role its record holds.

**The lists.** Proposed wording:

```
## Roles

Your record holds your role, `manager` or `director`. Read the list for it and
the list both roles share. A list says what you owe, never what you're allowed
to do: that comes from Bounds and Authority and the workspace's authority
configuration, and it's the same for either role.

**Both roles**

- Call yourself only by the role your record holds, on your report's record
  line and everywhere else in it.
- Report up to your reviewer as Reporting says, naming your record in every
  report.
- Brief a successor with the role your record holds; a successor never changes
  it.

**Manager**

- Run one lane: the roadmap's features or the discipline rotation your scope
  names. Anything outside it goes to your reviewer as a proposal.
- Dispatch and brief the workers your lane's units need, from
  `references/brief-template.md`.
- Review your workers' pull requests at your land step: nothing a worker
  reports lands until you've checked it there.
- Send every pull request you author, your verdict and reopen edits included,
  to your reviewer before it merges.
- Report your lane's worker pull requests to your reviewer by link: each ready
  one in your verify report and your progress table's `Ready to merge` rows,
  and, in the report you owe after a land, every one that merged in your lane
  since your last report, whoever merged it.

**Director**

- Dispatch and brief managers, one lane each, from the scope and decisions you
  were given.
- Be the reviewer of each manager you dispatched.
- Read a manager's finished work yourself and send your own reading up, never
  the manager's report passed through (Bounds and Authority).
- Read for alignment. Your reading covers the work all your managers push: the
  pull requests a manager authors and sends you, and the worker pull requests
  each manager reports ready or landed in its lane. Start from what they send;
  read GitHub only to confirm a pull request's state or to rebuild that set
  after a succession. Ask whether the work fits the other lanes and the
  direction of the effort. It isn't a correctness review: correctness stays
  with each worker's review round, the manager's land step, and the manager's
  own checks before it sends a pull request it authored. When work in two or
  more lanes heads in diverging or conflicting directions, name the pull
  requests and the conflict to every manager involved and in your next report.
- Decide, within the worker budget and the lanes you've been given, which of
  your lanes advance at any time, and say which in your reports. Bounds and
  Authority says where each is read.
```

None of the three lists contains `grant`, `merge authority`, `may merge` or
`settle`, the allocation item names no cap value, and none says a director may
change a cap.

**The manager's report of its lane's pull requests.** This design settles the
PRD's open follow-up: the manager owes it, as an expectation. The ready half
adds no new duty, since the verify report and the `Ready to merge` rows already
carry each ready pull request up. The landed half is the one new obligation:
in the report it already owes after a land, the manager names by link every
worker pull request that merged in its lane since its last report, whoever
merged it (a merge the director or a person takes reaches the manager through
the `merged` wait event). The channel is the manager's existing reports to its
reviewer, and the lane is the record the report names, so the item needs no new
message, row or script. Without it a director would poll GitHub for every link
to learn a merge happened, and its reading would drift into reading worker
pull requests on its own.

**Allowances, read role-blind.** One paragraph in Bounds and Authority, after
the cap paragraph and outside both lists:

```
**What you allocate is read, never assumed.** Each coordinator you dispatch
counts against your cap for as long as it runs, so your cap is your worker
budget: how many of them, and any workers you dispatch yourself, run at once.
A total across their lanes that your decisions, or later direction from
whoever dispatched you, state is a decision you were given, and going past it
is asked. The lanes you move are the ones your scope and decisions name.
Whether you may raise or lower the cap of a coordinator you dispatched is
asked when you'd make the change, through the same `niwa authority check`
lookup the posture read makes, with that change's decision point. Only an
answer that is bound, with that point's decider `session`, makes the change
yours; on any other answer, a failed lookup, or no point to ask, escalate it
once as a decision entry carrying the answer. A change you make goes to that
coordinator as direction through its dispatcher's channel, and it writes the
new cap in its own Run `cap` row; you never write another run's record.
```

Each read is something that already exists and doesn't look at the role: the
cap is enforced at dispatch and already counts a dispatched coordinator, the
lanes are the start's scope and decisions, and the cap-change read is the
authority lookup keyed on session and decision point. The posture read is
unchanged, so it and `niwa authority check` print the same answer for either
role.

The dispatcher-review design's own-reading paragraph in `SKILL.md` gains one
sentence, with none of its words changed: when the pull request comes from a
manager's lane, the director's reading is the alignment reading its Roles list
names, and the board, the worker's review round and goal fit are the manager's
checks, which the director confirms happened rather than repeats.

#### Alternatives Considered

**Duties folded into the Glossary entries and Bounds and Authority.** The lists
as sub-bullets under the Manager and Director entries. Rejected because it turns
definitions into checklists and puts several lines of duties between the
Manager and Director entries, against the PRD's "directly after the
Coordinator entry".

**No new manager duty; the director pulls; the report as an open question.**
Rejected because the PRD's scope sentence for the director's reading assumes
the manager reports landed pull requests, nothing today does so per pull
request, and the director would poll GitHub to learn of every merge.

**Allowances read once at start and kept in the record.** The cap-change point
added to the posture read's lookup and sealed in `grant_check`. Rejected
because the point isn't named yet, so the seal would ship a constant; a fresh
read at the moment of change is needed anyway, since a narrowed configuration
must apply at once.

**A cross-lane worker total, defaulting to the managers' starting caps.**
Rejected because nothing counts that number (the decisions text sets no
enforced value) and the default invents one. A total stated in the decisions
is still honoured, as a decision the director was given.

### Decision 5: How the sweep of "coordinator" is done and recorded

R12 and R13 require every occurrence of `coordinator` in `SKILL.md`,
`references/*.md` and the koto template to be classed, each one-role
occurrence readdressed, and positional names replaced, with the
dispatcher-review design's pinned sentences kept word for word. This design
decides how the 244 occurrences are found, classed and recorded so the
classification can be checked.

Key assumptions:

- A director runs the same loop on its own holdings (its lanes, plus any
  workers it dispatches for its own documents), so sentences about dispatching,
  landing, verdicts, teardown and reporting stay true of both roles. If a
  sentence is true only of a manager, the substitution test below catches it.
- The table fits a pull request description (a trial run was about 27 KB).

#### Chosen: A generated occurrence list, classed by hand with one stated test per class

**Classes and their test.** Each occurrence is read in its sentence with
"coordinator" replaced by "manager", then by "director".

- **Not a duty**: the occurrence tells no session what it owes. A definition
  (the Glossary, the template's term list, the skill's description); a scope
  name ("roadmap coordinator", "discipline coordinator"); a dispatch or
  succession relation ("root coordinator", "the coordinator that dispatched
  you", "a coordinator above you", "predecessor", "successor"); or a literal
  token (a script name such as `resolve-coordinator.sh`, a row such as `--run
  coordinator`, a `coordinator=` line, a status value). Substituting a role
  name would make it wrong or meaningless.
- **Either role**: the sentence stays true and owed under both substitutions.
- **One role**: true or owed under only one. The cross-check is Decision 4's
  two lists: a duty that exists only because of the manager-director relation
  (dispatching or briefing a lane, a lane brief's grant, the alignment reading,
  allocation; running exactly one lane) is one-role. Each is rewritten to name
  `the director`, `a manager` and so on, and re-read.

Doubt goes to the lists first; a sentence still unclear is rewritten so it is
plainly true of both or plainly names one. Every row in the categories the
PRD's spot-check names (dispatching a worker, landing a worker pull request,
giving a milestone verdict, dispatching a coordinator, handing a successor a
grant) carries a short note with the reason for its class.

**Positional names.** "Lane coordinator" becomes "manager" (the template's "A
lane coordinator gets none" becomes the director's "A manager you dispatch as a
lane gets none"); the dispatch table's "nested coordinator" row becomes a
director's row; "a nested coordinator's reply" becomes "the reply of the
coordinator you escalated to".

**Producing the table.** A command nobody commits, whose text goes in the
implementation pull request:

```
perl -ne 'chomp; while (/(?<!\w)coordinators?(?!\w)/gi) { my $s = $-[0] > 30 ? $-[0] - 30 : 0; printf "%s\t%d\t%s\n", $ARGV, $., substr($_, $s, $+[0] - $s + 20) } close ARGV if eof' \
  skills/coordinate/SKILL.md skills/coordinate/references/*.md skills/coordinate/koto-templates/coordinate.md
```

It prints one row per occurrence, and its count matches `grep -oiwE
'coordinators?'` by construction (244 at this design's base). The implementer
classes every row at the branch's base, rewrites the one-role and positional
sites, reruns the command after the last commit that touches the three file
sets, carries each class forward by phrase, classes the occurrences the change
adds (the Glossary, the Roles section, the role setting text), and publishes
the table in the pull request description with columns File, Line, Phrase,
Class and Note, line numbers stated "as of" the head commit. Working copies
live outside the work tree; nothing goes under `wip/`.

**Pinned sentences.** The dispatcher-review fragments (`never whether the
review happens`, `once its review is done`, `your own reading`, `without the
reviewer's review`, and the one `**The reviewer** --` entry) sit in either-role
or not-a-duty sentences, so none is edited. A rule-coverage row whose phrase
must change is edited in place with a `changed:` note, never retired. Template
wording changes don't move its fingerprint.

**"Workspace manager".** Every mention of the tool keeps "workspace" before
"manager", and the pinned keep-alive sentence is untouched.

**Checks beyond the PRD's grep.** The PRD's line-based grep for positional
names misses a name wrapped across a line break: the template's "A lane /
coordinator" is split over two lines. The implementation also runs the
positional-name pattern over each file with whitespace squeezed (`tr -s
'[:space:]' ' '`), and adds "nested coordinator" to the pattern.

A trial classification of all 244 occurrences found two in the one-role class
(both in the template's dispatch passages) and three positional names; about
145 are either role and about 97 not a duty.

#### Alternatives Considered

**A table built by hand, as the dispatcher-review change did for "a person".**
Rejected because typing 244 rows by hand invites count and phrase errors, and
without a stated test per class a reviewer can't repeat the classing.

**A committed ledger with a test.** Rejected because the PRD puts the table in
the pull request description and leaves mechanical enforcement out of scope,
and line drift would make a committed ledger a cost on every later edit.

**Rewriting every duty sentence to name a role.** Rejected because it
contradicts the Glossary's "coordinator means either role" and churns about
145 sentences and several pinned rule-coverage phrases.

## Decision Outcome

The five decisions make one path for the role, from the person or coordinator
that names it to every reader that shows it. A start names the role as
`--role`, either typed by a person (or passed from a role stated in words in
the decisions) or rendered into the invocation line of the brief that started
the session. The opener checks the value before any koto call, asks when there
is none to continue, and refuses one that differs from the recorded role. The
record holds it as one Run row with one writer for existing records and one
seed, and every continuation already copies the Run section, so nothing new is
carried by hand. The handover read prints it and holds the gate while it's
missing. Every report starts from a record line a script prints from the live
record, and a successor's or lane's brief takes its role from the record or
from the lane rule, never from prose. The skill tells each role what it owes in
one Roles section, and says in one role-blind paragraph where each allowance
the director's allocation duty spends is read.

Cross-validation found one conflict and one naming difference. The record line
first assumed the role row was written before the reconcile report is sealed;
the role-less carry writes it later, at the handover gate. The record line was
re-decided so it's read live at print time, and the reconcile directive closes
its gaps before the first report goes up. The sweep and the record decision
described the `reports-to` value with different placeholders; this design uses
`<name>` throughout.

The role reaches no allowance. It isn't a koto variable, it isn't passed to
`niwa dispatch`, and a structure test pins that the posture read, the
reserved-step check, the merge re-read and the grant path never read the row.
What a director allocates is read from its cap, its scope and decisions, and
`niwa authority check` at the moment of a cap change, none of which looks at
the role.

**Where this meets the dispatcher-review design.** That design's Glossary entry
for the reviewer, its review rule and its pinned fragments stay word for word.
The director's list carries its own-reading duty ("send your own reading up,
never the manager's report passed through"), the manager's list carries its
rule that a coordinator's own pull requests go to its reviewer, and a manager a
director dispatched has that director as its reviewer through the existing
`reports-to` row and the brief's dispatcher block. Role and dispatch
relationship stay separate: a manager or a director can be root or bound, and
nothing in this design reads one from the other.

**The PRD's requirements, and where each is met.** Every requirement is met;
none is deferred.

| Requirement | Met by |
|---|---|
| Role named at start, two values, refused otherwise (R1) | Decision 1, the flag and its check; Decision 2 for a dispatched coordinator |
| Asked, never defaulted or inferred (R2) | Decision 1, `ask=role` and the `no-role` gap's fix wording |
| One stored value, one writer, gap holds the gate (R3) | Decision 1, the Run `role` row and `no-role` |
| Every continuation keeps it (R4) | Decision 1, the path table |
| No change across a succession (R5) | Decision 1, the `role_mismatch` refusal and the set-once writer |
| Reports name it on the record line (R6) | Decision 3 |
| Coordinator briefs carry it on one rendered line (R7) | Decision 2 |
| Successor reports its brief's role (R8) | Decisions 2 and 3: the brief's `--role` becomes the record's row, which the record line prints |
| Old names stop at the first handover (R9) | Decision 1 reads the role only from the flag, the brief's invocation or the record; Decision 4's shared item |
| Expectation lists (R10) | Decision 4 |
| Glossary entries (R11) | Decision 4 |
| Every duty names its role (R12) | Decision 5 |
| One name per role (R13) | Decision 5, positional names |
| Expectation, never allowance (R14) | Decisions 1 and 4, and the structure test |
| Meeting the dispatcher-review requirements (R15) | This section, and Decision 5's pinned sentences |
| "Role" means one thing in the record (R16) | Decision 1, `reports-to` in other words |
| No second container (R17) | Decision 1: a Run row, existing writers and carry paths |
| Settings stay constrained (R18) | Decision 1, the check before koto |
| Pinned text and checks (R19) | Decisions 2 and 5; Implementation Approach |
| Public content and vocabulary (R20) | Implementation Approach, final checks |

## Solution Architecture

### Overview

The change adds one stored value and the code that names, checks, carries,
prints and renders it, then rewrites the skill's text so each duty names the
role that owes it. No new script file, record key, koto state, gate or
variable is added, so the template stays at compat 2.

### Components

| Component | Change |
|---|---|
| `scripts/coordinate-open.sh` | parses `--role` outside the variable pairs; refuses `invalid_role` before any koto call; reads the candidate's role through `state-read.sh --run` and refuses `role-mismatch` before any write; prints `ask=role` (exit 10) for a new run or a role-less continuation without one; prints `role=<value>`; writes the row on a resume of a role-less record; runs the mismatch check on an import's copy right after it lands |
| `scripts/coordinate-open.wording.tsv` | `invalid_role`, `role_mismatch` and the `ask=role` message |
| `scripts/state-open.sh` | `--role` required on a fresh seed and written in it; `--carry --role` adds the row only when the copy has none |
| `scripts/holding-link.sh` | doesn't link a pull request onto a holding whose entry is `coordinate` |
| `scripts/state-stored-set.sh` | `--run role <manager\|director>`, set-once; `reports-to` usage reworded |
| `scripts/state-schema.jq` | `role` among the Run keys, two values, one row; `reports-to` comment and message reworded |
| `scripts/state-read.sh` | a `--run` mode that reads `record/run` without a sealed find |
| `scripts/state-handover.sh` | prints `role`; gap `no-role` with its fix; `no-reports-to` fix reworded |
| `scripts/reconcile-report.sh` | `def record_line`, a `line` mode, and `md --record-line <line>` |
| `scripts/reconcile-report-get.sh` | `--md` adds the record line as line 3, exits 4 with no role |
| `scripts/coordinate-report.sh` | `--record-line`; `record=` accepts a session name |
| `scripts/render-brief.sh`, `scripts/dispatch-common.sh` | the `role` input field; `dc_invocation` appends `--role` |
| `scripts/dispatch-worker.sh` | writes `.role` in `read_inputs`: deleted for workers, the record's row for a successor (refused when missing), `manager` for a lane |
| `koto-templates/coordinate.md` | `record_open` directive passes `role=`; `reconcile` directive closes gaps before printing the report; start state names the two roles and the Roles section; swept prose |
| `SKILL.md` | flag table, Glossary entries, `## Roles`, the Bounds and Authority allowance paragraph, the own-reading sentence, the record line in Reporting, `reports-to` wording, swept prose |
| `references/state-keys.md`, `brief-template.md`, `loop.md`, `entry-points.tsv` header | the Run `role` row and its writers; the Goal rule and the `role` field; the record line; where `--role` comes from |
| Tests | `state-stored-set_test.sh`, `state-schema_test.sh`, `coordinate-open` tests, `render-brief_test.sh`, `dispatch-worker_test.sh`, `coordinate-report_test.sh`, reconcile report tests, the template structure test (writers and non-readers of the row), `testdata/rule-coverage.tsv` rows for the new sentences |
| `koto-templates/coordinate.compat.json` | re-records the gate-script digest; fingerprint and compat unchanged |

### Key Interfaces

- **Start flag.** `--role manager|director` in the start's args file. Results:
  `refused=invalid_role` (exit 2), `outcome=refused` with
  `reason=role-mismatch` (exit 2), `ask=role` (exit 10), and `role=<value>` on
  success.
- **Record row.** Run key `role`, value `manager` or `director`, at most one.
  Writers: `state-open.sh` (seed) and `state-stored-set.sh --run role` (set
  once, exit 65 on a different value). Reader: `state-read.sh --run`.
- **Handover read.** `state-handover.sh` prints `role`; gap `no-role`, fix
  `state-stored-set.sh --run role <manager|director> --by <who named it>`.
- **Record line.** `` Record: session `<session>` on `<owner>/<repo>`[, address `<address>`]. Role: <manager|director>. ``,
  printed by `coordinate-report.sh --session S --record-line` (exit 4 with no
  role) and as line 3 of `reconcile-report-get.sh --md`.
- **Brief field.** `role` in the render input: required and only allowed when
  the entry point is `coordinate`; written by `dispatch-worker.sh`. Rendered
  as `` Run `/shirabe:coordinate <roadmap-path> --role <role>` in <owner/repo>. ``
- **Allowance reads (unchanged interfaces).** The Run `cap` row; the start's
  scope and decisions; `niwa authority check -C <instance> --session <id>
  --point <cap-change point> --json`, asked when a cap change would happen.

### Data Flow

1. A person starts `/shirabe:coordinate <roadmap> --role director` (or states
   "role: director" in the decisions, which the agent passes as the flag). The
   opener checks the value, finds no candidate run, prints `role=director`,
   and `record_open` seeds the record with the Run `role` row.
2. `reconcile` closes its handover gaps, then prints the first report with
   `reconcile-report-get.sh --md`; its third line is `` Record: session `…` on
   `owner/repo`. Role: director. ``
3. The director dispatches a manager for another roadmap. `dispatch-worker.sh`
   sets `.role` to `manager`; the brief's invocation line and the dispatch
   prompt carry `--role manager`; the manager's opener checks it and seeds its
   own record with `manager`. The manager's `reports-to` row names the
   director's address, and its reports go to the director as its reviewer.
4. The manager reports ready worker pull requests through its verify report
   and progress table, and merged ones in the report after a land. The
   director reads them for alignment and names any divergence to every
   manager involved and in its own report.
5. The director hands over. `dispatch-worker.sh` sees its own roadmap, reads
   the Run `role` row, and renders `--role director`. The successor's opener
   reads the candidate's role, accepts the matching flag, and the takeover
   carries the row with `record/`. Its first report's record line names
   `director`.
6. A successor of a lineage started before this change is started with
   `--role director`: the opener finds no recorded role, `finish_takeover`
   writes the row, and nothing reads the old names in earlier briefs or
   entries. Started without the flag, it is asked.

## Implementation Approach

One pull request, built in this order so each step's tests run against the
step before. The plan can split it, but the steps share fixtures and the
compat record, so one pull request is the expected shape.

### Phase 1: The record row

Add the Run `role` row: `state-schema.jq`, `state-stored-set.sh --run role`
(set-once), `state-open.sh` seed and `--carry --role`, `state-read.sh --run`,
and `state-handover.sh`'s `role` field and `no-role` gap. Reword `reports-to`
in the scripts and their messages. Update the record's writer structure test
and the gap list tests.

Deliverables: the five scripts, `state-keys.md`'s Run row entry, tests.

### Phase 2: The opener

`coordinate-open.sh` parses `--role`, refuses `invalid_role`, reads the
candidate's role and refuses `role-mismatch`, asks `ask=role`, prints `role=`,
writes the row on a resume and in `finish_takeover` for a role-less record,
and checks an import's copy. Add the wording rows. Tests cover each refusal
leaving the record and the run's state unchanged, for all five continuations
and both directions of mismatch.

Deliverables: `coordinate-open.sh`, `coordinate-open.wording.tsv`, the opener's
tests, `SKILL.md`'s flag table and the "stated in words" sentence.

### Phase 3: The record line

`reconcile-report.sh`'s `record_line` def and `line` mode,
`reconcile-report-get.sh --md`, `coordinate-report.sh --record-line` and its
`record=` fix. Reorder the `reconcile` directive (gaps first), point
`loop.md` and the `reconcile_pass` prose at the printed report, and document
the line in `SKILL.md`'s Reporting.

Deliverables: the three scripts, their tests, the directive text.

### Phase 4: The brief

The `role` field in `render-brief.sh`, `dc_invocation`'s `--role`,
`dispatch-worker.sh`'s fill rule, `brief-template.md`'s field and Goal text,
and the `entry-points.tsv` header comment. The worker golden files must not
change.

Deliverables: the scripts, `render-brief_test.sh`, `dispatch-worker_test.sh`.

### Phase 5: The skill text

The Glossary entries, the `## Roles` section, the Bounds and Authority
allowance paragraph, the own-reading sentence, and the start state's pointer.
Then the sweep: generate the occurrence list at the branch's base, class it,
rewrite the one-role and positional sites, rerun after the last text commit,
and put the table in the pull request description. Add rule-coverage rows for
the new pinned sentences (for example "It isn't a correctness review" and
"which of your lanes advance").

Plan steps the decisions surfaced, each small and inside this change:

- widen the cap write's trigger ("a person's word" in the cap paragraph of
  `koto-templates/coordinate.md` and in `references/state-keys.md`) to accept
  direction from whoever dispatched
  the run, so a manager can write a cap change its director made; the manager
  takes that direction only from the sender its Run `reports-to` row names,
  and the cap it writes stays inside what its own `niwa authority check`
  answer allows;
- stop a progress event from linking a pull request onto a holding whose entry
  is `coordinate` (the link is written by `scripts/holding-link.sh` at
  `report_link`), so a director's count of its managers doesn't drift;
- read one-role duties that SKILL.md addresses to "you" without the word
  "coordinator" (for example "Your land step...") against the two lists and
  readdress any that only one role owes, since the classification table only
  covers occurrences of the word.

### Phase 6: Checks

Re-record `coordinate.compat.json`'s gate-script digest, and have the check
derive it again from the scripts rather than trust the recorded value. Run
`scripts/check-skill.sh coordinate`, `scripts/check-template-compat.sh
--template skills/coordinate/koto-templates/coordinate.md` and
`scripts/ablation/check-public-content.sh`. Confirm the keep-alive sentence is
found in the same files as before, run the positional-name grep both per line
and over whitespace-squeezed text, run the banned-word check from
`skills/writing-style/rules.yaml` over added lines, commit messages and the
pull request text, and confirm the posture read and `niwa authority check`
print the same answer for a run recorded either way. The structure test only
covers scripts; the agent also reads the role and the Roles text, so a text
check confirms the Roles section keeps its sentence that a list says what a
role owes, never what it's allowed to do, and that no expectation item names a
grant, merge authority, a settler or a cap.

## Security Considerations

This change adds a value that describes a session and the code that carries
it. It downloads nothing, runs no new external program, and changes no
permission, so the questions that matter are whether the role can be used to
gain or lose an allowance, whether it can be forged into a brief or a record,
and what the new report line exposes.

**The role can't widen or narrow what a session may do.** The allowance
boundary is held by construction, not by wording alone. The role isn't a koto
variable, so no gate or template condition can branch on it. It is never passed
to `niwa dispatch`, whose `--role` flag grants the authorities a workspace
declares for a named role; a coordinator named `director` in a workspace that
happens to declare an `[authority.roles]` entry called `director` still gets
nothing from it. The posture read, the reserved-step check, the merge re-read
and the grant path don't read the Run `role` row, and a structure test pins
that with an allow-list of the row's readers, so a script added later that
reads the role fails the test instead of slipping past a list of known
offenders. A director with no merge grant still may not merge, and a manager holding
one still merges only after its reviewer's review.

**A role can't be injected through prose.** The opener never parses the
decisions text; the agent passes a role stated in words as the flag, and the
opener checks it against two literal values. In a brief, `dispatch-worker.sh`
overwrites the `role` field from the record or the lane rule, so a dispatcher's
Goal text ("you are the director") or an input that sets the field can't make a
lane start as a director. The renderer refuses `--role` in `entry_args`, so the
flag can't be smuggled past the field. Two strings still come from the caller
and are echoed or stored, so both are treated as data: the `invalid_role`
message prints the refused value in backticks, cut to 32 characters and with
control characters and backticks removed, so a crafted value can't break out of
the message an agent reads, and the `role_mismatch` message cleans the run
name it echoes the same way; and the `--by` value on the role row is one line
of at most 80 characters, stored as provenance and never read back as an
instruction.

**A forged or mistaken role is visible and bounded.** A session started by hand
with the wrong role gets only a different expectation list, never an
allowance. Its first report's record line names the stored role, and its
reviewer reads that line. Naming itself director doesn't make a session
anyone's reviewer either: a manager's reviewer is whoever its own Run
`reports-to` row names, which its dispatcher's brief set, and no script
resolves a reviewer from a `role` row. Once stored, the role can't be changed by a later
start: the set-once writer and the opener's mismatch check refuse it, and the
refusal writes nothing, so an attempted change can't leave a half-written
record. The flip side is that the first role written to a role-less record,
whether from the opener's flag or from the person's answer at reconcile, is not
authenticated and is permanent for that lineage. That is accepted because it
changes only which expectation list the session follows: a wrong first role is
corrected by starting a new lineage, and nothing it grants has to be revoked.

**The record line exposes nothing new.** It names the session and the host
repository, which every report already names, and, when the Run `coordinator`
row differs from the session name, the messaging address. That address is the
same kind of identifier as the session name: it is what briefs already tell
workers to report to, and the PRD's own test for the line strips it alongside
the session and host. The role word adds no identifier. Reports are messages
between sessions and to the person, not text committed to a repository; a run
that posts a report somewhere public already has to strip session names under
that repository's content rules, and the address falls under the same rule.
Reports from a public repository's coordinator still carry no private path or
figure, and nothing in the change names one.

**The cap-change read fails closed.** A director makes a cap change itself only
when `niwa authority check` answers bound with that point's decider `session`.
A failed lookup, an unbound session, any other decider, or a point the
authority configuration hasn't named yet sends the change up as a decision
entry, so a missing or broken read never widens what the director does on its
own. Until the authority configuration names the cap-change point, that means
every cap change goes up as a decision; that's a known limit, not a gap. The
read itself is prose with no gate, so a director that skips it isn't stopped
by a script: it is caught by the `--by` its manager writes on the cap row and
by its own reviewer, as Consequences says.

**The manager's cap write takes direction from one sender.** The plan step
that widens the manager's cap write past "a person's word" is the one place
this change touches an allowance on the manager's side. The manager accepts a
cap change only from the sender its Run `reports-to` row names, the session
that dispatched it, and writes it with that sender in `--by`. A cap change
from anyone else is not written, and a written cap still can't exceed what the
manager's own `niwa authority check` answer allows, so a director can lower or
move a manager's cap but can't use the manager to widen it past the workspace
grant.

## Consequences

### Positive

- The role has one source and one store: a flag at start, a Run row after it,
  and every reader (handover read, record line, successor brief) reads the
  row. A role can't drift between briefs because no brief writes it from
  prose.
- No compat raise: runs opened before the change resume, carry, take over and
  import onto it, which is exactly the lineage case the PRD tests.
- The allowance boundary is mechanical, not only written: the role isn't a
  koto variable, isn't passed to `niwa dispatch`, and a structure test pins
  that the posture and grant paths don't read it.
- The director's reading starts from what managers send, because the manager
  now reports its lane's merged pull requests, and the director doesn't poll
  GitHub to find them.
- The record line is printed by a script from the live record, so the first
  report and every later one say the same thing.

### Negative

- A new run's role travels from the opener's `role=` line to `state-open.sh
  --role` through the agent across a few states. A missing value is refused,
  but a wrong copy is caught only by the record line in the first report.
- A refused import leaves its copy on this host, because koto can't check a
  copy before it lands. The record inside is unchanged, but the copy exists.
- A role-less carry's role is written at the handover gate, not by the opener,
  so it depends on the reconcile directive's gap fix.
- The record line moves the reconcile report's `Scope:` line from line 3 to
  line 5, which a reader or tool that looks for it there will notice.
- The cap-change read is prose with no gate, so a director that skips it is
  caught only by the `--by` on the manager's cap row and by its reviewer.
- No brief can start a discipline coordinator today, so a director can't
  dispatch a discipline manager through a brief.

### Mitigations

- The agent copy of `role=`: the seed refuses a missing `--role`, the first
  report's record line shows the stored value, and its reviewer reads it. A
  proposed follow-up lets the opener seed a fresh roadmap record itself, which
  removes the copy, but it changes when a record is born, which the record's
  own effort owns.
- The import copy: the refusal says the copy stays and how to carry it (start
  again naming the recorded role, or none). Checking a copy in place needs a
  koto feature, proposed as a follow-up.
- The gap-fix dependency: the handover gate holds until the row exists, and
  `reconcile-report-get.sh --md` prints nothing without it, so no report goes
  up roleless.
- The `Scope:` line: `loop.md` already treats the opening lines as kept as
  written, and its text is updated to list the record line first.
- The cap-change read: escalation is the default on any answer but a bound
  `session` decider, so skipping the read can't widen what a director does on
  its own; a proposed follow-up seals the answer once the authority effort
  names the point.
- Discipline lanes: out of this change's scope; a director dispatches roadmap
  managers, and adding a discipline route to briefs is a proposed follow-up.
