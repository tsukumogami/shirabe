---
schema: prd/v1
status: Draft
problem: |
  The coordinate skill talks about two coordinator roles, a manager over one
  lane and a director over managers, only in prose. Nothing at a run's start,
  in its record, in its reports or in the brief it writes for a successor says
  which role a session runs. Dispatchers re-describe the role in free text in
  every brief, successors drift between several names for the session at the
  top, and the skill addresses duties only one role owes to "the coordinator".
goals: |
  Whoever starts a coordinator names its role, manager or director, and that
  name shows in the session's first report, in its record and in the brief it
  writes for its successor, whose first report names the same role. A reader
  of the skill finds "coordinator" meaning a session of either role and every
  duty addressed to the role that owes it. A session that owes what a director
  owes is never described, by itself or a successor, under any other name. A
  role carries what the session is expected to do and never what it's allowed
  to do.
---

# PRD: Coordinator Named Roles

## Status

Draft

## Problem Statement

A coordinator can run one lane of work (a roadmap's features, or one rotation
of a discipline), dispatching workers and landing what they push. It can also
run over other coordinators, dispatching them and reviewing what they finish.
The dispatcher-review requirements in shirabe#1449
(`docs/prds/PRD-coordinator-dispatcher-review.md`) call these two roles a
manager (one lane) and a director (over managers), with "coordinator" meaning
either, and leave giving the roles a place in the run to later work. This is
that work.

Today the roles live in words only, and that shows in four places:

- **Nobody can tell which role a session runs.** `/shirabe:coordinate` takes a
  roadmap path or a discipline and its host, a cap and a few bounds. Nothing
  at the start names a role, nothing in the record holds one, and the run's
  first report can't name what it was never told. A reader of a report or a
  record has to infer the role from what the session happens to be holding.
- **Every brief re-describes the role.** A coordinator that dispatches another
  coordinator, a successor or a lane, writes the role into the brief's Goal in
  its own words, because the brief has no place for it. Each brief describes it
  a little differently, and the successor's own reports pick up whichever
  wording it was handed.
- **The top session has no stable name.** A lineage of successors at the top
  of an effort ends up calling itself by several names over its life, one per
  brief that described it. A reader can't tell from the record whether two
  names are one role or two.
- **Duties are addressed to the wrong reader.** The skill's Glossary defines a
  coordinator as "the session running this skill", with no roles under it.
  The skill is written from a manager's side: it tells "the coordinator" to
  pick roadmap features, brief workers, land worker pull requests and give
  milestone verdicts, and it scatters the few director duties (deciding what a
  dispatched coordinator passes up, handing a successor its own grant) across
  passages that also say "the coordinator". The word "director" appears
  nowhere in the skill. The word "manager" appears about ten times, every time
  meaning the workspace manager (niwa), which collides with the role's name.

The workspace owner's rule for the split is that what a session is expected to
do and what it is allowed to do are different things: expectations are fixed
in the skill and its roles, and allowances are configured per workspace and
host. So naming a role must change what a session owes and how it's described,
and must never change what it may do.

## Goals

A person or a coordinator starting a session on the coordinate skill names its
role, manager or director, and sees that name in the session's first report,
in its record, and in the brief it later writes for its successor. The
successor's first report names the same role, and no brief describes the role
from scratch in prose.

A reader of the skill finds "coordinator" defined as a session of either role,
with the manager and the director defined under it, and every duty addressed
to the role that owes it. A session that owes what a director owes reports as
a director and under no other name, including a successor started from a
lineage whose older briefs called the top session by several names.

Roles carry expectations only. Grants, merge authority and who settles a step
stay with the workspace's authority configuration, and a role changes none of
them.

## User Stories

- As a person starting a coordinator over one roadmap, I want to say it runs as
  a manager and see "manager" in its first report and in its record, so that I
  and anyone reading later know which duties it owes without inferring them.
- As a person starting a coordinator over two lanes, I want to say it runs as a
  director, so that it reads the director's duties from the skill and its
  managers and its reports call it a director from the start.
- As a director dispatching a manager, I want the brief to carry the manager's
  role on one line the skill renders, so that I don't write the role into the
  brief's Goal in my own words and the manager doesn't pick up my wording.
- As a coordinator handing over to a successor, I want the successor's brief and
  first report to name my recorded role, so that the role survives the
  handover without anyone restating it.
- As a person continuing a lineage started before roles existed, whose briefs
  called the top session by three different names, I want to start its
  successor as a director and see it report as a director and nothing else, so
  that the old names stop at that handover.
- As a reader of the skill, I want "coordinator" to mean a session of either
  role and every duty to name the role that owes it, so that I can tell from
  one passage whether it applies to me.

## Requirements

Terms. **Role** in this document means only the session's own role, manager or
director. A **manager** runs one lane: a roadmap's features or one discipline
rotation, through the workers it dispatches. A **director** runs over managers:
it dispatches them and reviews what they finish. A **coordinator** is a session
of either role. **Bound**, **root**, **the reviewer** and **the land step** are
used as shirabe#1449 defines them. A **lineage** is a run and the successors
that continue it. A **successor brief** is the brief a coordinator writes to
dispatch a coordinator that continues its own run; a **lane brief** is the
brief a director writes to dispatch a manager.

### Functional

- **R1. The role is named at start.** Every start of `/shirabe:coordinate`
  that opens a new run (a roadmap or a discipline, root or dispatched) takes the
  role as a setting whose only values are `manager` and `director`. Any other
  value, such as `lead` or `top`, is refused before a session exists, as the
  skill refuses a malformed cap or host today, and nothing opens. A role
  stated in words in the starter's decisions ("run as a director") is passed as
  that setting, as the skill does for a host stated in words, and is not asked
  for again.
- **R2. An unnamed role is asked for, never defaulted.** When a new run's start
  names no role and there's no recorded role to continue from (R4), the start
  asks for it once, as it asks for a missing host, and nothing is dispatched
  before it's answered. No default applies, and no role is inferred from the
  scope, the cap, the holdings, the dispatcher, or any brief or report text.
- **R3. The role is in the record.** The run's record holds its role as one
  stored value inside the record's existing container, with one writer, read
  through the record's one reader. The handover read prints it, and a record
  with no role is a gap that holds the handover gate until the role is named,
  as a record with no `reports-to` row does today.
- **R4. Every continuation keeps the role.** A resume, a carry, a takeover, an
  import and a discipline rotation that carries its predecessor's state all
  continue with the recorded role, with no step by hand, and need no role
  setting at start. A continuation whose record holds no role (a lineage
  started before this change) takes it from the start setting under R1, or asks
  under R2.
- **R5. The role doesn't change across a succession.** A start that continues a
  recorded role and names a different one is refused, naming the recorded role
  and the one asked for, and the run keeps going as it was. Naming the
  recorded role again is accepted. Naming a role for a record that holds none
  is not a change. A session that should run under the other role is started as
  a new lineage.
- **R6. Reports name the role.** The run's first report, at reconcile, names the
  role in its opening lines, beside the record's session name and host
  repository, and every later report names it wherever it names the record.
  A report names the role with the word `manager` or `director` and no other
  word for it.
- **R7. A coordinator's brief carries the role on one rendered line.** A
  successor brief names the role the record holds, and a lane brief names
  `manager`, each on one line the brief renderer writes from the role it's
  given, never from the dispatcher's prose. The brief's other sections (Goal,
  decisions, checkpoints, acceptance criteria) don't describe the role's duties:
  the coordinator reads those from the skill's expectation list for its role
  (R10). `references/brief-template.md` says so where it describes the Goal.
  A worker brief (one that doesn't start a coordinator) carries no role line,
  and its rendered text is unchanged.
- **R8. The successor reports the role its brief names.** A successor's first
  report names the role on its brief's role line, which is the predecessor's
  recorded role, and its record holds that role from the start.
- **R9. Old names stop at the first handover.** In a lineage started before this
  change, the successor's role comes only from R1, R2 or R4. Nothing reads a
  role out of an earlier brief's prose, an earlier report, a decision entry, a
  session name or the dispatch topic. From its first report on, the successor
  calls its role `director` or `manager` and uses none of the names the
  lineage's earlier briefs used for it.
- **R10. Each role has an expectation list in the skill.** `SKILL.md` carries
  one list of what a manager is expected to do and one of what a director is
  expected to do, fixed in the skill, and the session reads the list for its
  recorded role. At the least, the manager's list says it runs one lane,
  dispatches and briefs workers, reviews its workers' pull requests at its land
  step, and sends the pull requests it authors (its verdict and reopen edits
  included) to its reviewer. The director's list says it dispatches and briefs
  managers, is the reviewer of each manager it dispatched, reads a manager's
  finished work itself and sends its own reading up (shirabe#1449's R8). The
  two lists may share items both roles owe, such as briefing a successor.
  Neither list names a grant, a merge authority or who settles a step.
- **R11. The Glossary defines the roles.** `SKILL.md`'s Glossary entry for
  Coordinator defines it as a session running this skill in either role, and
  two entries follow it, one starting `**Manager** --` and one starting
  `**Director** --`, matching the Terms above. The Glossary says that
  "workspace manager" means the tool that dispatches and lists sessions (niwa)
  and is never the role.
- **R12. Every duty names the role that owes it.** Every occurrence of the word
  `coordinator` (singular or plural, any case) in `skills/coordinate/SKILL.md`,
  `skills/coordinate/references/*.md` and
  `skills/coordinate/koto-templates/coordinate.md` is classified as one of:
  **either role** (a duty both roles owe, or a statement true of both), **one
  role** (a duty only a manager or only a director owes), or **not a duty** (a
  definition, a scope name such as "discipline coordinator", or a dispatch
  relationship such as "root coordinator" or "the coordinator that dispatched
  you"). Each one-role occurrence is rewritten to address `manager` or
  `director` (or `a manager`, `the director`, and so on). The classification
  after the change, one row per occurrence with file, line, quoted phrase and
  class, goes in the implementation pull request's description, and it has no
  row in the one-role class.
- **R13. One name per role.** Positional names for a role that aren't
  `manager` or `director` ("lane coordinator" and any name like "top",
  "lead", "head" or "parent coordinator" for a director) are replaced by the
  role's name. Words for a coordinator's scope ("roadmap coordinator",
  "discipline coordinator") and for its dispatch relationship ("root", "bound",
  "the reviewer", "the coordinator that dispatched you", "predecessor",
  "successor") stay, because they describe a different thing than the role.
  "Successor" keeps one meaning in the skill: a coordinator that continues a
  run. "manager" without "workspace" before it means only the role.
- **R14. A role is an expectation, never an allowance.** Naming a role grants
  nothing and withholds nothing: the posture read, `niwa authority check`, the
  grant a worker or successor is dispatched holding, and whoever settles a
  step all come out the same for either role. A director with no merge grant
  still may not merge, and a manager holding one still merges only after its
  reviewer's review. No text this change adds says a role holds, needs or
  implies a grant, a merge authority, a close or release authority, or the
  right to settle a step.
- **R15. Where this meets the dispatcher-review requirements.** The role and the
  dispatch relationship are separate: a manager or a director can be root
  (its reviewer is a person) or bound (its reviewer is the coordinator that
  dispatched it), and "the reviewer" keeps shirabe#1449's one Glossary
  definition. The two meet in three places: the director's expectation list
  carries shirabe#1449's duty to read a manager's finished work and send its own
  reading; a manager a director dispatched has that director as its reviewer;
  and the sentences shirabe#1449 adds or pins (the reviewer entry, `never
  whether the review happens`, `once its review is done`, `your own reading`,
  `without the reviewer's review`) keep their words, rewritten only where a
  one-role duty is readdressed under R12.
- **R16. "Role" means one thing in the record.** The record's `reports-to` value
  is described today as `<role>` or `<role> at <address>`, where "role" names
  who the coordinator reports up to. After the change, the skill and
  `references/state-keys.md` use "role" only for the session's own role, and
  describe the `reports-to` value in other words, so a reader of the record
  can't take one for the other. The stored `reports-to` values already in
  records stay valid.

### Non-functional

- **R17. No second container.** The role is a value inside the record's existing
  container, written by that container's one writer for its section, within
  its size budget and carried by its existing continuation paths
  (PRD-coordinator-session-record's one-writer and size-budget requirements;
  PRD-coordinate-successor-continues's carried-facts requirement). The change
  adds no store, no file, no GitHub surface and no takeover or carry path of its
  own.
- **R18. Settings stay constrained.** The role setting follows the start's
  existing rules (PRD-coordinate-record): a constrained value checked before a
  session exists, and free text after `--` never changes it except as R1 says
  for a role stated in words.
- **R19. Pinned text and checks.** The sentence the brief golden files and
  tests pin, "The workspace manager schedules your keep-alive at dispatch.",
  is unchanged. `scripts/check-skill.sh coordinate`,
  `scripts/check-template-compat.sh --template
  skills/coordinate/koto-templates/coordinate.md` and
  `scripts/ablation/check-public-content.sh` pass. Where the change alters the
  template's structure, the compatibility table records it as that script
  requires. Tests that pin a sentence the change rewords are updated with it,
  never deleted.
- **R20. Public content and vocabulary.** Nothing in the change names a private
  repository, a private path, a session name or internal figures. Commits and
  the pull request carry no AI attribution, and added prose uses none of the
  words `skills/writing-style/rules.yaml` bans.

## Acceptance Criteria

Starting and recording (Evidence: a reviewer starts one session as a manager
over a roadmap and one as a director over two managers, and sees each name its
role in its first report and in its record):

- [ ] A start of a roadmap run with the role setting `manager` opens, its first
  report's opening lines contain `manager` beside the record's session name and
  host repository, and reading the record's role value through the record's
  reader prints `manager`.
- [ ] A start with the role setting `director` opens; its first report's
  opening lines contain `director`, the record's role value prints `director`,
  and the lane briefs it renders for two managers each carry a role line naming
  `manager`.
- [ ] Neither first report names the role with any word other than `manager` or
  `director` (a reviewer reads the opening lines; `lead`, `top`, `head` and
  `lane coordinator` are absent).
- [ ] A start with the role setting `lead` is refused before a session exists:
  no koto session for the scope is created, and the refusal names the two
  allowed values.
- [ ] A new run's start with no role setting and no role in its decisions asks
  for the role once and dispatches nothing before the answer; a start whose
  decisions say "run as a director" opens as a director without asking.
- [ ] The handover read of a record with no role lists a gap for it, and the
  handover gate doesn't pass until the role is set; with the role set, the
  same read prints it and lists no role gap.
- [ ] A resume, a carry and a takeover of a run recorded as `director`, each
  started with no role setting, report `director` in their first report and
  their records read `director`.

Successor brief and first report (Evidence: each session hands off to a
successor, whose brief and first report name the same role, with no prose
paragraph describing the role from scratch):

- [ ] The brief renderer, given role `director` for a successor brief, writes
  exactly one line naming the role, and that line contains `director`; given
  `manager`, the line contains `manager`. A renderer test asserts both, and
  asserts that a worker brief contains no role line and renders byte-for-byte
  as it did before the change.
- [ ] A successor brief rendered from a run recorded as `manager` names
  `manager`, not a role taken from the dispatcher's input text: a renderer test
  that passes Goal text containing "you are the director" still renders the
  role line from the given role.
- [ ] `references/brief-template.md`'s description of the Goal says the Goal
  doesn't describe the role's duties and the coordinator reads them from the
  skill's expectation list for its role.
- [ ] In each successor's brief, no paragraph outside the role line restates the
  role's duties: none of the expectation-list items of R10 appears in the
  brief's Goal, decisions or checkpoints (a reviewer checks the brief against
  the two lists).
- [ ] Each successor's first report names the same role as its brief's role
  line, and its record's role value matches.
- [ ] A start that continues a run recorded as `manager` with the role setting
  `director` is refused, the refusal names both roles, and the recorded run is
  unchanged (same role, still driving); the same start with `manager` is
  accepted.

The Glossary and duties (Evidence: the Glossary defines "coordinator" as a
session of either role with the two roles under it, and no duty that belongs to
only one role is addressed to "the coordinator"):

- [ ] `SKILL.md`'s Glossary entry for Coordinator says a session of either role,
  and `grep -c '^- \*\*Manager\*\* --' skills/coordinate/SKILL.md` and
  `grep -c '^- \*\*Director\*\* --' skills/coordinate/SKILL.md` each print 1,
  directly after the Coordinator entry.
- [ ] The Glossary says "workspace manager" means the tool and is never the
  role, and every occurrence of `manager` in the three file sets that means the
  tool has `workspace` immediately before it.
- [ ] The implementation pull request's description has a table with one row per
  `grep -niwE 'coordinators?'` hit in the three file sets after the change, each
  with file, line, phrase and class, the row count equals the grep's line
  count, and no row is in the one-role class.
- [ ] A reviewer spot-checks at least ten rows the table classes "either role"
  or "not a duty", including every sentence that dispatches a worker, lands a
  worker pull request, gives a milestone verdict, dispatches a coordinator or
  hands a successor a grant, and finds each correctly classed.
- [ ] `grep -niE 'lane coordinator|(top|lead|head|parent) coordinator'` over the
  three file sets finds nothing.
- [ ] `SKILL.md` has one manager expectation list and one director expectation
  list, each containing every item R10 names for that role, and neither list
  contains `grant`, `merge authority`, `may merge` or `settle`.
- [ ] `references/state-keys.md` and `SKILL.md` don't describe the `reports-to`
  value with the word `role`, and an existing `reports-to` row (`the human`)
  still passes the record's schema check.

A lineage from before the change (Evidence: from a lineage created before this
change whose briefs called the top session by three different names, a
successor reports as a director and nothing else):

- [ ] Given a record with no role whose earlier briefs and entries call the top
  session by three different names (for example "lead coordinator", "top
  coordinator" and "head of effort"), a successor started with the role setting
  `director` reports `director` in its first report, and its record's role value
  prints `director`.
- [ ] That successor's first report and its record's keys written after the
  start contain none of the three earlier names (`grep -F` for each finds
  nothing).
- [ ] The same successor started with no role setting asks for the role and
  dispatches nothing before the answer; it doesn't infer `director` from the
  earlier names, the holdings or the dispatch topic.

Allowances and the dispatcher-review requirements:

- [ ] For the same workspace and session, the posture read and `niwa authority
  check` print the same result whether the run is recorded as `manager` or
  `director`, and the grant a successor brief requests is the same for either.
- [ ] The diff's added lines don't say that a role holds, needs or implies a
  grant, a merge, close or release authority, or the right to settle a step (a
  reviewer reads each added sentence naming `manager` or `director`).
- [ ] `SKILL.md` still has exactly one `**The reviewer** --` Glossary entry,
  still contains `never whether the review happens`, `once its review is done`
  and `your own reading`, and the director's expectation list says the director
  reads a manager's finished work and sends its own reading.

Checks and content:

- [ ] `scripts/check-skill.sh coordinate`, `scripts/check-template-compat.sh
  --template skills/coordinate/koto-templates/coordinate.md` and
  `scripts/ablation/check-public-content.sh` exit 0.
- [ ] `grep -rF 'The workspace manager schedules your keep-alive at dispatch.'`
  finds the sentence in the same files before and after the change.
- [ ] The diff's added lines contain none of `robust`, `leverage`,
  `comprehensive`, `holistic`, `facilitate`, `tiered`, no emoji, no
  `Co-Authored-By`, and no path or name from a private repository.

## Out of Scope

- How the role is passed at start and how it's stored in the record: the
  setting's name and shape, the record key, the handover gap's name, and how a
  successor or lane brief receives its role. The design settles these.
- Grants, merge authority, close and release authority, and who settles a step.
  The workspace's authority configuration owns them, and another effort owns
  changes to it.
- The record's container itself: the session as the record, one writer per key,
  the size budget and successor continuation belong to the record's own work.
  This change adds a value and reads inside it.
- Enforcing a role's duties with a state, gate or evidence field. The skill
  tells each role what it owes; mechanical enforcement is separate work.
- A third role, or a director over directors. The two roles are the whole set
  this change names.
- Rewriting the coordinate evals. They say "coordinator" for either role, which
  stays correct under R11; new eval cases for roles are later work.
- Worker briefs, which start no coordinator and get no role line.

## Known Limitations

- The role is stated and recorded, not enforced. A session recorded as a manager
  that dispatches a coordinator isn't stopped by this change; the skill's text
  and its reviewer are what keep it in its role.
- Refusing a role change means a lane that grows into an effort with its own
  managers starts its director as a new lineage, and the old lineage's record
  stays readable but isn't carried into the new one.
- The classification table in R12 describes the files at the time of the
  implementation; line numbers drift, and the phrases are what a reviewer
  checks.

## Decisions and Trade-offs

The workspace owner left three points open. This document settles one and
names two as questions for the design.

- **How the role is passed at start and stored in the record. Left to the
  design.** This document requires the behaviour (a constrained setting, asked
  for when unstated, one value in the existing record, carried by every
  continuation, rendered on one brief line) and leaves the setting's name, the
  record key, the gap's name and the brief field to the design. The reason is
  that the choices are mechanism: they depend on how the start's variables,
  the record's sections and the brief renderer's inputs are shaped, which the
  design reads closely and this document doesn't. Any shape that meets R1
  through R9 and R17 satisfies these requirements.
- **The wording of the manager and director expectation lists. Left to the
  design.** This document fixes what each list must contain at the least (R10)
  and what it must not contain (any allowance, R14). The exact wording, the
  lists' place in `SKILL.md` and how they sit beside the passages the R12 sweep
  rewrites are the design's, because they depend on the sweep's results and on
  the sentences the skill's rule coverage test pins, which only an
  occurrence-by-occurrence pass can see.
- **Whether a role can change across a succession. Settled: no.** A successor
  keeps the recorded role, and a start naming another role is refused (R5).
  Alternative: allow a change named at start and record it as an entry naming
  the old and new role. Rejected for now because the role is what the
  successor's own reviewer and the managers under a director rely on: a silent
  or casual change shifts what the session owes in the middle of a lineage, and
  that's the drift this change exists to stop. Refusing is also the narrower
  choice: allowing a recorded change later adds behaviour without breaking any
  run, while allowing it now and taking it back later would strand runs whose
  role already changed. A lineage with no recorded role isn't a change, so the
  lineages started before this change aren't blocked. The dispatcher reviewing
  this document is where this is confirmed or reversed.
- **No default role.** Decided: an unnamed role is asked for (R2). Alternative:
  default to `manager`, the common case. Rejected because a default would let a
  successor of a director's lineage, started without the setting, report as a
  manager, which is the failure the fourth outcome describes, and because a
  role inferred by default is a role nobody named.
- **No inference from prose.** Decided: nothing reads a role out of brief text,
  reports, entries or names (R9). Alternative: infer `director` from a record
  that holds coordinator dispatches. Rejected because the inference would need
  to read the very prose whose names this change retires, and because a record
  can hold a lane dispatch for reasons other than a director's (a successor
  dispatch is one).
- **Sweep by classification.** Decided: classify every occurrence of
  "coordinator" and put the table in the implementation pull request, as
  shirabe#1449 did for "a person". Alternative: rewrite the passages a reader
  notices. Rejected because "the coordinator" appears about 230 times across the
  skill's files and a reader-noticed pass is how a one-role duty survives; the
  table makes the check something a reviewer can repeat.
- **Keep "workspace manager".** Decided: the tool keeps its name, always with
  "workspace" before it, and the Glossary says it's never the role. Alternative:
  rename the tool in the skill (for example to "niwa"). Rejected because the
  phrase is pinned in rendered briefs and their golden tests, and the qualifier
  is enough to tell the two apart.
