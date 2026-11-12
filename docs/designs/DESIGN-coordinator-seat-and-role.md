---
schema: design/v1
status: Proposed
problem: |
  A coordinator's kind is recorded in one shape by the shipped named-roles
  work (a manager|director Run row in the coordinate record) and proposed in
  another by planned fleet-status work (a seat in koto with four roles for
  every session shirabe opens), and neither cites the other. The planned
  stable coordinator address reads like a third name for the same position.
  The fleet-status work builds nothing until one definition of seat and role
  exists, because a second definition beside the shipped role would undo the
  point of having one.
decision: |
  A seat is the position a dispatcher or a person creates, filled in turn by
  sessions called its holders; a successor is a new holder of the same seat.
  A seat's name is the one koto already holds: coordinate-<SLUG> for a
  coordinator, <parent seat>/<dispatch topic> for a worker, and the
  session's own <skill>-<topic> for a session nobody dispatched. There are
  three roles: director and manager, the shipped values, which live only in
  the coordinate record's Run role row, and worker, which every other seated
  session has by rule and nobody stores. A coordinator seat's role is the Run
  row itself, read through one new reader script; research is a kind of
  unit, read from the entry-point skill, not a role. The coordinator seat's
  name is the stable address, resolved to the newest holder by the walk
  resolve-coordinator.sh already does.
rationale: |
  Every fact the definition needs is already written once: the role in the
  Run row, the scope in record/meta, the lineage in supersede events, the
  parent in the dispatched-by link, the worker's topic in the parent's
  Holdings and the entry point in the session's name and template. Reading
  them through one script keeps one store per fact, writes nothing new, adds
  no koto call, and leaves the shipped flag, row, carry, brief line and
  refusal as they are. Storing a seat key at open, moving the role into a new
  key or into koto, keeping four roles, or taking an alias at takeover each
  either adds a second store, adds a write to every open, or changes shipped
  behaviour for a reader's convenience.
---

# DESIGN: Coordinator Seat and Role

## Status

Proposed

## Context and Problem Statement

Two pieces of planned work each record what kind of session a coordinator is,
in two shapes, and neither cites the other.

The named-roles work has shipped. `/coordinate` takes `--role
manager|director` at start; `coordinate-open.sh` checks it before any koto
call, the record keeps it as one set-once Run row, `role`, every continuation
(resume, carry, takeover, import, rotation) carries it, a successor's brief
names it on its invocation line, and a start whose role differs from the
recorded one is refused unless it names a change from above
([DESIGN-coordinator-named-roles.md](DESIGN-coordinator-named-roles.md)). A
structure test pins the writers of that row and an allow-list of its readers,
and no allowance read looks at it.

The other piece is planned and held. A status view of the fleet wants every
session shirabe opens to show, to anyone reading koto, which seat it holds,
that seat's role, its parent seat and its unit of work. In that plan a seat is
a position, a holder is the session filling it, and a role is the seat's
kind, one of director, manager, worker or researcher. A successor is a new
session holding the same seat, never a session that moves. That plan builds
nothing until one definition of seat and role is agreed, because a second
definition beside the shipped role would undo the point of having one.

The two meet in three places. The shipped role covers coordinators only and
has two values; the planned seat role has four and covers every dispatched
session. The shipped role lives in the coordinate record; the planned one
lives in "a koto seat" whose fields aren't named. And the named-roles work
also plans a stable address for a coordinator, one name that reaches whoever
currently holds the position, which reads like the same idea as a seat.

Several facts this design builds on already exist in koto and shirabe:

- koto records `koto/links/dispatched-by/<name>` in a session that another
  session dispatched, and `koto/links/continues/<pred>` in a session that
  continues another. A takeover (`koto init --continues --supersede`) writes
  `session_superseded` events that `resolve-coordinator.sh` follows forward
  to the newest member of a coordinator's run, whose Run `coordinator` row is
  the Claude session name a worker messages
  ([DESIGN-coordinate-successor-continues.md](DESIGN-coordinate-successor-continues.md)).
  That script also refuses when the newest member's `record/meta` scope
  differs from the dispatcher's.
- Coordinator runs are named `coordinate-<SLUG>-<timestamp>`, where SLUG is
  the lowercased scope and name (`roadmap-<roadmap>`, `discipline-<surface>`).
  `coordinate-open.sh` already treats one SLUG's runs as one lineage: it
  refuses a `--continues` that isn't the SLUG's newest member.
- Every other shirabe skill opens `<skill>-<topic>` through
  `scripts/skill-session.sh open`, from a template shirabe ships. A child a
  parent skill opens inline (`design-<topic>` under `scope-<topic>`) carries
  a `chain/parent` key. A coordinator's Holdings row records each worker by
  its dispatch topic, repository and branch.
- A carry today links the new run with `dispatched-by` and leaves no
  `continues` link or fence (tsukumogami/shirabe#1740).
- koto already uses the word "seat" for a review panel's reviewer
  (`koto review record`'s `seat` field), and shirabe's review rounds record a
  Seat per reviewer.
- `niwa dispatch --role` grants authorities. The coordinate role never reaches
  it.

The question for this design: one definition of seat and of role that both
pieces of work can cite, covering where the role lives, which roles exist,
and how the role in the coordinate record and a seat's role relate.

This is a new design rather than an amendment of the named-roles design.
That design is shipped and its decisions concern the coordinate record alone;
the seat covers every session shirabe opens and a read model over koto, so
folding it in would reopen a finished design to add a scope it never had.
This one cites it and changes nothing in it.

## Decision Drivers

- **One record of each fact.** A coordinator's role is written in one place.
  A second store that has to agree with the first is the failure this design
  exists to prevent.
- **Keep what shipped working.** The `--role` flag, the set-once Run row, the
  carry on every continuation, the brief's invocation line, the refusal on a
  mismatch and the change-from-above path keep working, or each change to
  them is named as its own follow-on issue.
- **The agent pays nothing.** No new step for the agent, no new text it reads,
  and no change in how many koto calls a run makes, counting the calls its
  scripts make.
- **Readable from koto.** A reader that holds a session name can find its
  seat, role, parent seat, current holder and unit from what koto holds,
  without the agent's help.
- **Roles stay out of allowances.** A role says what a session owes, never
  what it may do. No allowance read, and nothing passed to `niwa dispatch
  --role`, takes the role.
- **No word collision.** The seat this design defines and a review panel's
  seat must not share a key, field or reader.
- **Fits the planned stable address.** A seat's name should be the thing a
  stable address resolves, so the two plans don't grow two names for one
  position.
- **Small and docs-first.** This design defines; building is later work in
  shirabe, and any koto or niwa change is a follow-on issue in that
  repository's terms.

## Considered Options

The brief's three parts map onto three decisions. Decision 2 answers both
where the role lives and how the record's role and the seat's role relate,
because the answer to one fixes the other; it weighs options for each part
separately.

### Decision 1: What a seat is and how it is named

The fleet view wants a seat, a parent seat and a holder for every session
shirabe opens. The named-roles work wants a stable address for a coordinator.
If the two get separate names, one position has two. The seat has to be
defined so that it hands the address its name, without a new store and
without the agent doing anything new.

Most of what's needed is already in koto. A coordinator's SLUG names one
lineage, `record/meta` carries its scope through every continuation, and the
resolver's scope comparison already asks whether a walk stayed in one
position. The links are less tidy: `dispatched-by` means a parent for a
worker or a lane, but a predecessor for a carry, so from the links alone a
carried run looks like a child of the run it replaced (shirabe#1740).

Key assumptions:

- The stable address names a coordinator position and resolves to the current
  holder's messaging address, its Run `coordinator` row. If it has to pass
  `niwa authority check`, which binds to a dispatch id, that binding stays on
  the holder's dispatch id: the seat name identifies a position and grants
  nothing.
- A reader can match a worker session to its parent's Holdings row through
  its `dispatched-by` link and its `session/branch` key. If that proves
  unreliable, a label riding the existing link call is the fallback (a koto
  follow-on that keeps the call count).
- A takeover successor's `dispatched-by` naming its predecessor is told apart
  from parentage by its `continues` link, and a carry by its shared SLUG,
  until shirabe#1740 gives a carry a `continues` link too.

#### Chosen: A seat is the position its dispatcher named, and its name is the one already written

A seat is a position that a dispatcher, or a person, creates. Sessions fill it
one after another as its holders. A successor is a new session holding the
same seat; a session never moves between seats. A seat's name is the name its
creator already gave the position, read from where koto holds it:

- **Coordinator seat:** `coordinate-<SLUG>`, any holder's session name with
  the timestamp dropped, confirmed against the `record/meta` scope every
  member carries. Every resume, carry, takeover, import and discipline
  rotation of that scope holds this one seat. A lane manager a director
  dispatched is a coordinator seat named by its own scope, whose parent is
  the director's seat.
- **Worker seat:** `<parent seat>/<dispatch topic>`, where the dispatch topic
  is the Worker value in the parent's Holdings row. A worker usually has one
  holder; a re-dispatch of the same holding is a new holder of the same seat.
- **Root seat:** a shirabe session nobody dispatched holds a seat named by its
  own `<skill>-<topic>` session name, which is already stable because
  reopening the same topic attaches to or replaces the same session. A root
  seat has no parent.

The parent seat is the seat of the session the first holder's
`dispatched-by` link names, unless that link names a predecessor (a run
sharing the SLUG, or one its `continues` link names), which makes it a
continuation. The current holder is the newest member, found by today's
forward walk, with today's scope check serving as the seat's fence.

The coordinator seat's name is the stable address. `coordinate-<SLUG>`
resolves to the newest holder's Run `coordinator` row, which is what
`resolve-coordinator.sh` already computes from any member. No holder takes an
alias at takeover.

This works because the name already exists for every kind of seat, so
nothing is written and the resolver needs no rework. A carried run keeps its
SLUG and its `record/meta`, so it stays in its seat even across the carry gap;
only the order of holders on that path waits on shirabe#1740. Discipline
rotations come out as successive holders of one seat with no extra rule. The
cost is that a worker seat's name sits on the parent's side, so a reader
starting from a worker session takes one extra read.

#### Alternatives Considered

**The lineage root's session name.** The seat is named after its first
holder's session, the current holder is found by walking forward, and the
parent comes from the first holder's `dispatched-by`. Rejected: it breaks on
the carry gap, where a carried run has no `continues` link and its
`dispatched-by` names its predecessor, so it would read as a new seat
parented by the old run. A fresh start of a finished scope, or an import,
would also give one position a second name.

**An explicit seat label written into each holder.** Rejected: it adds a
write on every open and continuation, which changes the koto call count
unless it rides an existing call, and it is a second record of facts the
scope in `record/meta` and the Holdings row already hold.

**An alias taken at takeover.** Rejected: it needs a mutable name store
outside the record that must agree with the links, a write on every
continuation path, and a registry neither koto nor niwa has. It covers
coordinator seats only, never workers or roots.

**No seat entity, only a view over sessions.** Rejected: the stable address
would then have nothing to resolve and would invent its own name, the
two-names outcome the drivers rule out, and every reader would re-derive the
rules and meet the carry gap on its own.

### Decision 2: Where the role lives, and how the record's role and the seat's role relate

The shipped role is one set-once Run row in the coordinate record, written by
`state-stored-set.sh` and `state-open.sh` and read by an allow-list of
scripts that a structure test pins. The fleet view wants every seat's role
readable from koto at no cost to the agent. Two facts settle most of the
question: `koto context add` stores one key per call, so any role key written
at open adds a koto call to every session; and a session's name already says
which skill opened it, with `/coordinate` the only skill whose sessions come
in more than one kind.

Key assumptions:

- A fleet reader may name a session's role through one shirabe reader script.
  If a reader outside shirabe must read a plain stored value instead, a key
  becomes necessary and the call count has to give.
- A top session a person runs outside `/coordinate` isn't a shirabe-opened
  session.

#### Chosen: The Run row stays the one store, every other role is derived, and one reader reads both

**Where the role lives.** A coordinator seat's role lives only in the
coordinate record's Run `role` row, unchanged. No other session's role is
written anywhere: it follows from the skill that opened the session, which
koto already holds in the session's name and template. One shirabe reader
script takes a session name and prints its role from what koto holds: for a
coordinate run, its Run `role` row read live, or `no-role` when the record is
in the handover gap (the answer the report's record line already gives); for
any other seated session, `worker` (Decision 3); for a session that holds no
seat, nothing.

**How the two relate.** For a coordinator, the seat's role and the record's
role are one value read from one store: identity, not a copy. For every other
session the seat's role is a rule over the opener's skill, defined once in
the reader. There is no copy, so there is no check to keep a copy in step.

The top seat with no coordinate record needs no writer. A top session run as
`/coordinate --role director` keeps its role in its own record like any
coordinator. A person's session outside `/coordinate` holds no seat; the
reader shows it only as the address a parentless coordinator's `reports-to`
row names.

The reader joins the structure test's reader allow-list in the change that
adds it, which that test already provides for, and lives under
`skills/coordinate/scripts/` so the existing scan sees it. Nothing on a
grant or posture path calls it.

This keeps one store per fact and leaves every shipped behaviour untouched:
the flag, the set-once row, every carry path, the brief line, the mismatch
refusal and the change-from-above path. No session writes anything new, so
the koto call count stays where it is, and a role that is never written
outside the record has no new path toward an allowance or `niwa dispatch
--role`.

#### Alternatives Considered

For where the role lives:

**A uniform `seat/role` key written by every opener, with the Run row kept.**
Plain to read, but it costs one koto call on every open and is a second store
beside the Run row for every coordinator. It rides no carry path, so every
continuation and every change from above would need a second write and a
check to keep the two in step, the drift this design exists to prevent.
Rejected.

**A uniform key that replaces the Run row.** One store again, but it moves
every shipped writer and carry path, the brief and record lines, the refusal
and the structure test, needs a migration for runs opened before it, and
still adds a koto call per open. Rejected as a large reversal of shipped work
for a reader's convenience.

**A koto-native session field.** A koto change that puts shirabe's role names
into koto and duplicates the Run row unless the row moves into it. Rejected
for now; worth reopening only if koto grows a general indexed label that many
tools want.

For how the two relate:

**A copy kept in step by a check.** Two stores and a reconciliation path for
one fact. Rejected with the uniform key.

**A mapping from the Run row to a seat role.** The seat's manager and
director mean what the shipped values mean, so a mapping would translate
nothing and add a place for the two to drift. Rejected in favour of identity.

### Decision 3: Which roles exist

The shipped role has two values and covers only `/coordinate` runs. The
fleet view's plan proposes four seat roles, director, manager, worker and
researcher, for every session shirabe opens. Nothing separates research from
build work mechanically: `/comp` and `/design` open pull requests, and
`/explore` or `/decision` may commit a report. "Researcher" is also already
shirabe's word for a local subagent, such as `/design`'s security researcher,
which the coordinate Glossary says is not a worker.

Key assumptions:

- A fleet view can show the entry-point skill from the session's name. If
  not, a separate unit-kind field is needed, and it is still not a role.
- A session a person-run session dispatched carries a `dispatched-by` link
  when its opener is given one; without one it reads as a root seat, which is
  the safe default.

#### Chosen: Three roles (director, manager, worker); the unit's kind is the entry point

There are three roles, and research is a kind of unit, not a role.

- **Director** and **manager** are the shipped values, unchanged, read from
  the coordinate record's Run row (Decision 2).
- **Worker** is every seated session that isn't a coordinate run, dispatched
  or not. Its value is a rule, not a stored fact. A reader checks for a
  coordinate run first, so a carried run that the carry gap linked to its
  predecessor with `dispatched-by` still takes its role from its record.
- **The unit's kind** (explore, comp, decision, design, work-on and the rest)
  is the entry-point skill, read from the session's name. A fleet view shows
  "worker, /explore" beside "worker, /work-on" and can filter on it.

Who holds no role: a session that holds no seat (Solution Architecture,
Seated sessions). In particular, a person-run top session, the merge
authority included, is not a director unless it runs `/coordinate --role
director`, which gives it the record the role lives in; calling it a director
otherwise would give the word a second meaning with none of the director's
duties on record.

Every value is either written once already or follows from facts koto holds,
so the set meets one-store-per-fact and agent-pays-nothing with no new field.
The shipped values, row, carry, brief line and refusal are untouched, and the
Glossary's Worker and Local agent entries already describe the split. The
trade-off: a view that wants a count of research units groups by entry point
and decides for itself which entry points it calls research.

#### Alternatives Considered

**Four roles, researcher included.** Rejected: a researcher can't be told
apart from a worker without the agent declaring it or a table naming which
skills are research, and either is a second record of what the entry point
already says. It also reuses the word the skills use for a subagent.

**Two levels, coordinator and worker, with manager or director beneath.**
Rejected: it splits one fact into two fields and adds a `coordinator` value
the shipped Run row doesn't hold.

**The role is the entry-point skill's name.** Rejected: it folds manager and
director into one `coordinate` value, losing the shipped distinction, and
repeats what the session name already says.

## Decision Outcome

A seat is a position, a holder is a session filling it, and a role is the
seat's kind. Every seat's name, parent, holder, role and unit is read from
facts koto already holds, through one shirabe reader, and nothing new is
written:

| Seat | Name | Role | Parent | Current holder | Unit |
|------|------|------|--------|----------------|------|
| Coordinator | `coordinate-<SLUG>` | Run `role` row (`manager`, `director`, or `no-role` in the handover gap) | seat of the first holder's dispatcher, unless that is a predecessor | newest member, by the supersede walk and scope fence | the scope in `record/meta` |
| Worker | `<parent seat>/<dispatch topic>` | `worker` | the seat whose Holdings row names it | the newest session matched to that row | the Holdings row: topic, repository, branch, pull request |
| Root | `<skill>-<topic>` | `worker` | none | the session itself | its topic |

The three decisions fit together without a seam. Decision 1 names every seat
from what's written; Decision 2 puts the role in the one place that already
holds it and reads the rest by rule; Decision 3 keeps the role set to the
values that are written or follow by rule, so no role ever needs a store of
its own. The stable address and the seat are one idea: the coordinator seat's
name is the address, and its current holder's Run `coordinator` row is where
a message goes.

Cross-validation found three places where the decisions' first drafts
differed, all resolved toward the reading that writes nothing: a session
nobody dispatched is still a worker (the `dispatched-by` link decides only
its parent); a nested child is recognized by its `chain/parent` key; and the
reader keeps a rule (coordinate run or not), not a per-skill role table.

### What each plan cites

The named-roles plan, whose role milestone shipped, cites this design's
**Role** definition: the role it shipped is the coordinator seat's role,
stored only in the Run row, with the values `manager` and `director`
unchanged. Its planned stable address cites **Seat names**: the address is
`coordinate-<SLUG>`, resolved to the newest holder by the existing walk,
with no alias, and an authority binding, if one is needed, stays on the
holder's dispatch id.

The fleet-status plan, whose seat milestone is held on this definition,
cites **Seat**, **Holder** and **Role** as defined here, the **Seated
sessions** list, and the reader's output in Key Interfaces as the one way it
reads a seat. Two parts of what that plan proposed change under this
definition, and its own edit would say so: there are three roles, with
research read as the unit's kind; and "koto holds the seat" means koto holds
every fact a seat is made of, read through shirabe's reader, not a new seat
record written into each session.

## Solution Architecture

### Overview

The seat is a read model. Nothing in it is stored as "the seat": a reader
script assembles it from the session's name and template, the coordinate
record's Run and meta rows, koto's supersede events and links, and the
parent's Holdings. The coordinate opener, the record and every continuation
work exactly as they do today.

### Definitions

- **Seat** -- a position in the work a dispatcher or a person created, filled
  in turn by its holders. It has a name, a role, at most one parent seat and a
  unit. It is never stored as one record.
- **Holder** -- one koto session filling a seat. The current holder is the
  newest member; earlier holders are its predecessors.
- **Successor** -- a new holder of the same seat. A session never moves
  between seats.
- **Role** -- the seat's kind: `director`, `manager` or `worker`. It says what
  the holder owes, never what it may do.
- **Unit** -- what the seat works on: a coordinator's scope, a worker's
  holding, a root session's topic. Its kind is the entry-point skill.

### Seated sessions

A session holds a seat when shirabe opened it from one of its shipped
templates (the skill-session template, the coordinate template, and the
execute and deliver templates) and it is not a nested child. That covers
every coordinate run, every session opened from a coordinator's brief, and
every shirabe session a person starts directly.

These hold no seat:

- a nested child a parent skill opens inline, recognized by its `chain/parent`
  key; it is work inside its parent's seat and shows as that seat;
- a local agent or a sub-operation, such as a `/decision` decider writing into
  its parent's session, which opens no session of its own;
- a koto session opened from any other template;
- a person.

### Components

- **`skills/coordinate/scripts/seat-read.sh`** (new, later work) -- the one
  reader. It takes a koto session name and prints the seat that session
  holds. It reads only: koto session and log reads, and `koto context get` of
  `record/meta`, `record/run`, `record/holdings`, `chain/parent` and
  `session/branch`. It writes nothing to any session.
- **`resolve-coordinator.sh`** (unchanged) -- the supersede walk and scope
  fence the reader reuses for a coordinator seat's current holder.
- **The coordinate record** (unchanged) -- the Run `role` and `coordinator`
  rows, `record/meta` and the Holdings section.
- **The role structure test** (one entry added) -- `seat-read.sh` joins the
  reader allow-list for the Run `role` row.

### Key Interfaces

```
seat-read.sh <koto-session>
```

Prints, on success, one field per line:

```
seat_name=<name>
seat_role=director|manager|worker|no-role
seat_parent=<name>|none
seat_holder=<koto session of the current holder>
seat_unit=<scope, holding topic, or topic>
seat_kind=<entry-point skill>
```

or, for a session that holds no seat, the single line `seat_name=none` and
nothing else. Every field carries the `seat_` prefix so that no reader or
record confuses it with a review panel's `seat` field. Exit 0 when printed;
1 when a session, log or key it needs can't be read; 64 for usage.

The definitions above are the citable contract; the script's field names are
the contract a fleet reader builds against.

### Data Flow

For a coordinate run, the reader drops the timestamp from the session name
to get the seat name, confirms the scope in `record/meta`, walks forward to
the newest member as `resolve-coordinator.sh` does, and reads that member's
Run `role` row. It finds the parent from the first holder's `dispatched-by`
link, treating a link to a run with the same SLUG, or one its `continues`
link names, as a predecessor rather than a parent.

For any other session, it checks the template and `chain/parent` to decide
whether the session holds a seat, follows the `dispatched-by` link to the
parent, matches the session's `session/branch` against the parent's Holdings
rows to find its dispatch topic, and prints the worker seat. With no
`dispatched-by` link it prints a root seat named after the session.

Direct reports need no scan of the store: a coordinator seat's children are
its Holdings rows. A holder history is the walk from any member.

## Implementation Approach

This design changes nothing on its own. The later work is in shirabe, in
this order.

### Phase 1: The reader

Add `seat-read.sh` and its tests against fixture sessions: a coordinate run
of each role, one in the handover gap, a takeover, a carry, a worker matched
to its holding, a root session, a nested child and a session from a foreign
template.

Deliverables:
- `skills/coordinate/scripts/seat-read.sh`
- its test file beside the coordinate script tests

### Phase 2: The guards

Add `seat-read.sh` to the role structure test's reader allow-list, and add a
check that no grant, posture or dispatch path calls it.

Deliverables:
- the role structure test's allow-list entry
- the role-blind check

### Phase 3: The words

Add Seat and Holder entries to the coordinate skill's Glossary, and widen the
Worker entry to cover a seated session a person started directly.

Deliverables:
- `skills/coordinate/SKILL.md` Glossary entries

### Follow-on issues

Each is proposed for filing in its repository's own terms; this design files
none.

- **shirabe: add `seat-read.sh`, the read model for a session's seat**
  (Phases 1 and 2). Prints a session's seat name, role, parent, current holder,
  unit and entry point from what koto already holds; joins the role reader
  allow-list; no grant path calls it.
- **shirabe: define Seat and Holder in the coordinate Glossary** (Phase 3),
  and widen Worker to cover a seated session nobody dispatched.
- **shirabe: a carry writes a `continues` link** -- already filed as
  tsukumogami/shirabe#1740. Seat identity holds without it; an ordered holder
  history on the carry path needs it.
- **koto (only if matching a worker to its holding proves unreliable): let
  `koto session link --dispatched-by` record a label beside the link**, so a
  worker's dispatch topic is readable from its own session in the same call
  that writes the link. Not needed for the definition.

No niwa or tools change is needed. If the stable address ever has to pass
`niwa authority check`, that binding stays on the holder's dispatch id, which
is the stable-address work's question, not this definition's.

## Security Considerations

The design adds no store, no write, no credential and no network path. The
reader it names, `seat-read.sh`, only reads koto sessions the caller can
already read. Its trust boundary is the local user's koto store: a seat is a
label derived from that store, not an authenticated identity.

**Role and seat name are never authority.** A role says what a holder owes.
Nothing passes it to `niwa dispatch --role`, whose role grants authorities,
and no allowance read takes it. The reader joins the role structure test's
allow-list, and a check keeps shirabe's grant, posture and dispatch paths
from calling it. That check covers shirabe only, so any other consumer,
including a fleet-status view and a later stable-address binding, treats
`seat_name` and `seat_role` as advisory labels. Where an action needs
authority, the check stays on the holder's dispatch id through `niwa
authority check`.

**Spoofing.** A coordinator seat's holder is decided by koto's supersede
events and the scope fence, not by a name a session claims, so a session
can't become a seat's holder by being named like it. That is no protection
against a local actor who can run `koto init --supersede` or write
`record/meta`: such an actor can become the newest holder, and a message sent
to the stable address would reach it. That is already true of
`resolve-coordinator.sh`; this design neither adds nor removes it. A
worker's `session/branch` and `dispatched-by` link are written by the worker
itself, so the worker-to-holding match is a display aid that may be wrong or
forged. The reader shows a worker seat only when the parent's Holdings row
and the worker's link agree, and a session from a template shirabe doesn't
ship holds no seat.

**Untrusted strings.** Topics, branches, scopes and session names can be
written by other sessions. The reader checks each value it prints against a
fixed character set and length cap, rejects a newline anywhere and a `/` in
a topic, quotes every expansion, passes `--` before names it hands to koto,
and exits 1 rather than print a value that fails. Its consumers, person or
agent, read the output as data.

**Exposure.** The output holds session names, scopes, topics, repositories
and branches: no record bodies and no credentials. In a workspace with
private repositories these can name private work, so the output stays local
and isn't pasted into public pull requests, issues or CI logs. Test fixtures
use synthetic names.

## Consequences

### Positive

- One definition both plans can cite, with no second store: each fact a seat
  is made of is written once, where it is written today.
- What shipped keeps working unchanged. The named-roles flag, row, carry,
  brief line, refusal and change-from-above path need no edit.
- The agent pays nothing: no new key, no new koto call, no new text.
- The stable address gets its name and its resolver from work that already
  exists, and doesn't have to choose between the newest member and an alias.
- The fleet view can tell a continuation from a child, a nested child from a
  worker, and a seat from a review panel's seat, by facts koto holds.

### Negative

- A reader outside shirabe can't read a seat from a plain key: it calls the
  reader script or re-implements its rules.
- Naming a worker seat from the worker's own session takes a read of the
  parent's Holdings and a branch match.
- An ordered holder history across a carry depends on shirabe#1740.
- A fleet view that wants research counted separately must decide which entry
  points it calls research.
- The fleet-status plan's proposed four roles and per-session seat record
  change to three roles and a read model; that plan's edit has to say so.

### Mitigations

- The reader is one script with fixed field names, so a reader outside shirabe
  has one contract to follow rather than the rules themselves.
- If the branch match proves unreliable, the koto follow-on lets the existing
  link call carry the topic without adding a call.
- shirabe#1740 is filed; seat identity and role don't wait on it.
- The entry point is printed as its own field, so research can be grouped
  without a role for it.
