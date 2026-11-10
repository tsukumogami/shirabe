---
schema: design/v1
status: Proposed
problem: |
  The coordinate skill's progress table puts every blocked row under
  `Blocked on you`. That's right for a root coordinator, which a person
  dispatched, but a bound coordinator reports to the coordinator that
  dispatched it, so a person reading its table sees rows that wait on the
  chain above it, such as a reserved merge or release its dispatcher holds, as
  theirs to act on. The need kinds also can't say a holding waits on another
  lane, a fix in flight or a release, so such a wait shows no blocked row at
  all.
decision: |
  One shared rule, `kinds.jq`, included by both `progress-view.sh` and
  `reconcile-report.sh`, decides a blocked row's kind from one position fact
  that the pick and reconcile facts carry. On a bound run, a reserved merge,
  close or release, an unconfirmed merge and a decision escalated to the
  dispatcher move to a new `Blocked up the chain` kind that names the
  dispatcher; credentials, access, teardown, CI that never started and
  decisions that must reach a person stay `Blocked on you`. A closed `--chain`
  flag names the lane, fix or release a holding waits on, a worker can't
  appear under both kinds, and a root run's table doesn't change.
rationale: |
  Deciding the kind from a fact the scripts already read, rather than from a
  free-text claim, keeps the coordinator from moving a dispatcher-owed step
  back to the person, and keeping every input in one module gives the Planned
  coordinator-authority design a single place to swap the position fact for
  its settle outcome without touching the renderers. Stored needs and sealed
  report kinds keep their shape, so in-flight runs and old reports still read
  as they did. Deriving the kind and deferring the `--chain` flag was weighed
  and rejected because it leaves lane, fix and release waits in Ongoing,
  where they read as active work.
---

# DESIGN: Coordinate Blocked Kinds

## Status

Proposed

## Context and Problem Statement

The coordinate skill's progress table (`skills/coordinate/scripts/progress-view.sh`)
sorts every row into one of four kinds: `Ready to merge`, `Blocked on you`,
`Ongoing` and `Waiting to be assigned`. Only one of them says a row is
blocked, and its name says the reader is the one blocking it.

That's true for a root coordinator, which a person dispatched. A bound
coordinator, which another coordinator dispatched, reports up to that
coordinator, and the skill's Glossary says everything addressed to "the human"
goes there instead. The table never learned that. Three paths put a row under
`Blocked on you` today whatever the coordinator's position:

- **A holding passed with `--blocked <session>=<need>`** (`progress-view.sh`,
  the first `row("Blocked on you"; ...)`). The need is one of three kinds:
  `credential <name>`, `reserved-step <merge|release|close|teardown> <link>` or
  `access <owner/repo>`. For a bound coordinator, `need-check.sh` and
  `progress-view.sh --dispatcher` reword a reserved merge, close or release to
  `<step> <link>, for dispatcher <instance>`, but the row's kind stays
  `Blocked on you`.
- **A decision entry escalated to `a person`** (the second `Blocked on you`
  row). `state-decision.sh` already targets `coordinator <reports_to>` when the
  run reports to a coordinator, and those entries render under `Ongoing` as
  "with `<coordinator>` for a decision", so this path is already right. It's
  the case the issue keeps: an entry that has to reach a person stays
  person-blocked.
- **The reconcile report's table** (`reconcile-report.sh`), which builds the same
  four kinds from the reconcile facts and puts CI that never started and an
  unconfirmed merge under `Blocked on you` for every coordinator.

So a person who talks to a bound coordinator directly, and asks it for status,
sees a release its dispatcher is cutting or a fix another lane is landing
listed as theirs to act on. They can't tell what needs them from what's
already moving up the chain, and the chain's rows are exactly the ones they
might choose to step in on (tsukumogami/shirabe#1670).

There's a second gap underneath the label. The need kinds describe what a
person holds: a credential, a reserved step, repository access. Nothing in
them can say "waits on another lane's fix" or "waits on a release in flight",
so a coordinator whose holding waits on the chain either forces the wait into
`reserved-step` or has no way to show it as blocked at all.

The issue asks for:

- a row blocked on the person reading the table, and only those, under a kind
  that says so;
- a row blocked on the chain above the coordinator under a separate kind that
  names who it waits on: the dispatching coordinator, another lane, a release,
  a fix in flight;
- a root coordinator unchanged for what its human dispatcher owes, and a bound
  coordinator putting what its dispatcher owes under the chain kind, except an
  escalated decision entry that has to reach a person;
- a row's kind decided by who it waits on, not by who the report is addressed
  to, so one table reads correctly for a person and for the dispatching
  coordinator;
- `progress-view.sh` refusing a table that puts the same row under both kinds,
  and the skill's Reporting section describing both kinds and when each
  applies.

A Planned design, `docs/designs/DESIGN-coordinator-authority-settled-steps.md`,
changes the same code. It removes `--dispatcher` and `need-check.sh`'s
bound-or-root branch, and words a held or routed finishing step from a
settler the workspace's authority answer names (`session`, `dispatcher` or
`person`). The rule this design picks has to give the right kind today, when
the dispatcher comes from the stored grant, and still give it once that design
lands.

Out of scope: the template's guidance for CI that never started tells the
coordinator to pass `--blocked <worker>=CI did not run: <reason>`, a need
`progress-view.sh` refuses. That's a missing need kind for whoever holds the
account, independent of which blocked kind the row lands in, and it's tracked
separately as tsukumogami/shirabe#1671.

## Decision Drivers

- **The kind follows the waited-on party, not the addressee.** The same
  holding has to land in the same kind whether a person or the dispatching
  coordinator reads the table.
- **Facts over the coordinator's word.** Every existing row kind is checked
  against facts the script reads (pick facts, the stored need, the decision
  record). A new kind that rests on a free-text claim would reopen the gap the
  decisions design closed, where a decision travelled as a need.
- **The chain row names what it waits on.** "Blocked up the chain" with no
  target fails the issue's second criterion, so the target is part of the
  row, worded from a closed set rather than free text.
- **A root coordinator's table doesn't move.** What a person dispatcher owes
  stays where and how it is, byte for byte where the inputs are unchanged.
- **One rule, one place.** Today the bound-or-root choice is made twice
  (`need-check.sh` from the stored grant, `progress-view.sh` from
  `--dispatcher`) and the reconcile table hard-codes its own. The kind rule
  should live where the planned authority design can swap its input without
  touching every renderer.
- **Existing tables and in-flight runs keep working.** A run started before
  the change has needs stored under the old shape and reports already sealed
  with the old kind names. The change can't make either unreadable or refuse
  a table it accepted yesterday without saying why.

## Considered Options

### Decision 1: How a blocked row's kind is decided, and where the rule lives

Three places put rows under `Blocked on you` today, each from its own input.
`need-check.sh` words a reserved step's cell from `coord/posture.json`
`grant_check` when the need is stored, but never changes its kind.
`progress-view.sh` re-parses the need the agent types into `--blocked` and
words it from the agent-typed `--dispatcher`. `reconcile-report.sh`
hard-codes the kind for a decision escalated to a person, CI that never
started and an unconfirmed merge, with no position input at all. No script
reads `coord/need.json`: it holds `{kind, argument, cell}`, names no holding,
and each accepted need replaces the last. Nothing the scripts read names
another lane, a release or a fix for an ordinary holding. The record has a
closed `merged owner/repo#n` / `tag owner/repo <tag>` grammar, but only for
merge holds and pauses.

Key assumptions:
- Bound or root, for reserved steps and the reconcile rows, follows
  `grant_check`, the source `need-check.sh` uses today. Decisions keep their
  stored target, which `state-decision.sh` takes from the run's reports-to.
  A bound run whose authority lookup was skipped can therefore show a decision
  under the chain kind and a reserved step under the reader kind.
- A wait on another lane, a release or a fix is something the coordinator
  knows and the record doesn't. If a fact the worker records lands first,
  `--chain` reads that fact instead of the flag.

#### Chosen: Fact-derived kinds in a shared rule, with a closed chain flag for waits no fact records

One jq module, `kinds.jq`, included by `progress-view.sh` and
`reconcile-report.sh`, decides every blocked row's kind. Its inputs are the
row's need kind and one position fact: whether the run is bound and, if it
is, the dispatcher's name. One helper reads that fact from `grant_check`;
`pick-facts.sh` carries it into pick facts and `reconcile-pass.sh` into the
reconcile facts.

For a bound run:

- a reserved merge, close or release goes to `Blocked up the chain` with the
  target `dispatcher <name>`;
- an unconfirmed merge in the reconcile table goes there too, with the same
  target, since the dispatcher settles a bound run's merges;
- a decision escalated to a coordinator goes there under its stored target,
  instead of Ongoing;
- credential, access and teardown needs, CI that never started, and decisions
  escalated to `a person` stay `Blocked on you`.

For a root run nothing moves, and every row renders byte for byte as it does
today.

Waits the record can't show come through a new flag,
`--chain <worker>=<target>`, which accepts only `lane <topic>`,
`fix merged owner/repo#n` and `release tag owner/repo <tag>`. `kinds.jq`
checks them with the grammar `state-schema.jq` already defines for holds and
pauses. `dispatcher` is never accepted on the flag; it is only derived. A fix
that is one of the run's own holdings is checked against pick facts. Another
lane's fix and a release tag are checked for shape only, and a reader should
take them as the coordinator's statement. A worker named in both `--blocked`
and `--chain` is refused, which gives the "same row under both kinds"
criterion a refusal a test can reach. Nothing reads the network to render.
`--dispatcher` stays accepted, and is refused only when it disagrees with the
position fact, until the authority design removes it (Decision 2).
`coord/need.json` keeps its shape.

This is the only shape that meets every one of the issue's criteria in one
change while keeping each case a fact can decide away from the coordinator's
word. The reported bug, a dispatcher-owed step listed as the person's, is
decided entirely by the position fact. The rule lives in one module, so the
authority design later swaps its input in one place. A root table doesn't
move because no new branch fires on a root run, and no stored shape changes.

Lane, fix and release targets are the accepted trade-off: they rest on the
coordinator's claim, checked for shape. The drivers ask for a target worded
from a closed set rather than free text, which the flag meets. It also opens
no new way to hide a wait that needs a person. Leaving a worker out of
`--blocked` already sends it to Ongoing today, and a chain row is more
visible than an Ongoing one, not less.

The escalated-decision move follows the issue's wording: a bound coordinator
puts what its dispatcher owes under the chain kind, except an escalated
decision entry that has to reach a person. A decision escalated to the
dispatching coordinator is owed by that coordinator. It can't touch a root
run, whose decisions always target a person.

#### Alternatives Considered

**Derive only, with the chain flag deferred.** The same rule with the full
target set declared and only `dispatcher` written; lane, fix and release
wait for a fact the worker records. Rejected: it leaves the issue's chain
targets other than the dispatcher unmet, and leaves those rows in Ongoing,
where they read as active work. That is the confusion the issue reports. It is
the fallback if a shape-checked claim is judged unacceptable under "facts over
the coordinator's word".

**A stored `waits_on` per holding.** `need-check.sh` validates and stores a
`waits_on` with each need, in a key per holding, and `progress-view.sh` reads
the stored needs. Rejected: it's the largest change (what the `surface` state
accepts, a key per holding, a new reader in `pick-facts.sh`) for targets that
still rest on the coordinator's word. A stored need left behind after a worker
moves on keeps its row blocked, which is the one runtime path that breaks the
root byte-for-byte promise. The authority design reshapes the stored need
anyway. Its direction, a stored need per holding that `kinds.jq` reads, is the
end state for that design to build.

**Render-time flags only, with the dispatcher on the flag.** Rejected in favor
of deriving the dispatcher case: a fact exists for it, and a typed dispatcher
target would be the coordinator's word where the record already knows the
answer.

### Decision 2: Ordering against the authority design, and the cost to runs in flight

`docs/designs/DESIGN-coordinator-authority-settled-steps.md` changes the same
code. Its Phase 3 changes `need-check.sh` and `progress-view.sh`, removes
`--dispatcher` and the grant fold table, and replaces the bound-or-root
sentences. It also says no file but `settle-check.sh` maps grants or settlers
to an outcome. Its implementation waits on workspace authority work that
hasn't shipped: an answer for a root session, an addressable dispatcher
target, and tsukumogami/niwa#422. It never says which table kind a held step
gets.

Runs in flight pick up new scripts: gate scripts run from the run's plugin
root on every tick, and an upgrade rebinds a run at its next start. The
template stays the copy compiled when the run opened, so an old run's
directive keeps telling the agent to pass `--dispatcher`. `coord/pick.json` is
rewritten on every pick visit, and no reader refuses a missing or extra key.
Reconcile facts aren't stored, and a sealed reconcile report renders its
stored kind unchanged. Nothing lists the allowed kind strings.

Key assumptions:
- Plugin upgrades land at a version-specific root, and a rebind keeps the
  run's compiled template.
- The agent runs `progress-view.sh` from the plugin its session loaded.
- A held finishing step renders under `Blocked on you` with its closed hold
  reason, because a hold means nothing in the chain can settle the step until
  a person changes the workspace's authority.

#### Chosen: Land this change first, and hand `kinds.jq`'s input to the authority design

This change ships on the `grant_check` reading `need-check.sh` already makes.
`kinds.jq` is a display rule: it maps a row to a kind and a target, routes
nothing and settles no step, so it adds no second decision-maker beside
`settle-check.sh`. Its position input is the one bound-or-root reading the
authority design's Phase 3 has to replace.

The change amends the Planned authority design in two places. Its Phase 3
swaps `kinds.jq`'s input from `grant_check` to the stored settle outcome
(settler, and take, route or hold). It also states the kind a held step
renders under. The swap is then one module's input, not every renderer.

Runs in flight:

- A run on an old template keeps passing `--dispatcher`, so the flag stays
  accepted and checked until the authority design's Phase 3 removes it. Such a
  run's agent doesn't know `--chain`, so its lane, fix and release waits stay
  in Ongoing as today. Its dispatcher-owed steps still move to the chain kind,
  from the fact.
- An old `coord/pick.json` with no position field reads as null, which
  `kinds.jq` treats as root. That gives today's table until the next pick
  visit rewrites the file.
- Sealed reconcile reports keep their stored kind strings and render
  unchanged. The renderer doesn't re-derive kinds.
- Editing `need-check.sh`, `pick-facts.sh`, `reconcile-pass.sh` or
  `reconcile-report.sh` moves the compat table's script digest, which is
  re-recorded in the same change. `kinds.jq` comes in by `include` and isn't
  in that digest today, so the change adds it.

Waiting, or landing together, ties the issue to workspace authority work with
no date. The authority design itself says shipping before that work would
hold every root coordinator's finishing steps. Landing first fixes the
reported confusion now, on a fact the skill already reads, and the later swap
touches one input.

#### Alternatives Considered

**Wait for the authority design**, and build `kinds.jq` on the settler from
the start. Rejected: that design waits on unshipped work, and the issue's fix
doesn't depend on it.

**Land the two together**, folding the issue into the authority design's
Phase 3. Rejected for the same dependency, and because it makes one large
change out of two that can be tested apart. That Phase 3 is already the
design's widest step.

### Decision 3: The chain kind's name

The new kind needs a name that reads as the counterpart of `Blocked on you`
and says the wait sits above the coordinator.

#### Chosen: `Blocked up the chain`

It uses the issue's own phrase and pairs with `Blocked on you`: both say
blocked, and each says on whom.

#### Alternatives Considered

**`Waiting on the chain`.** Rejected: "waiting" reads as softer than
"blocked" for a row that can't move until someone else acts.

**`Blocked upstream`.** Rejected: "upstream" already names a document's
source artifact in shirabe (the `upstream` frontmatter field and the
`--upstream` flag a brief can pass), and in git it means the remote branch.

### Decision 4: Where the chain kind sits in the table

The table lists its kinds in a fixed order, and tests pin that order.

#### Chosen: Between `Blocked on you` and `Ongoing`

Blocked rows stay together, the person's first. A root table has no chain
rows, so its order is unchanged.

#### Alternatives Considered

**After `Ongoing`.** Rejected: it separates the two blocked kinds and puts a
row that waits on someone below rows that are moving.

### Decision 5: Where the position fact is read

`pick-facts.sh` and `reconcile-pass.sh` both need the same bound-or-root fact
from the session's posture.

#### Chosen: `lib_position` in `state-common.sh`

Both scripts already source `state-common.sh`, and it already holds the
readers for the session's variables. One function keeps one reading.

#### Alternatives Considered

**A new script, called by each.** Rejected: it adds a process and a file for
a few lines that both callers can share by sourcing.

### Decision 6: How `kinds.jq` enters the compat digest

The compat table's `gate_scripts` digest covers what `check-template-compat.sh`
finds by following `$HERE/<file>` references from the scripts a template
reaches. A module pulled in with jq `include` isn't followed, so `kinds.jq`
would change without moving the digest.

#### Chosen: A `$HERE/kinds.jq` reference in `reconcile-report.sh`

`reconcile-report.sh` is reached from a gate, and a direct reference puts the
module in the digest without touching the shared check.

#### Alternatives Considered

**Teach `check-template-compat.sh` to follow `include`.** Not chosen for this
change because it alters a check every template relies on. It's the better
long-term fix: `state-schema.jq` has the same blind spot today. It's left as a
follow-up.

### Decision 7: Where a chain row shows its target

A chain row has to name what it waits on, and the table has a status cell and
a next cell.

#### Chosen: The status cell reads `waits on <target>`

The status cell is what a reader scans down. The next cell keeps the need's
wording where it is today, so a reserved step reads the same apart from its
kind and status.

#### Alternatives Considered

**The target in the next cell.** Rejected: it would push the need's own
wording aside, and the status cell would then say only "blocked" for both
kinds.

### Decision 8: A missing position fact

Pick facts written before this change, and a session whose posture can't be
read, have no position fact.

#### Chosen: Read a missing or null fact as root

That gives today's table, which is what the run showed before the change.
Decision 2's migration path relies on it: an old `coord/pick.json` renders as
before until the next pick visit rewrites it.

#### Alternatives Considered

**Refuse the table.** Rejected: an in-flight run would lose its report until
its next pick visit, for a fact whose absence has a safe reading.

## Decision Outcome

A blocked row's kind comes from one rule, `kinds.jq`, which both table
renderers include. It reads one position fact that the pick and reconcile
facts carry. On a bound run, what the dispatcher owes moves to
`Blocked up the chain` with the dispatcher named: a reserved merge, close or
release, an unconfirmed merge, and a decision escalated to it. What only a
person can supply stays `Blocked on you`. A closed `--chain` flag names the
lane, fix or release a holding waits on when no fact records it, and a
worker can't sit under both kinds. A root run's table doesn't change.

The two decisions fit because the first keeps every input to the rule in one
place and the second makes that place the authority design's handover point.
`kinds.jq` decides how a row reads, never who settles a step. When the
authority design lands, it swaps the position fact for the settle outcome,
retires `--dispatcher`, and leaves the renderers alone. Nothing stored changes
shape, so runs already in flight keep producing a table throughout, and
reports sealed before the change still read as they did.

## Solution Architecture

### Overview

The progress table and the reconcile report's table get a fifth kind,
`Blocked up the chain`. It sits between `Blocked on you` and `Ongoing`. One
jq module decides, for every blocked row, which of the two blocked kinds it
takes and what a chain row names as its target. Both renderers include the
module and feed it the same position fact. The scripts that already read the
session (`pick-facts.sh` and `reconcile-pass.sh`) carry that fact into the
facts each renderer reads. `progress-view.sh` keeps its `--blocked` and
`--next` flags and gains `--chain` for waits nothing stored records.
`need-check.sh`, `coord/need.json` and the decision record don't change.

### Components

**`skills/coordinate/scripts/kinds.jq` (new).** The kind rule. It holds no
I/O and no wording beyond the target words. It defines:

- `position_bound`, true when the position fact says bound with a
  dispatcher name. A null or missing fact is root.
- `need_kind($need; $position)`, which returns `{kind, target}` for a row
  `--blocked` names. A `reserved-step merge|close|release` on a bound run is
  `Blocked up the chain` with target `dispatcher <name>`. Every other need
  (credential, access, a reserved teardown), and every need on a root run, is
  `Blocked on you` with no target.
- `decision_kind($decision)`, which sends an entry escalated to `a person` to
  `Blocked on you` and an entry escalated to `coordinator <topic>` to
  `Blocked up the chain` with that target. Proposed and verdict-pending
  entries keep their Ongoing rows.
- `chain_target($t; $holdings)`, which checks a `--chain` value against the
  closed grammar: `lane <topic>` (`re_topic`), `fix merged owner/repo#n`
  (`re_pr_ref`), `release tag owner/repo <tag>` (`re_repo`, `re_tag`). A fix
  naming one of the run's own holdings must match that holding's pull request
  in the pick facts and must not be merged. It returns the target words or an
  error.
- `target_words`, the cell text for a target: `dispatcher <name>`,
  `lane <topic>`, `<owner/repo#n> to merge`, `<owner/repo> tagged <tag>`.

It includes `state-schema` for the shared regexes and adds no new grammar of
its own.

**`skills/coordinate/scripts/state-common.sh`.** A new `lib_position
<session>` reads `coord/posture.json` and prints the position fact as one
JSON value: `{"bound": true, "dispatcher": "<instance>"}` when
`grant_check.state` is `bound` and the parent instance passes the name check
`need-check.sh` already applies; `{"bound": true, "dispatcher": null}` for a
bound run with no usable instance name; `{"bound": false}` otherwise,
including a missing or unreadable posture. This is the one reader of the
bound-or-root fact for kinds. `need-check.sh` keeps its own reading for the
cell until the authority design removes it.

**`skills/coordinate/scripts/pick-facts.sh`.** Adds `position`, from
`lib_position`, to the pick facts it writes.

**`skills/coordinate/scripts/reconcile-pass.sh`.** Adds `position`, from
`lib_position`, to the reconcile facts it assembles before calling
`reconcile-report.sh json`.

**`skills/coordinate/scripts/progress-view.sh`.**
- Includes `kinds`.
- Renders each `--blocked` row under the kind `need_kind` returns. A chain
  row's status reads `waits on <target words>`; its next cell keeps the
  need's worded cell.
- Renders decision rows through `decision_kind`.
- Gains `--chain WORKER=TARGET`, repeatable. Its rows are `Blocked up the
  chain` with status `waits on <target words>` and next `--next`'s text or
  `report at its next checkpoint`.
- Refuses a worker named in both `--blocked` and `--chain`, a `--chain` key
  with no holding or on a ready holding, and a target `chain_target` refuses.
- `--dispatcher NAME` stays accepted. It is refused when the position fact is
  root, or names a different dispatcher. Otherwise it changes nothing.

**`skills/coordinate/scripts/reconcile-report.sh`.**
- Includes `kinds`.
- A bound run's unconfirmed merge goes to `Blocked up the chain` with the
  dispatcher target.
- Decision rows go through `decision_kind`.
- Its not-run CI row stays `Blocked on you`.
- `md` keeps printing each sealed row's stored `.kind`.
- Carries a `$HERE/kinds.jq` reference, so the compat table's `gate_scripts`
  digest covers the module.

**Text.**
- `SKILL.md`: Reporting and the Glossary's "The human" describe both blocked
  kinds and when each applies.
- `references/loop.md:181`: the same.
- The template's `surface` and `wait` prose:
  - stops telling the agent to pass `--dispatcher`;
  - says when to pass `--chain`;
  - says a bound run's reserved steps move without a flag.
- `docs/designs/DESIGN-coordinator-authority-settled-steps.md` gains the two
  amendments from Decision 2.

### Key Interfaces

Position fact, in pick facts and reconcile facts:

```json
"position": {"bound": true, "dispatcher": "<instance>"}
"position": {"bound": false}
```

Absent or null reads as root.

New flag:

```
progress-view.sh [--merge-order ...] [--blocked T=NEED]... [--chain T=TARGET]... [--next K=TEXT]... [< pick.json]
  TARGET := lane <topic> | fix merged <owner/repo#n> | release tag <owner/repo> <tag>
```

Exit 64 on a refused flag, with the reason on stderr, as today.

Table kinds, in order: `Ready to merge`, `Blocked on you`,
`Blocked up the chain`, `Ongoing`, `Waiting to be assigned`. A row appears
under exactly one kind.

### Data Flow

1. `pick-facts.sh` runs at a pick visit. It reads the session's posture
   through `lib_position` and writes `position` into the pick facts beside the
   holdings, units and decisions it already writes.
2. When the coordinator reports, it runs `progress-view.sh` with the pick
   facts, the `--blocked` needs it submitted at `surface`, and any `--chain`
   waits.
3. `kinds.jq` sorts each blocked row and each escalated decision by the
   position fact, the need kind and the decision's stored target, and words
   the target. A root run takes the same branches it takes today.
4. At a reconcile, `reconcile-pass.sh` adds `position` to the reconcile facts.
   `reconcile-report.sh json` builds the table through the same module, and
   the report is sealed with its kind strings. `md` renders them as stored.
5. The authority design's Phase 3 later replaces step 1's input: the stored
   settle outcome instead of `grant_check`. Steps 2 to 4 are unchanged.

## Implementation Approach

### Phase 1: The rule and the position fact

`kinds.jq` and its tests, `lib_position`, and `position` in the pick facts.
`progress-view.sh` renders `--blocked` rows and decision rows through the
module, and checks `--dispatcher` against the fact. This fixes the reported
case, a bound run's reserved step, without any new flag.

Deliverables:
- `skills/coordinate/scripts/kinds.jq`
- `lib_position` in `state-common.sh`; `pick-facts.sh`
- `progress-view.sh`, and `progress-view_test.sh`: the bound cases at
  :112-118 and the coordinator decision row at :153 move to the new kind, and
  the root assertions stay as they are.

### Phase 2: The reconcile table

`reconcile-pass.sh` carries `position`. `reconcile-report.sh` uses the module
for its unconfirmed-merge and decision rows and references `kinds.jq` for the
digest. The compat table's `gate_scripts` digest is re-recorded. Depends on
Phase 1's module.

Deliverables:
- `reconcile-pass.sh`, `reconcile-report.sh`, `reconcile-report_test.sh`
  (bound fixtures added beside the existing root ones)
- `skills/coordinate/koto-templates/coordinate.compat.json`

### Phase 3: The chain flag

`--chain` with its grammar, the own-holding fix check and the refusals.
Depends on Phase 1.

Deliverables:
- `progress-view.sh`, `kinds.jq`, `progress-view_test.sh` (each target form,
  each refusal, a worker under both flags)

### Phase 4: The text

SKILL.md, `references/loop.md`, the template's `surface` and `wait` prose,
the evals that name `Blocked on you`, and the authority design's two
amendments. Depends on Phases 1 to 3, so the prose describes what ships.

Deliverables:
- `skills/coordinate/SKILL.md`, `skills/coordinate/references/loop.md`
- `skills/coordinate/koto-templates/coordinate.md`, and its compat entry
- `skills/coordinate/evals/evals.json`, `testdata/rule-coverage.tsv`
- `docs/designs/DESIGN-coordinator-authority-settled-steps.md`

## Security Considerations

This change alters how the coordinate skill's progress table and reconcile
report sort and word their rows. It downloads and runs nothing, reads nothing
from the network and needs no new permission: it reads `coord/posture.json`,
which `need-check.sh` already reads, and adds one field to facts that
`pick-facts.sh` and `reconcile-pass.sh` already write. Three inputs reach the
rendered table: the `--chain` flag, which the coordinator types; the
dispatcher name, read from the session's posture; and the `position` fact.
The table is markdown, and a sealed reconcile report is read later by a
dispatching coordinator, so the risk worth guarding is a value that breaks or
forges a row.

**Table injection.** `chain_target` accepts only `lane <topic>`,
`fix merged <owner/repo#n>` and `release tag <owner/repo> <tag>`, checked
with `re_topic`, `re_pr_ref`, `re_repo` and `re_tag` from `state-schema.jq`.
Those regexes are anchored and use closed character classes, so a `|`, a
control character or a newline inside a value is already refused. jq's `$`
also matches just before a final newline, though, so they accept a value that
ends in one. `chain_target` refuses that case on its own instead of relying on
the shared regexes, and `lib_position` applies the dispatcher name check
with the same end-of-string anchoring. Tests cover one refusal per case: a
`|`, a control character, an embedded newline and a trailing newline, for
each target form and for the dispatcher name. Fixing the shared regexes
themselves is left to tsukumogami/shirabe#1703, because other state checks
use them.

**Display, not authority.** `kinds.jq` decides how a row reads. It routes
nothing and settles no step. On a bound run, credential, access and teardown
needs, CI that never started, and decisions that have to reach a person stay
`Blocked on you`, decided by the need kind rather than by any flag. A worker
can't be named in both `--blocked` and `--chain`, so `--chain` can't relabel
a need the coordinator lists for the person. It can only move a wait that
would otherwise show as Ongoing. A missing, null or unreadable position fact
reads as root, so a bound run whose lookup failed shows what its dispatcher
owes under `Blocked on you`: the error leans toward the reader seeing too
much, never toward hiding a row from them. The residual risk is the one named
under Consequences: lane, release and outside-fix targets are the
coordinator's statement, checked for shape only, and the row's wording marks
them as such.

**Module loading and integrity.** `progress-view.sh` already runs jq with
`-L "$HERE"` and includes `state-schema` from the script's own directory.
Both renderers load `kinds` the same way, so a `kinds.jq` in the working
directory or in a checkout a worker can write to is never picked up in place
of the plugin's copy. `kinds.jq` enters the compat table's `gate_scripts`
digest through the `$HERE/kinds.jq` reference in `reconcile-report.sh`
(Decision 6). That reference is easy to drop in a later edit, so
`scripts/check-template-compat_test.sh` gains a case that fails when a change
to `kinds.jq` doesn't change the digest. `state-schema.jq` has the same blind
spot today. Teaching the check to follow `include` is the follow-up Decision
6 names.

**Data exposure.** The table adds the dispatcher's instance name and chain
targets (a lane topic, `owner/repo#n`, a tag). The run already holds all of
them, and its output goes only to its own person or dispatching coordinator.
Nothing leaves the machine. A chain target comes only from the closed
grammar, so no credential name or free text can appear in one, and the
`credential <name>` need keeps its current wording under `Blocked on you`.

## Consequences

### Positive

- A person talking to a bound coordinator sees only what needs them under
  `Blocked on you`. What the dispatcher owes is listed under
  `Blocked up the chain` with the dispatcher named.
- The progress table and the reconcile table share one rule, where today they
  each hard-code their own.
- The reported case is decided by a fact. The coordinator can't move a
  dispatcher-owed step back to the person, or a credential or access need it
  passes with `--blocked` up the chain.
- The authority design's swap touches one input in one module.
- A root coordinator's table is byte for byte what it is today.

### Negative

- Lane, fix and release targets outside the run's own holdings are the
  coordinator's statement, checked only for shape.
- A bound run whose authority lookup was skipped can show a decision under
  the chain kind and a reserved step under the reader kind, because the two
  read different facts.
- Runs on an old template don't know `--chain`. Their lane and release waits
  stay in Ongoing until they restart on the new template.
- `--dispatcher` lingers as a checked flag that does nothing, until the
  authority design removes it.
- `need-check.sh` and `progress-view.sh` still each carry a copy of the need
  grammar.

### Mitigations

- The chain row's wording marks a claimed target as the coordinator's. A
  worker can't be under both `--blocked` and `--chain`, so a claim can't
  relabel a need the coordinator lists for the person; it can only move a wait
  the coordinator would otherwise show as Ongoing. A fix target that is one of
  the run's own holdings is checked against the pick facts.
- The design names the skipped-lookup disagreement. The authority design
  replaces both readings with the settle outcome, which ends it.
- Old templates still get the fact-decided move, which is the case the issue
  reports. Only the optional flag waits for a restart.
- `--dispatcher` is refused when it disagrees with the fact, so a stale flag
  can't misplace a row while it lingers.
- The duplicated grammar is unchanged by this design and stays a known gap,
  not a new one.
