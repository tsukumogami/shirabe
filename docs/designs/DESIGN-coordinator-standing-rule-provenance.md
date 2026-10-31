---
schema: design/v1
status: Proposed
problem: |
  A coordinator's Standing rows hold only five kinds of person-owned event,
  with a free-text owner and relayer, and end by deletion; the process rules
  it runs under ride forward in brief prose. A successor asked why it follows
  a rule can't say who said it, when, where the words are or whether it still
  stands, and a rule the owner took back can survive in a copied brief and be
  acted on again. koto's decision record is being built to answer those
  questions for every delegated decision, and this work has to use it rather
  than build a second set of fields or a second reversal.
decision: |
  Standing gains a `rule` kind and one optional Source column that cites a
  koto decision, a skill line, a document, a pinned file, or names the rule
  inferred. No column stores a class: one schema function works it out at
  read, and owner-said means a cited person decision entered at a root
  coordinator, which a manager reaches only by citing its director's. A cited
  rule's status is koto's, so an owner's reversal reads superseded wherever
  the rule was copied. Rows written before the change are read in place as
  relayed, keeping their owner, time and recording entry, and brief rules come
  in once as flagged inferred rows. A successor that continues a run may
  reverse below its predecessor, standing where the predecessor stood, read
  from koto's supersede fence and never higher.
rationale: |
  Citing instead of copying keeps one set of provenance fields and one
  reversal, and deriving the class leaves a coordinator no field in which to
  call its own prose the owner's word. Reading old rows in place, behind a
  reader release that ships before any writer, keeps every current reader and
  older plugins working without a conversion pass. The successor answer
  follows from the rest: without it, an owner ruling recorded at the root
  could not be reversed after the first handoff, and the fence is the one
  record tying a run's members together that the successor doesn't write
  about itself.
upstream: docs/briefs/BRIEF-coordinator-standing-rule-provenance.md
---

# DESIGN: Standing rules that carry their provenance

## Status

Proposed

## Context and Problem Statement

A coordinator (a manager over one lane, or a director over managers) is
replaced every few hours as its context fills, and each successor starts from
the record its predecessor left plus a brief. The record's Standing section
is the one place a rule survives a handoff with its source attached, and it
holds only five kinds of event a person owns: a pause, a go-ahead, an
approval, an answer and an assignment. Each row names an Owner and a Relayed
by in free text and a Set time, and nothing else about where the words came
from. A row ends by being deleted (`state-stored-set.sh --end`), so a rule
the owner took back leaves no trace a successor can read.

Everything else a coordinator runs under lives outside the record. Process
rules (how to report, what not to touch, which commands to avoid) ride in the
brief as prose, copied forward from one successor to the next. A role's
definition and the coordinator's own judgment calls never enter any record.
The Run section has `rules` and `briefs` digest rows meant to pin the files a
coordinator ran with, but nothing writes or compares them. A long-lived
lineage therefore accumulates rules nobody can trace: a successor asked why it
follows one can say only that its brief says so. A rule the owner reversed can
survive in the brief after the Standing row that recorded it was deleted,
and be acted on again.

koto's decision record (`docs/designs/DESIGN-decision-record.md` in koto) is
being built to answer "who decided this, on what authority, and does it still
stand" for every delegated decision, and it defines a reversal: a `reverse`
decision aimed at the original, with standing rules, a race rule, and a
status every reader computes the same way. An owner ruling is a decision a
person made. This design reuses those fields and that reversal for standing
rules rather than defining a second set beside them.

The design has to settle four things:

1. The field names a rule row carries, and where process rules live beside
   owner rulings.
2. What marks a row as the owner's word, and who can make it so.
3. How rows written before the change are read by every tool that reads the
   record today.
4. Whether a successor that continues a predecessor's run may reverse a
   decision made below that predecessor, a question koto's decision record
   left open for this work to answer.

Out of scope: compiling a successor's brief from the rows and a receiver's
restatement at handoff, which are later work that reads the interface this
design names; who settles a step, escalation targets and grants, which the
authority model owns; and the record's container, which this design adds
rows and reads inside.

## Decision Drivers

- **One set of provenance fields.** Who decided, when, on what authority,
  and whether it still stands come from koto's decision record. A rule row
  cites a decision; it doesn't copy its fields.
- **One reversal mechanism.** A rule the owner takes back is reversed through
  koto's `reverse`, and every reader reads its status from koto. No status
  field, end flag or supersession column in the row stands in for it.
- **Inside the existing container.** Rows go in `record/standing`, written by
  `state-stored-set.sh` through the write core, under the one-writer rule and
  the size the record already carries. No new key outside Standing; nothing
  touches `record/decisions` or `record/reversals`.
- **Old rows keep working.** Sixteen scripts and the schema read Standing
  today (pause reads in pick, the dispatch check, the land check and the
  merge; pick's assignment units; the handover read; the carry; the progress
  view; the write core's comparison).
  Each must read a row written before this change exactly as it does now, and
  a lineage started before it keeps every rule it had.
- **Attribution, not authentication.** koto records a person's handle as
  handed text, and an agent can claim to be a person. The design can't make a
  claim true; it can make every claim attributable and keep a coordinator from
  minting owner rulings out of its own prose.
- **Checkable by someone who didn't write it.** Each of the milestone's
  outcomes has to be something a reviewer can run against a real record and
  see hold or fail.
- **koto ships first.** The decision commands aren't released yet. Whatever
  can land before them should, and nothing should need rework when they
  arrive.

## Considered Options

### Decision 1: The fields of a rule row, and where process rules live

A Standing row is `{standing, kind, on, until, what, owner, relayed_by,
set}` today, and its five kinds are all events a person owns. The rules a
coordinator leans on beyond those (lines of the skill, its charter or
roadmap, the workspace's own rule files, what its brief says) have no row at
all. koto's decision record answers who, when, on what authority and whether
it still stands for anything recorded as a decision, addressed from outside
by session name and a 12-digit identifier, and its requirements set the
pattern for shirabe's own tables: each row gains one field citing the
decision, and every existing reader passes unchanged. Two facts about the
record shape the answer. `check_srow` in `state-schema.jq` refuses a column
it doesn't know and rebuilds every row with all its columns, so a new column
reaches every stored row unless an empty one is left out. And every reader
except the handover and the carry picks rows by kind, so a new kind is
invisible to the pause, pick, land and merge paths.

Key assumptions:
- koto keeps the (session name, 12-digit id) address and a read that returns
  a decision's decider kind and status. If not, only the citation's grammar
  changes.
- Skill text and charter text are not decisions: nobody records a koto
  decision per line of a skill.

#### Chosen: A `rule` kind plus one typed Source column, the class worked out at read

Standing gains one kind and one column. A `rule` row is a rule that binds
the coordinator until it is reversed or ended; like an approval or an answer
it has no On and no Until. What holds the rule's words in one line and Set
keeps its meaning; Owner and Relayed by stay blank, since the Source says
who said it (Components). Owner rulings and process rules
are both `rule` rows. What tells them apart is the Source.

`source` is optional on the five existing kinds and required on a `rule`
row. It takes one of five forms:

| Form | What it points at |
|---|---|
| `decision <session> <id>` | a koto decision; who, when, where and whether it stands are all read from koto |
| `skill <owner/repo> <path> <commit>` | a line of a skill's text, in the repository, path and commit form koto uses for a document subject |
| `doc <owner/repo> <path> <commit>` | a charter, roadmap, strategy, PRD or design a public host can name |
| `pinned <label> sha256:<64 hex>` | a file the Run section pins as `rules <label>` or `briefs <label>`, its location kept in `record/host`, for a file a public host can't name |
| `inferred [brief <label> sha256:<64 hex>]` | the coordinator's own reading, optionally naming the brief it was read from |

No column stores the rule's class. One function in `state-schema.jq`,
`rule_class`, reads the Source (and, for a citation, what koto recorded about
the cited decision) and returns the class. That leaves nothing that can
disagree with koto and no field in which a coordinator could label its own
prose the owner's word. Process rules live in the same section as owner
rulings, and only when the brief would otherwise be their only carrier: text
every session loads by itself, the skill at its version and the workspace's
instruction files, isn't copied into rows, because the Run section's `rules`
digests already say which versions the coordinator ran with.

#### Alternatives Considered

- **A `rule` kind with a decision citation and nothing else.** Every rule
  row cites a koto decision and its class comes from the decider. Rejected
  because skill and charter text aren't decisions: those classes would have
  no rows or would need a decision made up for each line, and nothing could
  be written before koto's decision commands ship.
- **A typed Source plus a stored class column.** The chosen shape, with the
  writer also setting owner-said, skill-says, charter or inferred in a second
  column. Rejected because a stored class is a second provenance claim that
  can disagree with the cited decision, lets a coordinator write owner-said on
  its own prose, and keeps reading owner-said after the owner reverses the
  ruling until someone edits the row.
- **A separate key for process rules.** Owner rulings in Standing, process
  rules in a new `record/rules`. Rejected because it would need its own
  writer path, carry, handover gap, write-core comparison and size, a
  successor would read two places to learn what binds it, and the rows
  belong in Standing by the agreement between the roadmaps.
- **Mirroring every skill and workspace rule into Standing at first start.**
  Rejected because it copies text every session already loads at a pinned
  version, grows Standing past any sensible size, and goes stale the moment
  the skill moves on.

### Decision 2: What marks a row as the owner's word, and who can make it so

Owner and Relayed by are free text the coordinator types today, and the
skill tells it to write "the person as owner and yourself as relayer"
whenever a person's word arrives. Nothing records which session wrote the
row, and the coordinator can't tell who sent a message: a manager can't tell
its director's message from the owner typing. The handover gate even asks a
successor to write the person's carry acknowledgement itself. So a
coordinator can turn its own prose into an owner ruling with one command.

koto's decision record gives a person decider (a handle, a surface of
`terminal`, `forge` or `relay`, an optional link, and the session the
decision was entered through), records a relay with no https link as the
entering session's own decision with the person kept as a note, and lets only
a person reverse a person's decision. It can't prove a person typed
anything: a handle is always handed text. The readers that enforce Standing
(the pause read and everything built on it) never look at Owner, so the mark
matters for display, for handover and for the later work that reads it, and
enforcement can stay blind to it.

Key assumptions:
- koto can read a decision in another session on the same host, so a manager
  can read the person decision its director recorded. No koto acceptance
  criterion covers that read yet; if it fails, the manager's citation reads
  unreadable and the manager writes an uncited row instead.
- A coordinator dispatched by another coordinator has a koto dispatched-by
  link to that coordinator's session, which koto freezes into every decision
  it records there. The link is written by the dispatched session's own
  opener (`coordinate-open.sh --dispatched-by`), so it is the dispatcher's
  brief, not koto, that puts it there; a session that skips it also drops
  out of its dispatcher's hierarchy. The `reports-to` Run row is a second
  signal, never the only one, because the coordinator writes it itself.
- A carried run (a recycled coordinator) is linked dispatched-by to the
  earlier run of the same scope it carried, so a chain can name a session of
  the writer's own lineage that isn't above it.
- An owner ruling maps to a koto `judgment` (outcome `settled`) whose subject
  is the rule's words with a pointer to the Standing row, since an `accept`
  needs a repository path and commit that a spoken ruling lacks.

#### Chosen: Owner-said is read from the cited decision, and only a root coordinator enters the owner's word

The row stores no class and the writer takes no class flag. The same
`rule_class` function that readers use to label a row is what the writer
uses to refuse one. A cited row reads:

- **owner-said** when the cited decision's decider is a person and the
  decision was entered in a root coordinator's session. A session is a root
  only when neither the chain koto froze into the decision when it was
  recorded names a session holding a coordinator record for another scope,
  nor the session has a `reports-to` Run row; so a manager can't become a
  root by leaving its own row out. A chain session holding a record for the
  entering session's own scope is an earlier member of its lineage (the run
  it carried, or a predecessor that dispatched it) and is never above it, so
  a carried or continued director stays a root. koto already decides which
  surfaces count: `terminal` and `forge` as entered, `relay` only with an
  https link.
- **dispatcher-said** when the decider is a session on the writer's koto
  chain, the dispatched-by links koto froze when the writer was dispatched,
  or a later member of such a session's run, followed forward through koto's
  supersede fence the way Decision 4's hop follows it: a director's own
  ruling handed to a manager, including one the director's successor made
  after the manager was dispatched. The `reports-to` row never widens that
  set, since the coordinator writes it itself.
- **inferred**, flagged for confirmation, for any other citation: the
  writer's own session, or a person entered in a bound run (one that wasn't
  a root, by the test above, when it was entered). A citation that fails the test is a
  checked claim that failed, so it is flagged rather than passed over.
- **unreadable** when koto can't read the decision. It never counts as the
  owner's word and is never folded into inferred.

"The writer's own session" covers every member of the writer's run back
through koto's supersede fence, so a successor's carried citations keep
their class without the successor reaching higher than its predecessor. A
reversed decision keeps its class; what changes is its status, superseded.

An uncited event row reads relayed (Decision 3). Once koto's decision
commands and its supersede hop (Decision 4) are installed, the writer refuses a new event row that names a
person in Owner with no citation, so relayed can't stay open as an unflagged
channel for rows a coordinator writes from its own prose. That includes the
carry acknowledgement the handover gate asks a successor to write: after
koto ships, it has to cite a person decision recorded at the root.

Who can make a row owner-said follows from where the decision is entered. A
root coordinator, the director in practice, records the owner's words with
`koto decisions record --kind judgment --by person:<handle> --surface
terminal` when they arrive as the owner's turn in its own session, or with
`--surface forge` or `--surface relay --link <https>` when it holds a link to
where the owner wrote them, and then writes the row citing that decision. A
bound coordinator, a manager, never enters a person decision in its own
session: it reaches owner-said only by citing the decision its director
already recorded. Reversal then stays with a person under koto's rule, and a
director can't lift one lane's copy of the owner's ruling on its own.

"Only at the root" is one named test in `rule_class`. It is expected
behaviour, hardcoded where the owner's framing puts expectations, and it
grants nobody anything; if the authority model later names another place the
owner may speak, that test is the one thing it replaces.

The accepted trade-off: a root coordinator can still record `--by
person:<owner> --surface terminal` about its own prose. Neither shirabe nor
koto can stop that; koto says so itself. What this guarantees is that the
claim is a separate, write-once decision stamped with its entering session
and harness id, that it can only be made at the root, and that the owner
reads every person decision below them in one listing.

#### Alternatives Considered

- **A class cell the writer sets with a flag.** owner-said only with a
  citation or, before koto ships, a free-text source. Rejected because the
  flag is the coordinator vouching for itself, the cell copies koto's decider
  kind, and it keeps showing owner-said after a reversal until someone ends
  the row. Kept from it: the writer refuses a citation it can't verify.
- **Owner-said only with a link; a terminal decision reads unconfirmed.**
  Rejected because koto stores links without fetching them, so `--link
  https://<anything>` is as cheap a claim as `--surface terminal`, and the
  owner's commonest channel, typing to the director, would nearly always read
  unconfirmed. When the owner's verbatim words have a durable home, requiring
  a link is a change to the one test, not to rows.
- **Only the owner's own session holds owner-said; every copy below reads
  dispatcher-said.** Rejected because it weakens the owner's word one hop
  down and lets a director reverse one lane's copy alone, while citing the
  owner's decision leaves reversal with a person. Kept from it: a bound run
  never enters a person decision of its own.

### Decision 3: How rows written before the change are read, and how an old lineage keeps its rules

Every tool that reads Standing gets it through `rs_record` in
`state-read.sh`, which runs the record through `state-schema.jq`. That
grammar is closed: it refuses an unknown column, an unknown kind and an empty
Owner or Set, and rebuilds every row from its declared columns. So whether
old rows read unchanged, and whether an older plugin can read a newer record,
are both decided in that one file, and both depend on when the grammar
changes relative to when anything writes the new shape.

Plugins of different versions do meet. A takeover copies every `record/` key
and lets a successor on another plugin version drive the run while the
template's compat number matches. A grammar change moves no template
structure, so compat doesn't keep an older plugin off a newer record, and
raising it would also stop a new plugin continuing an old lineage. When an
older plugin meets a row its grammar refuses, `run_address` in
`coordinate-open.sh` reads the refusal as "no record", so the takeover fences
the predecessor and only then fails on every write.

The provenance an old row has is already on the record: Owner, Relayed by
and Set in the row, and the entry `--standing` wrote when it set the row
(`s<n> (<kind> ...): <what>. Owner: <owner>. Relayed by <relayer>.`), whose
id a lineage never reuses. Process rules in the brief have none of that.

Key assumptions:
- A discipline lineage's earlier rotation sessions are readable while koto
  keeps them; when one is gone, the row itself is the pointer of last resort.
- No plugin older than the reader release takes over a lineage after a row
  of the new shape is written into it. This is a residual risk, not a
  guarantee.

#### Chosen: Read old rows in place as relayed, widen the grammar in a release before anything writes it, and bring brief rules in as inferred rows once per brief

Old rows are never rewritten. A row of one of the five event kinds with no
Source reads as class **relayed**: an owner and a time as the coordinator
recorded them, with no decision behind them. Its owner and date are its
Owner, Relayed by and Set; its pointer is the entry its own `--standing`
write produced, found in this session's entries (a takeover carries them)
or, for a discipline lineage, in the earlier rotation's session. It binds
while the row exists, it isn't flagged, and it ends by `--end` as rows end
today: it has no koto decision to aim a reversal at. When the owner later
confirms it, the row gains a `decision` Source in place and from then on is
reversed only through koto.

The grammar ships in two releases, readers first. The reader release accepts
the `rule` kind and the Source column, leaves an empty Source out of the
normal form so an old row is written back byte for byte, adds the read view
below, and makes `run_address` stop a takeover before the fence when the
schema refuses the record, instead of reading the refusal as "no record". A
later writer release writes `rule` rows and Sources. It writes the
`decision` form only when koto's decision commands and its supersede hop are
both present, checked at each write; with an older koto, an owner's word is written as today's event row and reads
relayed, so nothing needs rework when koto arrives.

Brief rules come in once per brief digest. At a start whose brief has no Run
`briefs` row for its digest, the reconcile gate names a gap, and the
coordinator writes one `rule` row per rule its brief states that no Standing
row already holds: the brief's sentence in What, Owner blank, Source
`inferred brief <label> sha256:<digest>`, and the `briefs` row beside them.
A sentence that matches a row already held, superseded rows included, is
not written again; one matching a superseded row is named in the start
report as a reversed rule the brief still carries, so prose the owner took
back can't come in again as a fresh inferred rule.
Each reads inferred and is flagged for confirmation. A brief line that reads
like a pause or a go-ahead still comes in as a `rule` row, never as that
kind, so the pause read never grants or withholds on a coordinator's reading
of prose. A person the brief names stays inside the quoted What, never in
Owner. Running the intake again on the same digest writes nothing, and the
brief file is never edited.

#### Alternatives Considered

- **Import every old row into koto at the first start.** Convert each row
  with `koto decisions import` and add the citation. Rejected because it
  rewrites every row of every old lineage at once, which breaks an older
  plugin across a takeover; it gains only the handed provenance the row
  already has; it makes the successor the deciding session of rulings it
  never made, which would hand it standing over them by accident; and it
  can't land until koto's import ships.
- **Import a row only when it has to be reversed or confirmed.** Rejected
  for the same reasons one row at a time, and because confirmation through
  the owner's own surface already produces a real decision, so an import
  beside it records the same ruling twice.
- **Annotate old rows in place with a stored class and pointer.** Rejected
  because a stored class and pointer are a second set of provenance fields,
  and the rewrite breaks an older plugin with nothing new said by anyone.
- **Leave brief rules in prose until the compiled brief exists.** Rejected
  because a reviewer has to see every rule the lineage runs under, and
  process rules exist only in the brief today.

### Decision 4: Whether a continuing successor may reverse a decision made below its predecessor

A coordinator is replaced every few hours, and the workers it dispatched
often outlive it and report to its successor. koto builds each decision's
chain from links frozen when the worker was dispatched, so a worker's chain
names the predecessor, never the successor. Read literally, the successor
stands above nothing its predecessor dispatched. koto's decision record
assumes exactly that, leaves the question open for this work, and records a
recommendation for yes.

What constrains the answer is where standing may come from. The continues
relation is written by the successor itself and grants no authority, by the
rule of the work that built succession. The one record tying predecessor to
successor that the successor doesn't simply assert is koto's supersede
fence: `koto init <successor> --continues <predecessor> --supersede` appends
a koto-written `session_superseded` event to the predecessor's own log,
under the predecessor's own write lock, with exactly one winner, and from
then on koto refuses every attempt to drive the predecessor.

Key assumptions:
- koto's decision record ships in its designed shape: create-only keys per
  decision, chain snapshots taken at record time, standing computed at read.
- Whoever can fence a session can already cancel or alter it, locally or
  through the bucket credential. If koto ever grants bucket writes per
  prefix, this answer needs revisiting.

#### Chosen: Yes; the run's newest member stands where its predecessor stood, read from the fence and never higher

A successor that continues a predecessor's run may reverse a decision made
below that predecessor, and a decision the predecessor itself made, with
exactly the standing the predecessor had. koto reads that standing from the
supersede fence, never from the continues relation. The conditions koto has
to meet in its chain walk:

1. A fenced predecessor records no decision. Today the fence refuses only
   log appends, and the planned decision writer creates keys without one, so
   the writer has to check for the fence under the same lock. This holds
   whatever the answer here.
2. The fence is readable at listing cost, through a small write-once marker
   koto writes beside the predecessor the way it marks a migrated session.
3. The chain walk follows the marker forward the way it already follows a
   migration marker, checking each successor's session id against it. Every
   member of the run occupies the fenced session's position. Upward reads
   continue from the predecessor's frozen links, never the successor's own,
   so a successor gains nothing above or beside the position.
4. A hop koto can't confirm (no marker, a session id that doesn't match)
   refuses the reversal, and the coordinator escalates as it does today.
5. Every reversal that got standing through a hop records the hop in its
   standing path, naming the fence's actor and time, so a reader can list
   every reversal a given fence enabled.
6. koto's rule that only a person reverses a person's decision is unchanged.
   A successor alone can't reverse the owner; the owner, entering through the
   successor, can reverse what they told a predecessor.

The last point is what makes the answer necessary for this design and not
only convenient. An owner ruling recorded by a root coordinator has no
session above it. Without the hop, once that coordinator is replaced the
owner has nowhere to enter a reversal from: the fenced session refuses
writes and the successor isn't on the ruling's chain. Standing rules would
become irreversible at the first handoff. Until koto meets these conditions
the answer in force is no, a reversal below the predecessor is refused and
escalated, and the shirabe phase that writes cited rows waits for them.

#### Alternatives Considered

- **No; the person above reverses** (koto's current assumption). Rejected
  because once the manager and the director above a long-lived worker have
  both been replaced, only the owner can overrule it; the run's routine
  reversals of its own earlier calls would be recorded as refused; and an
  owner ruling recorded at the root could never be reversed after the first
  handoff.
- **Re-link live workers to the successor at takeover.** Rejected because
  the worker re-links only after following the fence, so the fence still
  grants the standing, now routed through every worker's compliance; a
  stopped worker never re-links; decisions recorded before the re-link keep
  their old snapshot; and the predecessor's own decisions are never covered.
- **Yes, but with standing `asserted` only.** Rejected because koto never
  lets an asserted reversal stop a live worker or clear a verified one, so
  after a director's replacement only the owner could stop a running worker,
  and it would need a new route in koto's standing rule besides.
- **Yes, but never for a decision a person made.** Rejected as a separate
  rule: koto already keeps a person's decision for a person to reverse, and a
  further exclusion would stop the owner reversing, through the current
  coordinator, what they told a predecessor.

## Decision Outcome

The four choices make one path. A rule enters a coordinator's record as a
Standing row, and its Source says where it came from: a koto decision, a
line of a skill, a document, a pinned file, or the coordinator's own
reading. Nothing in the row says what class it is. `rule_class` works that
out each time the row is read, from the Source and, for a citation, from the
decider koto recorded, so the owner's word is a property of a decision koto
holds and not of anything the coordinator typed. Only a root coordinator can
enter the owner's word as a person decision; a manager cites its director's.

Whether a rule still stands is koto's answer too. A cited rule the owner
reverses reads superseded at the next read, wherever it was copied, with the
reversal's reason beside it, and binds nothing. The reversal is koto's own
`reverse`; the row adds no status of its own. Because coordinators are
replaced and the owner's ruling sits in an earlier member of the run, that
reversal depends on koto treating the run's newest member as standing where
its predecessor stood, which is the answer this design carries back to
koto's decision record: yes, read from the supersede fence and never
higher.

A lineage started before the change keeps every row as it is, read as
relayed with its owner, its time and the entry that recorded it. Its brief's
rules come in once as inferred rows that name the brief they came from and
ask to be confirmed. Every row of either age answers the four questions a
successor is asked (who, when, where the words are, whether it still stands)
through one read, `state-stored-set.sh --rules`, and the later work on
compiled briefs and handoff restatement reads that and nothing else.

## Solution Architecture

### Overview

The change is confined to the coordinate skill's record scripts, its
reference text and one opener fix. Standing gains the `rule` kind and the
Source column; one schema function classes a row and another says whether
it may grant; one new helper reads what
koto recorded about a cited decision; the writer gains a flag, an intake and
a read view; the pause read learns to ask koto about the few rows that cite
a decision; and the handover read lists rules and names one new gap. Nothing
writes outside `record/standing` except the Run `briefs` row and the
`record/host` path the crash set already defines, and nothing reads or
writes `record/decisions` or `record/reversals`.

### Components

- **`skills/coordinate/scripts/state-schema.jq`.** `standing_kinds` gains
  `rule`. The Standing columns gain `source`, validated against the five
  forms and added to Standing's text-checked columns, so the public-host
  checks (no private repository, home path or token-shaped string) run on
  it. Those checks find a private repository only in a link or an
  `owner/repo#n` reference, so the grammar also checks the bare
  `<owner/repo>` of a `skill` or `doc` Source, and the repository in a
  `decision` Source's session name, against the list of repositories that
  aren't public. That is why a workspace file a public host can't name is
  cited only through `pinned`. The normal form leaves out an empty `source`,
  so a row without one is written back byte for byte. A `decision` Source's
  session name must match koto's session-name grammar and may not start
  with `-`, and its id must be exactly 12 digits, so nothing a writer types
  there can reach `koto` as a flag or a path; every script passes the two as
  separate arguments, never through a built command string. A `skill` or
  `doc` Source must name a commit its repository's default branch contains,
  and the writer refuses one whose repository it can't read to check that
  (one forge read, through the same `gh` the record's scripts already use),
  so a citation that can grant always points at merged words. A `rule` row
  leaves Owner and Relayed by blank whatever its Source: who said it is the
  Source's to answer (koto's decider for a citation, the document for a
  `skill`, `doc` or `pinned` row, the writing coordinator for an `inferred`
  one), so the row holds no second copy of it. An event row keeps its Owner,
  which today's readers show; when it cites a decision, the writer refuses
  an Owner that differs from the decider koto recorded (the person's handle,
  or the deciding session's name). Standing holds at most 120 `rule` rows, of which at most 60
  may read inferred; the five event kinds don't count against either cap, so
  neither a long brief nor a full set of rules stops a pause or a go-ahead
  being written. A new
  function, `rule_class`, takes a row and, for a cited row, the facts the
  provenance helper read, and returns one class:

  | Source | Class |
  |---|---|
  | none (an event row) | relayed |
  | `decision`, person decider entered at a root coordinator | owner-said |
  | `decision`, a session decider on the writer's frozen koto chain, or a later member of that session's run | dispatcher-said |
  | any other `decision` (the writer's own run, a person entered in a bound run) | inferred |
  | `decision`, not readable | unreadable |
  | `skill` | skill-says |
  | `doc`, `pinned` | charter |
  | `inferred` | inferred |

  A second function, `rule_grants`, returns whether a row may grant: true
  for an owner-said or dispatcher-said citation in effect, a `skill` row and
  a `doc` row, false for everything else (inferred, `pinned`, unreadable,
  superseded). It branches on the Source as well as the class because
  `doc` and `pinned` share the charter class and only `doc` grants, so a
  reader asks this function rather than working it out from the class.

- **`skills/coordinate/scripts/standing-provenance.sh` (new).** For each
  row with a `decision` Source, it runs `koto decisions show <session> <id>`
  and reads the fields koto's decision body defines (`decider`, `time`,
  `subject`, `chain`, and for the winning reversal its `standing` path and
  `reason`), printing the facts `rule_class` and the read view need: the decider kind,
  handle, surface, link and entering session; the decision's time and
  subject; its status; whether the entering session was bound when the
  decision was entered; and, when it reads `reversed`, the winning
  reversal's session, id, time, decider and reason, with whether its
  standing came through a supersede hop and that fence's actor and time.
  The entering session counts as bound when the decision's chain snapshot,
  which koto froze when it recorded the decision, names a session that holds
  a coordinator record (`record/meta`) for a scope other than the entering
  session's own, or when the entering session has a `reports-to` Run row. A
  chain session of the same scope is an earlier member of the lineage and
  doesn't count. The row can only make a session count as bound; it never
  makes one a root and never widens what a writer may cite. The writer's own
  frozen chain, which the dispatcher-said test reads, comes from the
  koto-owned `koto/links/dispatched-by/` keys in the writer's session, read
  by the same helper, and each session on it is followed forward through
  koto's supersede marker to its run's later members; a hop koto can't
  confirm stops there, so a successor it can't confirm never reads
  dispatcher-said. It reads and never writes, and it fails closed: any
  error, a status of `unreadable`, a body it can't parse, or a read that runs
  past its time limit gives `unreadable` for that row. Text it hands on from
  koto (a subject, a reason, a link) is cut to 200 characters, stripped of
  control characters, and marked as quoted data. A row with no citation
  costs it nothing.

- **`skills/coordinate/scripts/state-stored-set.sh`.** `--standing` takes
  `rule` and a new `--source <form>`. It refuses a `rule` row without a
  Source; a `decision` Source koto can't find, doesn't read `in-effect`, or
  that `rule_class` wouldn't read as owner-said or dispatcher-said for this
  writer (a manager citing a person decision entered in its own session, a
  citation outside its frozen koto chain, its own run's session decision,
  whose place is the Decisions section or an `inferred` row); and, once
  koto's decision commands are present, a new row naming a person in Owner
  with no `decision` Source. A `decision` row can still read inferred later,
  when it was carried from a writer whose standing differed; the writer just
  never creates one. A new mode confirms a row in place:

  ```
  state-stored-set.sh --session S --confirm s<n> --source "decision <session> <id>" --by <who>
  ```

  It adds the citation to a row that has none or reads `inferred`, keeping
  its id, kind, On, Until, What and Set, under the same refusals as a new
  citation, and writes an entry naming the old and new Source. That is how
  a relayed or inferred row becomes the owner's word once the owner confirms
  it. `--end` refuses a cited row whose decision is in effect
  and names `koto decisions reverse` instead; it accepts a cited row once its
  decision reads `reversed`, the reversal is older than this run member's
  start (the creation time in this session's koto header), and the brief
  this member started with no longer states the row's words (the intake's
  normalized match). So the successor after a reversal always sees the
  superseded row before it can go, and the row outlives the brief prose
  that repeated it: as long as a brief still carries the sentence, the row
  is there to keep the intake from taking it in again. `--by`
  stays required on every `--end`. A cited row that reads `unreadable` can
  be ended only with `--end <id> --by <who> --authorized-by "decision
  <session> <id>"`, citing a person decision that reads owner-said by the
  same test as any row (entered at a root, readable, in effect) and whose
  subject names the row. The writer writes an entry naming that decision
  and the session koto couldn't read. This is the way out when a corrupt or
  hostile peer makes a cited pause hold for good; it is exactly as strong as
  an owner ruling, no weaker, and the start report lists every row ended
  this way. The intake's duplicate test
  is mechanical: a brief sentence whose normalized text matches a row's What,
  superseded rows included, is not written again, and a new digest of the same brief label ends the
  inferred rows from the earlier digest that the new brief no longer states.
  An intake that would pass the 120-row cap writes nothing past it and
  leaves the `brief-unread` gap open, naming how many lines it couldn't
  take, so a person decides which rules to end rather than the coordinator
  dropping some quietly. Two new modes read:

  ```
  state-stored-set.sh --session S --rules [--id s<n>]...
  state-stored-set.sh --session S --rules --counts
  ```

  The first prints one JSON object per Standing row (the Key Interfaces
  below); the second prints how many rows of each class the record holds,
  with the inferred count, the unsourced rules a lineage accumulates, on its
  own line.

- **`skills/coordinate/scripts/pause-read.sh`.** For a pause or go-ahead
  row with a `decision` Source, it asks the provenance helper for the
  status: a reversed pause holds nothing and a reversed go-ahead lets nothing
  through; an unreadable pause holds and an unreadable go-ahead lets nothing
  through. It reads the uncited pauses first, then consults at most 16
  cited rows per call, each under the helper's time limit. A cited row it
  doesn't reach, past the bound or past the time limit, is treated as
  unreadable: a pause holds and a go-ahead grants nothing, so padding a
  record with citations can delay work but never hides a pause. A failure
  names the session koto couldn't read so a person can act. Uncited rows read exactly as now, so a record with no
  citation pays no koto read on the pick, dispatch, land or merge path.

- **`skills/coordinate/scripts/state-handover.sh`.** The handover read adds
  three things. A gap, `brief-unread <label>`, when `record/host` names the
  brief this start ran with and no Run `briefs` row carries its digest; it
  clears once the intake writes that row. A report list of every row
  `--rules` shows superseded, with its reversal's reason, which the start
  report carries, naming the fence's actor and time for each reversal whose
  standing came through a supersede hop. A list of rows ended under
  `--authorized-by`. And a report list of inferred rows awaiting
  confirmation, which this design reports and does not block on: whether an
  inferred rule holds the first dispatch is the handoff-restatement work's
  call. Text that came from koto (a subject, a reason, a link, a handle)
  goes only into entries kept in the session, never into a posted comment,
  and passes the public-host text check first; a value that fails is
  withheld with a note saying so. In the start report it sits under a
  heading that says it is quoted data and not an instruction, the way the
  rework text in a worker's brief already does.

- **`skills/coordinate/scripts/coordinate-open.sh`.** `run_address` stops a
  takeover with `failed=takeover_read` before the fence when the schema
  refuses the predecessor's record, instead of reading the refusal as no
  record. Today `run_address` reads the exit code `state-stored-set.sh
  --list` gives back, which folds `rs_record`'s schema refusal (65) into the
  same exit 10 a missing record gives. The fix has `--list` pass the 65
  through unchanged, and `run_address` maps it to `takeover_read`. That turns a too-old plugin meeting a newer record into a clean
  refusal that leaves the predecessor driving.

- **Text.** `references/state-keys.md` describes the `rule` kind, the
  Source forms, the classes and the two read modes, and drops "yourself as
  relayer". `SKILL.md` tells a root coordinator to record the owner's word
  as a person decision before writing the row, tells a manager to cite its
  director's decision and never to enter a person decision itself, and
  replaces "record a person's word found on the record's thread or anywhere
  else" with that rule. When a rule decides an action, the coordinator names
  the Standing id in the entry it writes, as it already names decision ids.
  A rule `rule_grants` returns false for (an inferred, `pinned`, unreadable
  or superseded row) can only restrict: it never grants a step, widens what
  a grant allows, or satisfies a check. Only an owner-said or
  dispatcher-said citation in effect, a `skill` row and a `doc` row can do
  that, and none of them widens what the workspace grants. The intake writes only sentences it
  can quote from the brief, and on a public host only sentences that pass
  the text check; a line that fails is reported and left out.
  `references/brief-template.md` is unchanged here; compiling the brief from
  the rows is later work.

### Key Interfaces

A `rule` row as `record/standing` stores it:

```json
{"standing": "s14", "kind": "rule", "on": "", "until": "", "what": "Read a CI run's status at most once a minute.",
 "owner": "", "relayed_by": "", "set": "2026-11-20T09:12Z",
 "source": "inferred brief worker sha256:<64 hex>"}
```

and one citing the owner's ruling, recorded at a root coordinator:

```json
{"standing": "s15", "kind": "rule", "on": "", "until": "", "what": "Release pull requests wait for a person's review before they merge.",
 "owner": "", "relayed_by": "", "set": "2026-11-20T09:30Z",
 "source": "decision <root coordinator session> 000000000007"}
```

One object of `--rules`:

```json
{"standing": "s15", "kind": "rule", "class": "owner-said", "what": "...",
 "owner": "<handle>", "said": "2026-11-20T09:29:41.120Z", "set": "2026-11-20T09:30Z",
 "pointer": {"decision": "<session> 000000000007", "surface": "terminal", "entered": "<session>", "link": null},
 "source": "decision <session> 000000000007",
 "status": "in-force", "reversal": null, "confirm": false, "grants": true}
```

`owner` is who said it: koto's decider for a cited row (the person's
handle, or the deciding session), the row's Owner for a relayed one, and
null for a `skill`, `doc`, `pinned` or `inferred` row, whose `pointer` and
`class` answer that. `grants` is `rule_grants`. `said` is the decision's time for a cited row and the row's Set otherwise.
`pointer` is the decision for a cited row, the entry that recorded the row
for a relayed one (`{"entry": "<session> record/entries/<n>"}`, with the
posted comment's URL when there is one, and the row itself when no entry is
found), the brief's label and digest for an inferred brief rule, and the
repository, path and commit (or the pinned label and digest) otherwise.
`status` is `in-force`, `superseded` (a cited decision reading reversed, with
`reversal` holding the reverser, time and reason), `unconfirmed` (an
inferred row) or `unreadable`. `confirm` is true for inferred rows. The
compiled brief and the handoff restatement read this object and nothing
else.

The koto calls, all from koto's decision record:

```
koto decisions record <root session> --kind judgment --outcome settled \
    --by person:<handle> --surface terminal|forge|relay [--link <https>] \
    --reason "<the rule's words>"
koto decisions show <session> <id>
koto decisions reverse <session> <id> --by person:<handle> --surface terminal --reason "<why>"
```

### Data Flow

1. **The owner rules at the root.** The owner tells the director, in its
   session, how something is to be done. The director records a person
   decision and writes a `rule` row citing it; `--rules` shows it
   owner-said.
2. **The ruling reaches a lane.** The director's message tells the manager
   the session and id. The manager writes its own `rule` row citing that
   decision, and its `--rules` shows owner-said too. A ruling the director
   makes itself is a session decision in the director's run, and the
   manager's row citing it reads dispatcher-said.
3. **Handoff.** The successor's takeover carries `record/standing` as it
   stands. Its first `--rules` reads every cited decision from koto, so a
   reversal recorded while nobody was driving is already visible.
4. **The owner reverses.** The owner, through the current director run
   member, runs `koto decisions reverse` on the original decision. koto
   accepts it through the supersede hop (Decision 4). Every row citing that
   decision, in the director's record and in every lane, reads superseded
   at its next read, with the reason, and binds nothing; a cited pause or
   go-ahead stops holding or granting at the pause read's next call. The
   next successor's start report lists the row as superseded before the row
   can be ended.
5. **An old lineage's first start under the change.** Its rows read
   relayed with their owners and times. The handover read names
   `brief-unread`, the coordinator brings its brief's rules in as inferred
   rows, writes the `briefs` row, and the gap clears.

### How a reviewer checks each outcome

Each outcome the milestone promises can be run by a reviewer who didn't
write the change, against a real record:

- **An old lineage keeps its rules.** Start a successor on a lineage created
  before the change. Compare `koto context get <predecessor> record/standing`
  with the successor's `--rules`: every row is there with a class, and every
  row that had an Owner and a Set shows the same values, class relayed. Each
  rule its brief stated is there as an inferred row naming the brief.
- **Three sources on request.** `--rules --id s<a> --id s<b> --id s<c>`
  gives a class, a date and a pointer for each. Following each pointer
  (`koto decisions show`, the entry, the file at its commit) reaches the
  words. A row with no source anywhere (a brief rule, or the coordinator's
  own reading) reads inferred with `confirm` true; an old event row with an
  owner and a time reads relayed with `confirm` false.
- **A reversed rule is never acted on.** Reverse one cited rule as the
  owner. The next successor's `--rules` shows it superseded with the
  reason, and its start report lists it. No entry written after the
  reversal's time names that Standing id as the reason for an action, and
  for a cited pause or go-ahead the pause read's output shows it holding or
  granting nothing.
- **Unsourced rules stop accreting.** `--rules --counts` on each member of
  a lineage, oldest to newest, gives the inferred count (the unsourced
  rules) and, beside it, the relayed count per succession, so the rate of
  rise can be read against whatever baseline the reviewer holds. A rule the
  owner reversed doesn't come back in as inferred, since the intake matches
  superseded rows.
- **One home, one reversal.** `koto context get <session> record/standing`
  shows the rule rows in Standing. `koto decisions show` on the reversed
  rule's decision shows it reversed by a koto `reverse`, and nothing in
  `record/reversals`, in a Standing row or anywhere else in the record
  carries a second status for it. The schema has no class or status column
  to search for.

## Implementation Approach

### Phase 1: The reader release

The schema accepts the `rule` kind and the Source column and leaves an empty
Source out of the normal form; `rule_class`, `rule_grants` and the
`--rules` and `--rules --counts` views land, with `decision` sources classed
unreadable until the provenance helper can read them; `run_address` refuses before the fence on a schema refusal; the
handover read lists rules. Nothing writes the new shape yet, so this release
can ship and spread before any record holds a `rule` row.

Deliverables:
- `state-schema.jq`, `state-stored-set.sh` (`--rules`, `--rules --counts`),
  `state-handover.sh` (lists only), `coordinate-open.sh` (`run_address`)
- tests: every existing Standing reader's tests pass on records with no
  Source; a record with a `rule` row reads through each of them unchanged;
  an old row is written back byte for byte after an unrelated write

### Phase 2: Rule rows and the brief intake

Depends on Phase 1 being released, so a successor on the older reader never
meets a `rule` row. `--standing rule` with the `skill`, `doc`, `pinned` and
`inferred` forms; the `brief-unread` gap and the intake that clears it; the
Run `briefs` row and the brief's path in `record/host`; the skill and
reference text, except the owner-said procedure.

Deliverables:
- `state-stored-set.sh` (`--standing rule`, `--source`, refusals),
  `state-handover.sh` (the gap), `SKILL.md`, `references/state-keys.md`
- tests: the intake is idempotent on one digest and writes only new
  sentences for a new digest; a brief line shaped like a pause comes in as
  a `rule` row; an inferred row reads `confirm` true; on a public host a
  `skill` or `doc` Source naming a repository that isn't public is refused;
  a `skill` or `doc` Source naming a commit off the default branch is
  refused; a `rule` row with an Owner is refused; a brief sentence matching
  a superseded row isn't taken in; the 121st `rule` row is refused while a
  pause can still be written

### Phase 3: Citations, owner-said and reversal

Waits on a koto release that ships the decision record's recording, listing
and reversal, and the supersede-hop conditions in Decision 4. Without the
hop, an owner ruling recorded at the root couldn't be reversed after the
first takeover, so this phase doesn't land on a koto that lacks it. The
`decision` form, `standing-provenance.sh`, the owner-said and
dispatcher-said classes, the writer's refusals, `--confirm`, `--end`'s
refusal of cited rows, the pause read's status check, and the owner-said
procedure in `SKILL.md`.

Deliverables:
- `standing-provenance.sh`, `state-stored-set.sh`, `pause-read.sh`,
  `state-schema.jq` (`rule_class` for citations), `SKILL.md`
- tests, under a scratch koto store: a reversed owner ruling reads
  superseded in the director's and a manager's record; a reversed go-ahead
  grants nothing; an unreadable citation fails closed and its row ends only
  with `--authorized-by` citing an owner-said decision; a cited pause past
  the pause read's bound holds; a Source whose session name starts with `-`
  is refused; a manager citing a person decision it entered
  itself is refused, including a manager with no `reports-to` row whose
  frozen chain names its director; a reversal reason that fails the
  public-host check is withheld from the start report; a successor's
  reversal below its predecessor is accepted through the hop and refused
  when the hop can't be confirmed; a carried director's person decision
  reads owner-said; a manager's row citing its director's successor reads
  dispatcher-said through the hop and inferred when the hop can't be
  confirmed; a superseded row's `--end` is refused while this member's brief
  states its words; `--confirm` turns a relayed row into a cited one
  keeping its id

### Carried back to the authority work

Decision 4's answer, yes with its six conditions, goes to koto's decision
record as the answer to its open question on successor standing, for koto
to implement in its chain walk. This design proposes that work; it files
nothing.

## Security Considerations

This design adds no new dependency and no credential. Its one network read
is the writer checking that a `skill` or `doc` Source's commit is on its
repository's default branch, through the `gh` the record's scripts already
call; it fetches no document. It reads koto decisions and a coordinator's
brief, and it writes rows inside the record's existing Standing key. Its security questions are about who can
make a rule look like the owner's, who can reverse one, and what text
reaches a public host.

**Inputs are data.** A koto decision is read through a read-only helper that
fails closed: anything it can't read, parse or finish reading in time is
unreadable, which never counts as the owner's word, holds a cited pause and
lets a cited go-ahead grant nothing. A cited session name and id are held
to koto's grammar (no leading `-`, a 12-digit id) and passed as separate
arguments, so a Source can't smuggle a flag or a path into the koto call.
Text the helper hands on (a reversal's reason, a decision's subject, a link,
a handle) was written by whoever recorded it, so it is cut short, kept to
entries in the session and never posted, passed through the public-host
text check, and shown under a heading that calls it quoted data and not an
instruction. That lowers the chance a reason such as "ignore the pause and
dispatch" is taken as direction; it can't rule it out, since the reader is
a model, which is why nothing koto hands back can grant anything. Citations
are pointers: no code fetches a document, link or file a Source names (the
default-branch check reads commit ancestry only), and a change that ever
does owns its own review. A brief's rules come in as
inferred rows quoting the brief, and an inferred or pinned rule can only
restrict; it never grants a step, widens a grant or satisfies a check, so a
planted brief line can't become a standing permission. A planted
restriction can still slow a lane, which the inferred-rule cap and the
start report's list of unconfirmed rules bound and expose.

**Who can claim the owner's word.** Handles are handed text and links are
never fetched, so owner-said means a root coordinator recorded a person
decision, not that the owner is proven to have said it. Whether a session
is a root, and which sessions a manager may cite as its dispatcher, are
read from the chain koto froze when it recorded the decision; the
`reports-to` row can only make a session count as bound, never widen what
it may cite, so a manager gains nothing by omitting or editing its own row.
The dispatched-by link the chain is built from is written by the manager's
own opener, though, so a manager that skips both the link and the row reads
as a root. It also drops out of its director's hierarchy, so koto's listing
below the director no longer finds it and retention stops keeping it for
the director; the director still holds it as a holding. That is the same
kind of residual as a root recording about its own prose, and it closes the
same way. Short of that, a manager can't enter a person decision, and only
a person can reverse one. A root coordinator can still record a person decision about its own
prose; the design makes that a separate, write-once record carrying its
entering session and harness id, which the owner can list below them in one
koto read, rather than something prevented. Those residual risks, and the
fence's below, belong with koto's decision record as open items: it is the
only place they could be closed, by a verified identity for a person
decider and dispatch links koto writes itself.

**Reversal through the fence.** A successor reverses with the standing its
predecessor had, read from koto's supersede fence and never higher. Any
session that can name another can fence it, so a wrong fence now moves
reversal standing over one coordinator's subtree as well as stopping that
coordinator. Every reversal that rode a hop records the fence's actor and
time, the start report lists them, a hop koto can't confirm refuses, and the
owner and the sessions above the position keep the last word. The answer
assumes the fence and the decision store share one trust boundary, which
holds while whoever can fence a session can already cancel it; if koto ever
grants bucket writes per prefix, this answer is revisited.

**Availability.** A decision made unreadable by a corrupt or hostile peer
would otherwise hold a cited pause for good. The pause read reads uncited
pauses first and consults a bounded number of cited rows under a time
limit; a row it doesn't reach counts as unreadable, so padding can delay
work but never hides a pause, and a failure names the session at fault.
Such a row can be ended only by citing an owner-said decision naming it,
the same bar as any owner ruling and no lower, and the next start report
lists the ending. Standing holds at most 120 `rule` rows and at most 60
inferred ones, the event kinds don't count against either, and the
intake's duplicate test is mechanical, so rules can't crowd out a pause.

**Data exposure.** The Source column holds repository names, paths, session
names and labels, and all of it is text-checked on a public host. The
generic check finds a private repository only in links and `owner/repo#n`
references, so the grammar checks the bare repository of a `skill` or `doc`
Source, and the repository in a cited session's name, against the list of
repositories that aren't public. A workspace file a public host can't name
is cited only by label and digest, with its location kept in
`record/host`, and the intake writes a brief sentence only if it passes the
same check. A pinned or brief digest records what was read; comparing it
with the file's current contents is the compiled-brief work's, so this
design doesn't present it as an integrity check, and that is why a pinned
rule can only restrict. A `skill` or `doc` rule can grant only from a
commit its repository's default branch contains, so it points at merged
words and never at a branch a coordinator pushed itself. Person
handles already sit in Owner today; the ones koto hands back go only into
entries kept in the session.

## Consequences

### Positive

- A successor answers who said a rule, when, where the words are and
  whether it still stands, for every rule it runs under, from one read.
- A reversed owner ruling stops binding in every record that cites it at
  once, because its status lives in one place koto keeps.
- A coordinator can't label its own prose the owner's word: there is no
  field to set, and a manager can't enter a person decision at all.
- Old lineages keep working on any plugin from the reader release on, with
  no conversion pass and nothing rewritten.
- The Run section's `briefs` digests get their first writer and reader, and
  brief rules stop riding forward unseen.

### Negative

- A cited row needs koto to show its class and status, and an unreadable
  decision reads unreadable, not owner-said, until koto can read it again.
- Two endings coexist while relayed rows remain: `--end` for rows with no
  decision and koto's `reverse` for cited ones.
- A superseded row stays in Standing, counting against the rule cap, for as
  long as a successor's brief still repeats its words.
- A root coordinator can still claim the owner said something; the design
  makes the claim attributable, not impossible.
- The citation phase waits on koto shipping both its decision record and
  the supersede hop, so owner-said rows can't exist until then.
- A plugin older than the reader release that takes over a record holding a
  `rule` row fails after the fence; old plugins can't be changed.
- Each brief's first start costs an intake pass, and a pre-change lineage
  starts with every brief rule flagged inferred.

### Mitigations

- The pause read asks koto only for cited pause and go-ahead rows, so the
  common path pays nothing; the provenance helper fails closed, so an
  unreadable citation never lifts a pause.
- `--end` refuses a cited row in effect and names the reversal command, so
  the two endings can't be mixed up; relayed rows shrink as the owner
  confirms them.
- Every person decision carries its entering session and harness id, and a
  director lists every person decision below it in one koto listing.
- Until the citation phase ships, an owner's word is written as today's
  event row and reads relayed, with owner and time kept, so nothing is lost
  in the wait.
- Shipping the reader release well before the writer release closes most of
  the old-plugin window, and the `run_address` fix makes every plugin from
  the reader release on refuse cleanly before the fence.
- The intake runs once per brief digest, and confirming an inferred rule is
  one citation; the restatement work decides how hard inferred rules block.
