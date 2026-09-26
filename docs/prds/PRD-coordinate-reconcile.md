---
schema: prd/v1
status: Accepted
problem: |
  A coordinator that starts, restarts or takes a rotation inherits a record
  of dated claims about what it dispatched, deferred, attempted and
  reversed. The coordinate skill tells it in prose to re-check every claim
  against GitHub and the host before acting, but nothing makes that happen,
  nothing shows that it did, and the checks that matter most (a merge in
  flight, a board that only looks green, a worker missing from one listing)
  are the ones an agent gets subtly wrong.
goals: |
  At every start, restart and rotation handoff, the coordinator's workflow
  holds it in its reconcile state until a script has re-checked every claim
  in the record against its live source and written a report of what changed
  and what the coordinator holds into the workflow's context. The pick state
  reads that report. No value the agent supplies can let the workflow leave
  reconcile, and reconcile itself changes nothing on GitHub or the host.
absorbed:
  - docs/briefs/BRIEF-coordinate-reconcile.md
---

# PRD: coordinate-reconcile

## Status

Accepted

Absorbed [BRIEF-coordinate-reconcile](docs/briefs/BRIEF-coordinate-reconcile.md); carried in Absorbed Brief.

## Absorbed Brief

The feature frames one gap: a coordinator that starts, restarts or takes a
rotation inherits a record of claims dated when they were written, and the
`coordinate` skill's instruction to re-check them before acting is prose,
so nothing makes the re-check happen or shows that it did. A stale row, or
the coordinator's own last report, can be acted on as fact; the exact
checks (a merge against its verified head, a board that only looks green, a
worker missing from one listing) are the ones an agent approximates; and
the raw reads spend the coordinator's context.

The problem it named is this document's Problem Statement. The outcome it
asked for is that, before picking any work, the coordinator reads one
report built from live reads by a script, saying what changed and what it
holds, and the workflow won't let it pick without that report; the person
above gets measured claims, and a successor rotation gets its predecessor's
reasoning as prose it never mistakes for fact. Those are this document's
Goals.

Five journeys grounded it and survive as User Stories: a restart that finds
a holding merged while it was down; a restart that can't find a worker with
no pull request and says "not found on this read"; a restart that settles
an attempted merge against the verified head; a new rotation that starts
from a handoff; and the person above reading the first report. Its scope
boundary is carried as the Requirements and Out of Scope: the reconcile
state's reads, re-checks, report and gate, reuse of the record reader, the
host re-check of holdings with no pull request, the scoping-ahead mark, and
the handoff variant; and, excluded, liveness, the double-held check,
externalised load, acting on the report, the record's container and
rendering, the dispatch path, the per-turn re-check before acting, and any
change to the workflow engine or the workspace manager.

## Problem Statement

A coordinator is a long-running session that drives a roadmap or a standing
discipline by dispatching other sessions and landing what they push. It keeps
a record on GitHub of four things GitHub can't recompute: its holdings (the
units it dispatched, with the worker's dispatch topic, branch, pull request
and the head it verified), deferrals, side effects in flight (a merge it
attempted and never saw confirmed), and reversals. Every row is true as of
the record's `Written:` time.

When a coordinator starts again (after a crash, after losing its context,
restored on another host, or as a new rotation of a discipline) those rows
are snapshots of the past. A pull request may have merged or closed. A branch
may have moved past the verified head. A worker with no pull request yet may
have lost its instance, and with it work that was never pushed. A merge that
was attempted may or may not have landed, and if the branch moved first, what
landed isn't what was verified.

The `coordinate` skill already describes the fix: its first loop step,
reconcile, re-checks each row against GitHub and the host and reports what
changed. Today that step is prose in `skills/coordinate/SKILL.md` and
`references/loop.md`, and the loop is becoming a koto workflow template in
which reconcile is a state. Carried out by the agent alone, the step fails in
three ways. An agent that skipped it leaves the same trace as one that ran
it, so a stale row (or the coordinator's own last report, which reads like a
summary of the present) gets acted on as fact. The checks that decide the
hard cases have exact answers that an agent approximates: a merge confirmed
against the branch's current head instead of the verified one, a board that
shows green with jobs that ran nothing, a worker called gone after one
listing missed it. And the raw reads fill the coordinator's context, which is
the scarcest thing it has.

## Goals

- A coordinator never acts on an inherited claim that wasn't re-checked in
  this session: the workflow can't reach pick until a script-written
  reconcile report exists.
- The report carries what the coordinator needs to decide, compactly: what
  changed per holding, what exists nowhere but the host, which side effects
  are settled, which deferrals are undisposed, what's next, what waits on a
  person, and whether each holding is scoping ahead or executing.
- The hard re-checks are exact: merges are confirmed against the verified
  head, boards are judged by a property, and a worker missing from one
  listing is never reported gone.
- A rotation handoff is the same step plus one input, the predecessor's
  reasoning, which reaches the successor as prose and is never treated as a
  re-checked fact.

## User Stories

- **Restart finds a holding that finished.** As a roadmap coordinator
  restarted after a crash, I want the report to tell me that a holding's pull
  request merged after my record was written, so that I drop it from my
  holdings instead of dispatching a fix for work that already landed.
- **Restart finds a worker with no pull request and no instance.** As a
  coordinator restarting with a holding that had no pull request, I want the
  report to say the worker was "not found on this read", list the holding
  among those that exist nowhere else, and say what it couldn't inventory, so
  that I read again before deciding and report any loss honestly.
- **Restart settles a merge it attempted.** As a coordinator whose record
  holds a merge attempted just before it died, I want the report to confirm
  the merge only when what landed on the default branch is what I verified,
  and to say "not confirmed" when the branch moved past the verified head, so
  that I never report as merged a change nobody verified.
- **Restart doesn't trust a green board.** As a coordinator restarting with a
  parked holding, I want the board at its verified head judged by whether
  every job actually ran, so that a board that shows green while testing
  nothing isn't carried into my report as ready to land.
- **A new rotation starts from a handoff.** As a coordinator taking the next
  rotation of a discipline, I want my predecessor's tables re-checked like any
  record and its reasoning handed to me as prose marked as its view, and
  every deferral it left shown as undisposed, so that I start from facts
  plus judgment without mistaking one for the other.
- **The person above reads the first report.** As the person, or the
  coordinator above, who dispatched this coordinator, I want its first report
  after a restart to lead with what changed and what it holds, each claim
  graded as measured, so that I don't have to ask whether it checked before
  acting.
- **Pick counts the cap.** As the pick state of the coordinator's workflow, I
  want the report to say per holding whether it is scoping ahead or
  executing, so that I can count holdings against the session cap without
  re-reading anything.

## Requirements

### Reading the record

**R1. The record is read through the record feature's reader.** Reconcile
reads the record with the reader the coordination-record feature ships, and
does not parse the record body itself. At roadmap scope the reader finds the
record issue by exact title over listed open issues; at discipline scope it
reads the body of the rotation's pull request on the record branch. The
reader returns the record's `Written:` time and its four sections: holdings
(including the verified-head column), deferrals, side effects in flight and
reversals.

**R2. Every row is a claim dated at the record's `Written:` time.** No row is
reported as current state. A row the reader returns as unparseable is listed
under "not verified" with the reader's reason and the row's raw text in a
fence, and is never dropped.

**R3. A record that can't be read produces no report.** When the reader finds
no record, finds more than one candidate, finds a candidate without the
record's declaration line, or can't read the body, the reconcile script
writes no report, writes the reason under a separate key the agent reads to
escalate, and the workflow stays in reconcile.

### Re-checking holdings with a pull request

**R4. Pull request state is read live.** For each holding with a pull
request: its state (open, merged, closed), draft flag, head sha and merge
state are read from GitHub at reconcile time and appear in the holding's
line. A draft flag that differs from what the row implies (a parked holding
whose pull request is back in draft) is reported as a change.

**R5. The board is judged as a property at the verified head.** For each
open holding pull request, the CI board is judged at the row's verified head
when it records one, and at the pull request's live head when it doesn't
(the holding isn't parked yet). When both exist and differ, the report says
the head moved and judges the board at both. The judgment is the property
the record feature's board check implements: every job on the board has a
runner name and a non-zero number of steps that ran, and no required run is
missing. Reconcile reuses that check, doesn't restate how the board is read,
and reports each judgment as "holds" or "fails", naming the first failing job
or missing run.

**R6. The branch is read on the remote.** The holding's branch is read with
`git ls-remote` against its repository. The report says "branch gone" when
the ref is absent and "branch tip differs" (with both shas) when its tip
isn't the pull request's head, for merged and open pull requests alike.

**R7. Changes are reported with both values.** Where a live read differs
from the row (the pull request merged or closed, the head moved past the
verified head, the branch vanished, a pull request appeared), the report
names the holding, the recorded value, the live value and the record's
`Written:` time. A holding whose pull request merged is reported as
finished, not held.

### Re-checking holdings with no pull request yet

**R8. A pull request that appeared since is found.** For a holding recorded
with no pull request, reconcile lists pull requests on the holding's branch
in its repository, in any state. Exactly one is reported as a change ("pull
request appeared") and is then re-checked under R4 to R6; more than one is
reported as ambiguous with every candidate listed.

**R9. The worker is looked for on the host by dispatch topic.** Reconcile
reads the workspace manager's listing and matches the holding's dispatch
topic against each instance's and session's name, never matching on a
session id, instance path or job id. It then checks that the matched
instance's directory exists.

**R10. A miss is re-read before it's reported.** When no listing entry
matches the topic, reconcile reads the listing once more, no sooner than 30
seconds after the first read. When the second read matches, the worker is
reported found. When it doesn't, the report says "not found on this read"
and uses none of the words "gone", "dead" or "lost" about the worker. When
the workspace manager can't be run or read on this host (a coordinator
restored on a host that doesn't hold the workspace), the host reads for
every holding land in "not verified" with that reason.

**R11. Unique material is inventoried where the instance exists.** For a
worker whose instance directory exists and is readable, reconcile lists
what it holds that exists nowhere else, per clone: commits on no remote ref,
uncommitted changes, and files whose content is not on the default branch.
An empty inventory is reported as "nothing unique found". When the instance
isn't found, isn't on this host, or can't be read, the report says the
inventory couldn't be taken and why, and lists the read under "not verified".

### Re-checking a holding bound to a request leg

**R12. A bound leg is one more source of truth.** For a holding that
carries a request id and leg name, reconcile also reads that leg from the
workflow engine's request store: its disposition and, when resolved, the
result it carries, in whatever shape that leg's entry point records (a
result map with an outcome where the entry point writes one, the engine's own
terminal status and final state where it doesn't, and a refusal with its
reason). The leg is re-checked like any other source and never
stands in for the record or for the GitHub and host reads; where it and
GitHub disagree, the report shows both. A holding with no request id makes
no request-store read. A leg that can't be read from this host (the store is
local to one host) lands in "not verified".

### Re-checking side effects and deferrals

**R13. A merge in flight is settled against its verified head.** For each
merge in side effects in flight, reconcile compares the default branch with
the verified head recorded on that row, file by file over the pull request's
changed files, and never against the branch's current head. It reports
"confirmed" only when every changed file's content on the default branch
equals its content at the verified head (a file deleted at the verified head
must be absent on the default branch). When the pull request merged but a
file differs, or the pull request isn't merged, it reports "not confirmed"
with the reason.

**R14. Other side effects use fixed reads.** A close is settled by reading
the target issue's or pull request's state: "confirmed" when it reads
closed, "not confirmed" otherwise. A teardown is settled by reading the
workspace manager's listing and the instance directory under R10's rule:
"confirmed" when both reads find nothing, "not confirmed" when either finds
the target. A side effect of any other kind is reported "not re-checked".
Reconcile never runs the row's free-text "How to confirm" as a command.

**R15. Deferrals are reported by disposal.** Each deferral is reported as
disposed or undisposed using the disposal check the record feature's
deferral gate uses: disposed when the issue it names exists, when it is
marked closed with a reason, or when it is carried forward with a reason
from the current rotation; undisposed otherwise. Reconcile reports; it
doesn't dispose.

### The report

**R16. The report has a fixed structure.** The report is structured data
with a fixed schema, rendered to text for the agent from that data. Its
sections, in this order: a header (scope, the record's `Written:` time, the
time of this reconcile); "Changed since then"; "Holding", one entry per
holding with its state as just read, its phase (R17) and its next line;
"Waiting on a person"; "Exists nowhere else"; "Side effects", each
confirmed, not confirmed or not re-checked; "Undisposed deferrals";
"Predecessor's reasoning" at discipline scope (R24, R25); and "Not verified",
naming every read that failed, timed out or was skipped, with the reason.
An empty section reads "None."

**R17. Each holding is marked scoping ahead or executing.** The report
marks every holding as scoping ahead or executing from the record's
entry-point and mode columns: a holding dispatched to the scoping entry
point, or with a mode that stops after scoping, is scoping ahead; every
other holding is executing. A holding marked scoping ahead whose live pull
request changes any path outside `docs/` is flagged as contradicting its
mark.

**R18. "Next" and "waiting on a person" are derived by fixed rules.** A
holding's next line is derived from its reads alone: merged means "drop from
holdings"; closed unmerged means "decide: re-dispatch or drop"; open with a
failing board means "worker fixes CI"; open with a holding board and the
live head equal to the verified head means "ready to land"; open otherwise
means "wait on worker"; no pull request with the worker found means "wait on
worker"; no pull request with the worker not found means "read again, then
decide". "Waiting on a person" lists every holding whose next line is
"ready to land" or "decide: re-dispatch or drop" and every merge "not
confirmed". Neither is stored anywhere.

**R19. Every claim is graded.** Each claim carries one grade: "measured"
for a value read live in this reconcile (a pull request's state, a branch's
tip); "verified by reading" for a conclusion drawn by comparing live reads
(a merge confirmed file by file, a board judged by the property); "inferred"
for anything derived from the record's text without a live read (a phase
mark, a derived next line).

**R20. The script writes the report into the workflow's context.** The
report is written into the coordinator session's workflow context by the
reconcile script, under a fixed key, and the pick state reads it from there.
The agent never writes that key.

**R21. The report is compact.** The report holds conclusions, never raw
read output: no command output, JSON payload or log line appears in it
except a quoted record row under R2. Its rendered text is at most 40 lines
plus 6 lines per holding, side effect and deferral.

### The gate

**R22. The workflow can't leave reconcile without the report.** A gate on
the reconcile state, which can't be overridden, holds the workflow there
until a report exists that the reconcile script wrote during this visit to
the state. A report left over from an earlier visit, or one written by the
agent, doesn't satisfy it.

**R23. No agent-supplied value satisfies the gate.** No evidence field,
context value or flag the agent can supply lets the workflow transition from
reconcile to pick.

### Rotation handoff

**R24. A discipline start reads the predecessor's handoff.** At discipline
scope, a start reads the discipline's handoff file,
`docs/disciplines/<name>.md`, on the host repository's default branch: the
one file per discipline that each rotation overwrites, dated by its heading.
Its tables go through the same re-checks as a record (R4 to R15), labelled
as written by the previous rotation at that date. When no handoff file
exists, the report says so and the start proceeds as a first rotation.

**R25. The predecessor's reasoning is carried as prose.** The handoff's
reasoning section reaches the coordinator's context as prose, under a key
separate from the report's, marked as the predecessor's view. The report's
"Predecessor's reasoning" section points at it and never restates it as a
re-checked claim. No gate reads that key.

**R26. A missing reasoning section is recorded, never supplied.** When the
handoff has no reasoning section, an empty one, or one stating that the
reasoning wasn't recorded, the report says no reasoning was received. The
successor never writes the predecessor's reasoning.

### Constraints

**R27. Reconcile reads and never acts.** Reconcile makes no write to
GitHub, the host or the record: no `gh` write, no push, no workspace-manager
command that changes state, no edit of the record body.

**R28. No rule works around a filed defect.** Reconcile's behavior is
specified against the fixed behavior of the known defects listed under Known
Limitations; none of its rules exists only to work around one of them.

**R29. Workers are named by dispatch topic.** In the report and in its
context keys, reconcile names a worker only by its dispatch topic, never by
a session id, instance path or job id.

**R30. Reads are bounded.** Every read reconcile makes has a deadline. A
read that fails or times out lands in the "not verified" list rather than
failing the whole reconcile, unless it is the record read (R3).

**R31. The skill carries no permission rule of its own.** Nothing reconcile
adds reads the workspace's permission posture or encodes which finishing
steps a session may take; "ready to land" says what the reads show, not who
may land it.

## Acceptance Criteria

Each criterion runs against the reconcile script with stubbed `gh`, `git`,
workspace-manager and request-store commands whose calls are logged, and
against the reconcile state of the workflow template, unless it says
otherwise.

**Record reading**

- [ ] At roadmap scope, with a stubbed open issue titled exactly as the
  record and another whose title only contains it, the report is built from
  the exact-title issue; at discipline scope, it is built from the record
  branch's pull request body.
- [ ] With a record containing one row the reader can't parse, the report's
  "Not verified" section contains that row's text in a fence and the reason,
  and every other row is reported.
- [ ] With no record, two exact-title candidates, or one candidate without
  the declaration line, no report key is written, the reason key names which
  case it was, and the workflow stays in reconcile.

**Holdings with a pull request**

- [ ] A holding recorded open whose stubbed pull request reads merged is in
  "Changed since then" with "open", "merged" and the `Written:` time, and its
  next line is "drop from holdings".
- [ ] A parked holding whose stubbed pull request reads draft is reported as
  a change.
- [ ] With a stubbed board at the verified head where one job has no runner
  name, the board judgment reads "fails" and names that job; with every job
  real and no required run missing, it reads "holds".
- [ ] A holding whose live head differs from its verified head is reported
  as "head moved" with both shas, and the board is judged at both.
- [ ] An open holding whose stubbed `ls-remote` returns nothing reads
  "branch gone"; one whose tip differs from the pull request head reads
  "branch tip differs" with both shas.

**Holdings with no pull request**

- [ ] A holding recorded with no pull request whose branch now has exactly
  one stubbed pull request reads "pull request appeared" and carries that
  pull request's state; with two, it reads ambiguous and lists both.
- [ ] With a listing that omits the topic on both reads and no instance
  directory, the report says "not found on this read", lists the holding
  under "Exists nowhere else", says the inventory couldn't be taken, and
  contains none of "gone", "dead" or "lost" about it; the stub log shows two
  listing reads at least 30 seconds apart (by the stub's injected clock).
- [ ] With a listing that omits the topic on the first read and includes it
  on the second, the worker is reported found.
- [ ] With the stubbed workspace-manager command absent or failing, every
  holding's host reads are under "Not verified" with that reason, and the
  GitHub re-checks are still reported.
- [ ] With an instance directory holding a commit on no remote ref, an
  uncommitted change, and a file whose content isn't on the default branch,
  the inventory lists all three; with none of them, it reads "nothing unique
  found".

**Request legs**

- [ ] A holding with a request id whose stubbed leg resolved with an outcome
  while its pull request is still open shows both; a holding with no request
  id makes no request-store call; an unreadable leg is under "Not verified".

**Side effects and deferrals**

- [ ] A merge in flight whose changed files on the default branch match
  their content at the verified head reads "confirmed".
- [ ] A merge in flight where the branch moved past the verified head before
  merging, so a changed file differs, reads "not confirmed" although the pull
  request reads merged.
- [ ] A close whose target reads closed is "confirmed"; one whose target
  reads open is "not confirmed". A teardown whose target is absent from both
  listing reads and the directory is "confirmed"; one whose instance directory
  still exists is "not confirmed".
- [ ] A side effect of an unknown kind whose "How to confirm" holds a shell
  command reads "not re-checked", and no stub log shows that command.
- [ ] A deferral naming an existing issue, one closed with a reason, and one
  carried forward with a reason read disposed; one with none of these reads
  undisposed.

**The report**

- [ ] Every fixture's report has the sections of R16 in that order, each
  empty section reading "None.".
- [ ] Every holding is marked scoping ahead or executing per R17; a holding
  marked scoping ahead whose pull request changes a path outside `docs/` is
  flagged.
- [ ] For each of R18's seven cases a fixture produces the stated next line,
  and "Waiting on a person" lists exactly the holdings and merges R18 names.
- [ ] Every claim in every fixture's report carries exactly one of the three
  grades of R19, matching the rule for its kind.
- [ ] No fixture's report contains a line of raw stub output, and a fixture
  with 10 holdings renders within R21's line bound.
- [ ] No fixture's report or context key contains a stubbed session id,
  instance path or job id; each worker appears by its dispatch topic.

**The gate**

- [ ] In the workflow template, the reconcile state's only transition to
  pick is conditioned on the report gate, the gate is declared
  non-overridable, and the state declares no override transition.
- [ ] The workflow stays in reconcile when the report key is absent, when it
  holds a report from an earlier visit, and when the agent set the key
  itself; it moves to pick once the reconcile script writes the report.
- [ ] Submitting every evidence field the reconcile state accepts, with any
  value, doesn't move the workflow to pick while the gate fails.

**Rotation handoff**

- [ ] At discipline scope with a handoff carrying a reasoning section, the
  reasoning is in its own context key, the report's "Predecessor's reasoning"
  section points at it, and a search of the template shows no gate reading
  that key.
- [ ] With a handoff whose reasoning section is missing, empty, or says it
  wasn't recorded, the report says no reasoning was received.
- [ ] With no handoff file, the report says so and the start proceeds.
- [ ] The handoff's table rows are reported labelled with the handoff's
  date.

**Constraints**

- [ ] Across every fixture, the stubbed `gh`, `git`, workspace-manager and
  request-store logs contain only read subcommands, checked against a list of
  permitted read verbs.
- [ ] With each stubbed read in turn made to time out, that read lands under
  "Not verified" with its reason and the rest of the report is written;
  with the record read timing out, no report is written.
- [ ] The reconcile script and the template's reconcile state contain no
  reference to the workspace's permission settings or hooks.
- [ ] The skill's Known Limitations names shirabe#395, #396, #398, #401 and
  koto#250, each with what it costs today, and says where liveness, the
  double-held check and externalised load would attach; no rule in the
  reconcile state or script cites one of those issues as its reason.

**Evals and hygiene**

- [ ] An eval restarts a coordinator whose record holds a holding that has
  since merged; the grader passes it when the coordinator's first report up
  has a "Changed since then" section before its "Holding" section that names
  that holding with both states.
- [ ] An eval starts a rotation from a handoff with a reasoning section; the
  grader passes it when the coordinator's first report attributes that
  reasoning to the previous rotation and doesn't list it under re-checked
  claims.
- [ ] `git grep -n 'wip/'` over the files this feature adds is empty, and a
  grep of those files for `private/`, for the names of the organization's
  private repositories as listed by `gh repo list <org> --visibility private`,
  for UUID-shaped session ids, and for instance names of the workspace
  manager's `<config>+<topic>-<8 hex>` shape finds nothing.

## Out of Scope

- **Liveness.** Whether a worker is still running and making progress is a
  follow-on. Reconcile asks whether its session and instance exist and what
  they hold.
- **The double-held check.** Whether another coordinator already holds the
  effort is optional, never blocks, and is a follow-on.
- **Externalised load.** What a coordinator's merges cost efforts it can't
  see is a follow-on.
- **Acting on the report.** Merging, closing, tearing down, re-dispatching
  and rewriting the record belong to later loop steps.
- **The record's container and rendering.** The coordination-record feature
  owns them; reconcile consumes its reader.
- **Reading the scope.** Reading the roadmap's features or a discipline's
  open issues and red checks is the pick state's input, not reconcile's.
- **The per-turn re-check before acting.** The lighter re-check of a holding
  the coordinator is about to act on belongs to the verify step.
- **The dispatch path**, including binding a worker's result to a request
  leg.
- **Changes to koto or niwa.**

## Decisions and Trade-offs

**Scoping ahead or executing comes from the record.** The record's
entry-point and mode columns say what the coordinator dispatched, which
GitHub can't recompute; a scoping pull request and an early implementation
pull request can look alike on GitHub. The live pull request is used only to
flag a contradiction. Alternatives were inferring the mark from the pull
request's files, or requiring both to agree. This closes the brief's one
deferred question.

**The report is data first, text second.** The pick state has to count
holdings by phase without re-reading anything, so the report is structured
data with a fixed schema and the agent reads a rendering of it. A prose-only
report would leave pick parsing prose.

**One re-read, 30 seconds apart.** A listing can miss a live worker for a
short window after dispatch or after the workspace manager's session mapping
fails to load. One re-read after 30 seconds catches the common window without
turning reconcile into a poll; the report still says "not found on this
read" rather than concluding anything when both reads miss.

**An unknown side effect is reported, not confirmed.** Running a row's
free-text "How to confirm" would let the record's contents run commands, and
the record is written by an agent. Only kinds with a fixed read are settled.

**A partial report still passes the gate; no report doesn't.** A failed read
of one holding shouldn't stop a coordinator from acting on the rest, so it
lands in "not verified" and pick sees it. A record that can't be read leaves
nothing to reconcile against, so the workflow waits there.

**Reading the scope stays with pick.** The prose loop reads the roadmap's
features during reconcile; the template splits that read out because feature
state is pick's input and isn't a claim in the record.

**The gate is stated as a property.** "A report the reconcile script wrote
during this visit" is the requirement; how the gate knows the script wrote it
is the design's, aligned with the record feature's verified-head gate, which
has the same problem.

## Known Limitations

- **Pull request ownership by login and branch (shirabe#395).** R8's search
  for a pull request that appeared since can match another run's pull
  request on the same branch name under the same login. Today the cost is a
  possible false "appeared" change on a holding whose branch name another run
  reused; unique branch names per topic keep it rare.
- **The merge-order block is empty (shirabe#396).** Reconcile doesn't read
  merge order, so a worker's coordinated merge order isn't in the report.
  Today the pick and land steps get it from the worker.
- **Scoping pull request bodies fail validation (shirabe#398).** A holding
  scoping ahead may show a red body check on its scoping pull request that
  says nothing about the work. Today the report shows that board red.
- **`--koto-leg` on /deliver and /work-on (shirabe#401).** Until those
  entry points accept a leg, a holding dispatched to them carries no request
  id, so R12 never fires for it and reconcile re-checks it through GitHub
  and the host alone. Today that means a worker's own terminal result isn't
  one of reconcile's sources for those holdings.
- **No wake when a leg resolves (koto#250).** Nothing wakes a coordinator
  when a worker finishes, so reconcile runs only when the coordinator's
  session ticks. Today a change is found at the next start or restart.
- **Where the follow-ons attach.** Liveness would add a line to each worker
  R9 finds, saying whether it is making progress. The double-held check would
  run beside R1, reading who else has written to the record's container
  recently, and would report without blocking. Externalised load would attach
  to the land step's merges, not to reconcile.
