---
schema: prd/v1
status: In Progress
problem: |
  A coordinator started with `/coordinate` can open a second record after a restart,
  dispatch past a predecessor's deferral, or land work on a head nobody verified, because
  the skill is prose: each check it asks for can be skipped or satisfied by saying it was
  done, a green CI board that ran nothing looks like one that ran everything, and the
  record is hand-written markdown that nothing finds, renders or rewrites.
goals: |
  A coordinator runs its loop as a koto workflow. The record is found or opened exactly
  once and always has the same four sections; nothing is dispatched while a predecessor's
  deferral is open; nothing lands without a head the workflow itself read from the remote
  and verified against a CI board that really ran. The two judgment calls in the loop are
  recorded next to an automatic answer that doesn't act. The coordinator keeps its worker
  cap full, and every rule of the prose skill still holds.
upstream: docs/briefs/BRIEF-coordinate-record.md
---

# PRD: The coordination record and the coordinator's workflow

## Status

In Progress

## Problem Statement

A coordinator is the longest-running session in a workspace: it hands units of work to
other sessions, checks what they push, and lands the work or puts it in front of a person.
`/coordinate` tells it how, as a prose skill, and four of the checks it asks for are the
ones that fail when a coordinator is restarted, rushed, or new to an effort.

The record must exist once, but finding it is a listing the coordinator runs by hand, and a
coordinator restarted a minute after opening its record, or one that searched instead of
listing, opens a second. A predecessor's deferrals must be disposed of before the first
dispatch, and nothing stops a coordinator that skips them. A head must be verified before
anything lands, but a coordinator can write any sha into its record and nothing can tell
whether it read the board at that sha. And a board that is green can have tested nothing:
a job whose steps were all skipped still reads as success.

Each check is a claim the coordinator makes about its own work. The record it writes is
also rebuilt from a template in a reference file every time, so its shape drifts between
writes and a successor has to parse whatever the last writer produced. Finally, the two
judgment calls in the loop, which unit to pick next and what a worker's report means, leave
no trace anyone could compare against a mechanical answer.

## Definitions

The prose skill's glossary (coordinator, the human, worker, local agent, brief, holding,
deferral, reconcile, rotation, surface, teardown, unique material) holds unchanged. This
PRD adds:

- **Scope.** What one coordinator drives: a roadmap (**roadmap scope**) or one rotation of
  a named discipline such as `ci-health` (**discipline scope**).
- **Host repository.** Where the record lives: the roadmap's repository at roadmap scope,
  the repository the human named at discipline scope.
- **Record.** The coordinator's durable record on GitHub (not koto's session log, which
  this PRD calls the **session**). Its **declaration line** is
  `> This is a **coordinator record** for <scope>.`, the line the prose skill already uses.
- **Unit.** One piece of work pick can hand to a worker: a roadmap feature, an issue, an
  open question, a contested choice, or out-of-scope work the dispatcher assigned.
- **Active worker.** A dispatched worker whose unit isn't merged or abandoned and that isn't
  parked. **Parked worker:** one whose pull request is verified and ready and waits only on
  a merge.
- **Phase.** A holding's stage: `scoping-ahead` (the worker is scoping a unit whose
  execution waits on another feature landing) or `executing`.
- **Board.** Every GitHub Actions workflow run for the pull request's head sha, each at its
  latest attempt, and every job in those attempts; plus every check GitHub marks required
  for the pull request. An earlier attempt that failed and was re-run doesn't count against
  the head; it's listed in the verify report.
- **Run.** One coordinator session, from its start to its end. A restart is a new run; its
  start time is recorded when the session opens.
- **Verified head.** A full 40-character sha the workflow read as the pull request's head on
  the remote and found a board that really ran at (R10).
- **Posture.** The workspace's declared permissions: the permission lists in the workspace
  root's and the instance's `.claude/settings.json`, and the PreToolUse hooks under their
  `.claude/hooks/`.
- **Shadow decider.** An automatic answer to a judgment question that the workflow records
  beside the coordinator's answer and never acts on.

## Goals

- The four checks (the record exists once, deferrals are disposed of first, a verified head
  exists before land, the board really ran) hold on every run, and none can be satisfied by
  a value the coordinator supplies.
- A restarted coordinator continues on the record it already has.
- The record reads the same on every write: four sections, fixed columns, rewritten whole.
- The pick and report-classification calls are recorded beside a shadow answer.
- The coordinator keeps its worker cap full and drives each worker to landed work.
- Every rule of the prose skill still holds; the skill file shrinks to a contract, and each
  step's guidance arrives when the coordinator reaches that step.

## User Stories

- As a maintainer with an Active roadmap, I want to start a coordinator with the roadmap
  and my decisions and read its record on GitHub from the first minute, so I never type
  the job into a prompt.
- As a coordinator restarted after a crash, I want to find and adopt the record I already
  opened, even one opened a minute before the crash, so no second record drifts beside it.
- As a rotation successor, I want the predecessor's open deferrals carried into my record
  and nothing dispatched until I've filed, closed or carried each one, so none is lost at
  the handoff.
- As a coordinator told by a worker that its pull request is green, I want the workflow to
  read the head and the board itself before any land step, so what I relay or merge is
  what was verified.
- As a maintainer receiving a merge-order table, I want each row's head to be one the
  workflow verified, so the order I merge in is safe.
- As a coordinator with free slots and a next feature that waits on another feature
  landing, I want to start that feature's scoping now and its execution later in the same
  worker, so the cap stays full.
- As a coordinator whose scope has nothing unblocked left, I want to ask whoever dispatched
  me for other work, so free slots aren't wasted.
- As the maintainer who will decide whether pick or report classification can be
  automated, I want every such call recorded beside a shadow answer, so the decision rests
  on evidence.

## Requirements

### Starting and the workflow

- **R1. The loop is a koto workflow.** `/coordinate` runs as a koto session with states for
  start, reconcile, pick, dispatch, wait, verify, land or surface, record, the roadmap
  close-out, and the rotation close-out at discipline scope. The session's own log is kept
  after it ends, so a run can be read afterwards.
- **R2. Arguments are checked before a session exists.** The roadmap path or discipline
  name, the host repository, the rotation length, the worker cap and the parked-worker
  bound reach the session as constrained values; a malformed one (a path outside
  `docs/roadmaps/`, a discipline name outside `^[a-z0-9-]+$`, a length or cap that isn't a
  positive integer) is refused before any session exists. Free text after the scope is
  the human's decisions: it is shown to the coordinator as decisions and never changes a
  setting the workflow enforces.
- **R3. Start checks.** Before anything else the start state: stops, dispatching nothing,
  when the roadmap is missing or not Active; sets a rotation's length to seven days when
  none was given; asks once, with a recommendation, for a discipline's host repository
  when none was given and never defaults to the repository it runs in; reads the posture,
  and, when the posture can't be read, treats every finishing step as reserved and asks
  the human once which ones the coordinator holds.
- **R4. Every prose rule survives.** Each step, bound, definition and "never does" in the
  current skill and its four references is carried into the directive or guidance of the
  state that uses it, or into the skill file where it is global. The four references
  remain and each is named by the states that use it.
- **R5. Thin skill file.** The skill file states the flags, how to open the session, how to
  advance it, how to print its report, and the final states, and holds no step procedure.
  Each state's longer guidance is shown when the coordinator arrives at the state, not on
  every advance.
- **R6. No permission rule of the skill's own.** No state says who merges, closes or tears
  down. The land state takes each finishing step exactly as far as the posture read at
  start allows; a step the posture denies, or puts behind a person's confirmation, goes to
  the human as a hand-over, never a retry by another command.

### The four checks

- **R7. The record exists, once, before any dispatch.** Before a run's first dispatch the
  workflow has itself read GitHub and found exactly one record for the scope:
  - Roadmap scope: an open issue in the host repository titled exactly
    `Coordinator record: ROADMAP-<name>` whose body carries the declaration line, found by
    listing every open issue (not only the first page) and never through GitHub's search.
    A closed issue with the title doesn't count.
  - Discipline scope: an open pull request from `coordinate/discipline-<name>` whose body
    carries the declaration line and whose title end date hasn't passed.
  A title or branch match without the declaration line, or more than one match, stops the
  run for the human. When none is found the coordinator opens one (R17) and the workflow
  reads GitHub again; only that read satisfies the check.
- **R8. The record has its four sections.** The found record carries Holdings, Deferrals,
  Side effects in flight and Reversals, in that order, each a table with its fixed columns
  or the line `None.`; a record that doesn't stops the run for the human, like an
  ambiguous match.
- **R9. Deferrals are disposed of before the first dispatch.** The workflow refuses the
  run's first dispatch while any deferral raised before this run started is undisposed. A
  deferral is disposed of when its Disposition cell reads `filed #<n>`, `closed: <reason>`,
  or `carried <time>: <reason>` with a time at or after the run's start. At discipline
  scope the check also reads the previous rotation's handoff file (or its still-open record
  when the successor closes it), and every deferral there must appear in the new record
  with a disposition. The check reads GitHub, not the coordinator's evidence.
- **R10. The board really ran.** A head is verified only when the board at that head is
  non-empty; every run in it has finished and none concluded `startup_failure`; every job that ran
  (every job not concluded `skipped`) concluded `success`, ran on a named runner, and had at
  least one step that succeeded; every check GitHub marks required for the pull request is
  present, finished and successful, including one concluded `skipped`, which fails; and the
  pull request's merge state isn't `DIRTY`. Jobs concluded `skipped` that aren't required are
  listed in the verify report.
- **R11. A verified head before any land step.** The land state is reachable only after the
  workflow itself read the pull request's head from the remote and verified it under R10.
  On entering land the workflow reads the remote head again and refuses when it differs
  from the verified one. The coordinator never supplies the head. The verified head is kept
  in the session and written into the holding's Verified head column by the record step.
- **R12. The prediction comes first.** The verify state takes, before the board read, the
  coordinator's written prediction of which reds it would report and which it would
  escalate, and the board read doesn't run until it's submitted.
- **R13. Checks can't be overridden.** No `koto overrides record`, with or without data, can
  stand in for R7 to R11, and no field the coordinator submits is read by those checks.

### The record

- **R14. One renderer, fixed columns.** The record body and the discipline handoff file are
  produced by one renderer from structured input. The body opens with the declaration line
  and a `Written:` UTC time, then the four sections with these columns:
  - Holdings: Unit, Entry point, Mode, Phase, Worker, Repo, Branch, Verified head,
    Dispatched, Pull request.
  - Deferrals: Deferral, Reason, Raised, Disposition. Raised and a carry-forward's date are
    UTC times to the minute (`YYYY-MM-DDTHH:MMZ`).
  - Side effects in flight: Action, Target, Verified head, Attempted, How to confirm.
  - Reversals: Date, Reversed, Now, Reason, From.
  A rendered body parses back to the same input.
- **R15. Rewritten whole, nothing recomputable.** Every update replaces the whole body with a
  new `Written:` time. No section carries a status, CI or merge-state column; the renderer
  refuses input that tries to add one. A deferral filed or closed drops out at the first
  rewrite after the run's first dispatch; a carried one stays.
- **R16. Safe cell values.** Workers are named by dispatch topic; the renderer refuses a
  worker value containing a `/`, a UUID, a `session_` prefix, or only digits, which are the
  shapes of a filesystem path, an instance or session id, and a job id.
  Quoted text, a pipe, a newline or a backtick run in any cell can't change a table's
  column count.
- **R17. Finding is a read, every write is the coordinator's.** Finding the record is a read
  the workflow runs itself. Opening, rewriting and closing the record are GitHub writes the
  coordinator runs as its own steps, through scripts, never as something the workflow runs
  unprompted. A restart that finds its record never opens one.
- **R18. The record follows each event.** A dispatch is recorded as a holding before the
  workflow leaves dispatch, and the workflow confirms the holding's row is on GitHub. The
  record is rewritten after every verified report, every merge or attempted merge, every
  new deferral and every reversal, before the loop goes round again.
- **R19. Discipline record lifecycle.** At discipline scope the find distinguishes: an open
  record past its end date (the predecessor's, closed out first, then found again); an open
  pull request on the branch without the declaration line (stops for the human); a branch
  whose last pull request merged or closed (re-cut from the default branch); no branch (cut,
  pushed, draft pull request opened). The rotation's title is
  `docs(coordinate): <name> rotation <start> to <end>` and the end date is read from it.
- **R20. Rotation close-out.** At rotation end the workflow has the coordinator commit the
  handoff file (from R14, with a freshly written reasoning section), correct the title's end
  date when the rotation ended early, and then merge, or hand the merge over, per the
  posture. The coordinator deletes the branch after a merge it made; after a merge it
  handed over, the next rotation's find re-cuts the branch (R19). Closing a predecessor's rotation copies its
  tables as "not re-checked" and never writes its reasoning.
- **R21. Roadmap close-out.** The roadmap record closes only when every feature reads Done or
  Dropped, Holdings and Side effects in flight are empty, and every deferral is filed or
  closed; the workflow reads all of that itself, then the final body is written and the
  issue is closed or the close handed over per the posture.

### Pick, the cap and deciders

- **R22. A cap on parallel workers.** The worker cap defaults to five. On every pass pick
  dispatches until active workers equal the cap or no unit is left. Parked workers and local
  agents don't count against it. The separate bound on parked workers waiting on a
  person's merge stays at a default of three: at or over it, pick dispatches nothing new.
- **R23. Scoping ahead.** A unit whose execution waits on another feature landing is
  dispatched for scoping now, in phase `scoping-ahead`, and the same worker session is sent
  its execution when the blocker lands, moving the holding to `executing`. Pick uses this
  before asking up.
- **R24. Asking up.** When free slots remain and the scope has no unit left, pick sends
  whoever dispatched the coordinator (a person or a coordinator, through the same channel
  it reports on) a request for out-of-scope work, and doesn't invent work. The loop keeps
  running while it waits. Work it's assigned is recorded as a holding like any other; a
  proposal it makes itself stays unacted on until answered.
- **R25. Shadow deciders on the two judgment calls.** Pick's choice and the classification
  of a worker's report (done, blocked, needs a fix) each carry a shadow decider. Its inputs
  are values the workflow itself recorded and checked, never free text. Its answer is
  recorded beside the coordinator's, the coordinator's answer always decides, and no
  automatic answer can end the run or pass a confirmation. The declarations are listed in
  the repository's decider declaration list with fixtures, so a later change can move them
  to automatic.

### Wait and failure

- **R26. The wait is message-driven.** Workers report by message plus what they pushed, and
  the coordinator advances the workflow on each message or notification. The wait state's
  guidance says when a worker's result is read from a koto request leg (a same-host worker
  whose entry point accepts a leg) and when from the message (every other worker). Nothing
  in the workflow depends on an open-ended watcher; any bounded wait states its deadline in
  the state's guidance.
- **R27. Quiet workers.** The wait guidance says a worker is quiet after 30 minutes with no
  message or push and is checked at most once per 30 minutes; the human's decisions may set
  other intervals, which the coordinator applies as guidance, not as a workflow setting. A quiet
  worker whose check shows nothing new gets one status message; a second silent check sends
  its unit to the failure branch (re-dispatch or escalate) without declaring the worker gone
  and without any teardown.

### Packaging

- **R28. Declared requirements.** The skill's requirements file declares the koto version
  the workflow needs and every tool its scripts and states call, and the load-time check
  passes.
- **R29. Tests.** Every script has a test beside it that runs offline against stand-in
  `gh` and `koto`.
- **R30. Evals.** Every existing eval scenario keeps passing, and new scenarios cover: the
  record found instead of duplicated after a restart; a deferral blocking the first
  dispatch; a verified head recorded before a land step; pick filling the cap, scoping
  ahead, and asking up.
- **R31. Public repository hygiene.** No committed file references a private repository,
  session, instance, job id, or a `wip/` path.

## Acceptance Criteria

Workflow and start:

- [ ] `skills/coordinate/koto-templates/coordinate.md` and its mermaid companion exist, and
      they pass every template check shirabe's CI runs.
- [ ] The template has a state for each loop step named in R1, and a rotation close-out
      and a roadmap close-out state.
- [ ] Initialising with a roadmap path outside `docs/roadmaps/`, a discipline name with an
      uppercase letter, a rotation length of `0`, a cap of `0`, `-1` or `abc`, a parked bound
      of `abc`, or a host repository that isn't `owner/repo` fails, and no session exists
      afterwards; free text after the scope that reads `--cap 9` leaves the cap at 5.
- [ ] A discipline start without a rotation length records seven days; one without a host
      repository asks for it once and never proceeds with the repository it runs in.
- [ ] A test with a Draft roadmap fixture reaches a stopping state from start without
      entering dispatch.
- [ ] A test with an unreadable posture fixture routes start to a question to the human
      rather than to reconcile.
- [ ] A coverage table in the design lists every step, bound, definition and "never does"
      of the current skill and references against the state or file that carries it, and a
      test checks each row's key phrase is present where the table says.
- [ ] Each of the four reference files exists and is named in at least one state's guidance.
- [ ] Advancing into a state and then advancing again without leaving it shows the state's
      longer guidance only the first time.
- [ ] The skill file contains no numbered step procedure, names the final states, opens the
      session with the shared opener, and keeps the session log past its end on every
      advance.
- [ ] A test with a posture fixture that permits a merge reaches a merge step in land; one
      that denies it, and one that requires a person's confirmation, each reach a hand-over
      and no merge step; no state's text outside start, land and the close-outs names who
      merges, closes or tears down.

The four checks:

- [ ] Against a stand-in `gh`: with no record, dispatch is unreachable and evidence naming an
      issue number doesn't change that; after the stand-in gains a matching record, the next
      advance reaches pick with no evidence naming the record.
- [ ] The find succeeds when the record is one of 150 open issues; a closed issue with the
      title isn't found; a `-v2` title isn't found; two matches, or one without the
      declaration line, route to the human.
- [ ] The stand-in `gh` fails any search (`--search`, `-S`, `gh search`, a `search/` API
      path), and every find test passes against it.
- [ ] At discipline scope the find returns an open draft pull request from
      `coordinate/discipline-<name>`, ignores one from another branch, and routes each of the
      four lifecycle cases of R19 to its own state.
- [ ] A record missing any one of the four sections, or with a section that is neither a
      table nor `None.`, keeps dispatch unreachable.
- [ ] Rows disposed of as `filed #12`, `closed: done by #40` and `carried <today>: <reason>`
      each let dispatch through; `carried <an earlier date>`, `filed` without a number, an
      empty Disposition, and a predecessor handoff deferral missing from the new record
      each keep it unreachable; a `None.` Deferrals section passes.
- [ ] A complete board where every job ran on a named runner with at least one succeeded
      step records the head and makes land reachable.
- [ ] Each of these records no head and leaves land unreachable: zero runs; runs only for
      another sha; a run failed at startup; a queued or in-progress run; a job without a
      runner; a job whose steps were all skipped; a job concluded `failure`, `cancelled` or
      `neutral`; a required check missing or concluded `skipped`; merge state `DIRTY`.
- [ ] A board with a non-required job concluded `skipped` verifies, and the verify report
      lists that job; a run whose first attempt failed and whose re-run passed verifies.
- [ ] A fixture whose head changes between the board read and entering land refuses land.
- [ ] Verify doesn't run the board read until the prediction is submitted.
- [ ] `koto overrides record` is refused on every check behind R7 to R11, both with no data
      and with data shaped like a passing result.
- [ ] A structure test shows no field the coordinator can submit is read by any check behind
      R7 to R11; a test submitting evidence that contradicts the stand-in GitHub state shows
      the check follows the stand-in.

The record:

- [ ] The renderer's output opens with the declaration line and a `Written:` UTC time, has
      the four sections with R14's columns, and parses back to its input; two renders
      differ only in `Written:`.
- [ ] The renderer refuses a status, CI or merge-state column, a phase other than
      `scoping-ahead` or `executing`, and worker values shaped like a session id, a path or a
      job id; it accepts a dispatch topic.
- [ ] A cell holding a pipe, a newline, a backtick run or a fence opener round-trips
      unchanged and every row keeps its column count.
- [ ] The discipline handoff file comes from the same renderer and parses with the same
      parser.
- [ ] The open script isn't run by any state on its own; a restart fixture with a record
      present never calls it (the stand-in `gh` logs every call).
- [ ] After dispatch, the workflow doesn't reach wait until the record on the stand-in shows
      a Holdings row for the dispatched topic.
- [ ] Every update path replaces the whole body and none appends a comment.
- [ ] After each of a verified report, a merge attempt, a new deferral and a reversal, the
      loop doesn't go round again until the record on the stand-in reflects the event; a
      verified holding's Verified head cell equals the sha the board read verified.
- [ ] A rotation close-out test commits the handoff, corrects an early end date in the title,
      and reaches a merge step or a hand-over per the posture fixture; closing a predecessor's
      rotation copies its tables under "not re-checked" and writes no reasoning for it.
- [ ] A roadmap close-out test with one feature not Done, or one undisposed deferral, doesn't
      reach the close step; with all Done and the record clear, it does.

Pick, deciders, wait:

- [ ] Eval: cap 5 with two executing holdings, one parked worker and three unblocked units
      yields three dispatches in one pass.
- [ ] Eval: a unit blocked on another feature landing is dispatched with phase
      `scoping-ahead`, and when the blocker lands the same worker is sent the execution and
      the holding moves to `executing`.
- [ ] Eval: with three parked workers and free slots, pick dispatches nothing new.
- [ ] Eval: with free slots and nothing unblocked, the coordinator asks its dispatcher for
      work, dispatches nothing invented, and doesn't act on its own proposal before an answer.
- [ ] The pick guidance and the skill's bounds section both state a cap of 5, a parked bound
      of 3, and that parked workers and local agents don't count.
- [ ] Shadow deciders are declared on pick and report classification, listed in the decider
      declaration list with fixtures, and the declaration check passes.
- [ ] A test submits an answer that differs from the shadow answer and shows the
      coordinator's answer decides and both are recorded; no decider answer can reach a
      terminal state or a confirmation.
- [ ] The wait state's guidance names when the leg is read and when the message is; no
      state starts an unbounded watcher.
- [ ] A test with two silent checks after a status message reaches the failure branch and no
      teardown step.

Packaging:

- [ ] Every script's test passes with network access off, no GitHub token set, and `PATH`
      restricted to the tools the requirements file declares plus the stand-ins.
- [ ] The load-time check passes with the requirements file as committed.
- [ ] `evals/evals.json` keeps all nine existing scenarios and adds those named in R30, and an
      eval run passes.
- [ ] The skill file's Known Limitations section names shirabe#395, #396, #398, koto#250 and
      shirabe#401, each with what it costs today.
- [ ] `git grep -n 'wip/'` over added and changed files is empty, and a grep of them for
      private repository names, session ids, instance directory names and UUID-shaped
      strings is empty.

## Out of Scope

- The dispatch tooling: compiling a worker's brief, recording a dispatch automatically, and
  binding a worker's result to a leg. The dispatch state follows the prose procedure.
- A mechanised reconcile beyond what the four checks read. The reconcile state follows the
  prose procedure, as do teardown inventories, the issue-timeline read before dispatching an
  issue, and the stacked pull request check (runs created before a blocker merged), which
  stays verify guidance.
- Any change to koto or the workspace manager; deciders in automatic mode; session liveness;
  the check for an effort held by two coordinators; externalised load.
- Request legs across hosts, which koto doesn't offer by design.
- Tracking homeless findings in the record: they're routed before a worker is retired, as
  the prose skill says, and the record keeps its four sections.

## Known Limitations

- **Which pull requests a worker owns (shirabe#395).** The workflow relies on each worker's
  `/deliver`, `/execute` or `/work-on` identifying only its own pull requests. Today every
  worker shares one login, so a worker can adopt a sibling's pull request on resume. The
  coordinator's own reads go by pull request number and dispatch topic.
- **Where merge order is recorded (shirabe#396).** A worker's coordinated PLAN writes an
  empty merge-order block that is never updated, so the order a coordinator hands a person
  comes from its own reading of dependencies.
- **Pull request bodies that aren't scoped (shirabe#398).** A worker's pull request body can
  describe more than the pull request carries; the verify step's file-list read is the
  defence, at one more read per report.
- **No delivered wake when a leg resolves (koto#250).** The engine's waker is a stub, so the
  coordinator advances the workflow on each message or notification.
- **No leg flag on `/deliver` and `/work-on` (shirabe#401).** Only `/scope` and `/execute`
  accept `--koto-leg` today, so the workers a coordinator most often dispatches report by
  message only.
- **Single host for legs.** koto's request store is local, so a worker on another host
  always reports by message.

## Decisions and Trade-offs

- **The check is a read the workflow runs, not a value it is told.** A check over a sha or
  record number the coordinator submits proves a value was supplied, not that anyone
  verified it. Each check reads GitHub itself.
- **Every GitHub write stays the coordinator's.** Opening, rewriting and closing the record,
  and every merge, are externally visible writes, which shirabe keeps out of steps the
  workflow runs unprompted; the read that follows is what the check trusts.
- **A worker cap of five, kept full.** Relayed from the repository owner during drafting; it
  replaces the prose skill's default of three active workers. The parked bound stays at
  three, because it protects the person's merge queue, not throughput.
- **Skipped jobs aren't "every job".** A job skipped by a condition never ran and isn't green,
  so it can't be the empty-green case R10 guards; counting it would make repositories with
  conditional jobs unverifiable. A required check that was skipped still fails, and every
  skipped job is listed in the report.
- **Disposition is a column, not a deletion.** The prose skill removed filed or closed
  deferrals, which left nothing for a check to read. A Disposition column makes the check
  possible; disposed rows drop out at the first rewrite after the run's first dispatch.
- **Only the latest attempt counts.** A re-run that passes replaces a flaky attempt; counting
  every attempt would leave that head unverifiable for good. Earlier attempts are listed.
- **Times, not dates, for deferrals.** A predecessor's deferral raised or carried the same
  day would otherwise pass without the successor touching it.
- **Silence isn't death.** The prose skill says both "dead after a second silent check" and
  "never on silence alone". This PRD keeps the second: two silent checks send the unit to
  the failure branch without declaring the worker gone.
- **Homeless findings stay out of the record.** A fifth section would give a check something
  to read but would make the record where findings wait, which the prose skill forbids.
