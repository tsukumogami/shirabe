---
schema: prd/v1
status: Done
problem: |
  A coordinator's state lives in a GitHub record and its koto session is thrown
  away at every start, so a restart rebuilds the run from a body it can only
  trust as a dated snapshot, and a coordinator moved to another host can't
  follow its workers' request legs, can't recover a worker that vanished with
  the old host, and lacks the facts a replacement needs after a crash. koto now
  moves a session between hosts with its context keys, and nothing uses it.
goals: |
  A roadmap coordinator whose owner chose the session store keeps its whole state
  in its own koto session: a restart resumes it, an import on another host
  continues it through the handover gate with no other file, and every worker
  leg ends watched, on the message path, or recovered through the loop. Every
  existing record stays on GitHub and works exactly as today until its owner
  moves it, and the entries read outside the loop stay on GitHub.
absorbed:
  - docs/briefs/BRIEF-coordinator-session-record.md
---

# PRD: The coordinator's session as its record

## Status

Done

Absorbed [BRIEF-coordinator-session-record](docs/briefs/BRIEF-coordinator-session-record.md); carried in Absorbed Brief.

## Absorbed Brief

The feature frames one gap: a coordinator keeps its state in two places, and the
one it throws away at every start is the one it runs in. A restart rebuilds the
run from the GitHub record, which it can trust only as a snapshot dated by its
`Written:` line; a move to another host loses what the record can't carry: each
worker's request leg and the result that came through it, the recovery of a
worker that vanished with the old host, and what a replacement needs after a
crash rather than a planned handoff.

The outcome it asks for belongs to whoever runs a coordinator. Starting a crashed
coordinator again resumes its own session; moving it imports that session on the
new host, and the replacement passes the handover gate and carries on with no
handoff file, tools directory or old session's memory, every worker watched,
reporting by message, or redispatched through the loop. A lane mid-run on a
GitHub record sees nothing change until its owner moves the record on purpose,
and the readers outside the loop (the cost join, the verdict readers, a
reviewer before a merge) keep finding what they read.

The journeys it traced are the four the User Stories carry: a crash restart on
one host, a replacement on another host with workers imported, left behind or
gone, a lane that stays on its record, and a reader outside a moved coordinator.
Its boundary is the one Requirements and Out of Scope draw: the state, the
resume and import path, the legs, the crash set, the seam and the write
guarantees are in; removing the GitHub record, moving any record by shipping,
koto changes, pause delivery and the split loop issues are out.

## Problem Statement

The coordinate skill keeps a coordinator's state on GitHub: an issue titled
`Coordinator record: ROADMAP-<name>` at roadmap scope, a draft pull request per
rotation at discipline scope. The body holds the tables every check reads
(Holdings, Deferrals, Side effects in flight, Reversals, Holds, Run, Standing,
Work and Decisions), and the comments hold the account. The coordinator's koto
session, `coordinate-<scope>-<UTC stamp>`, lives for one run: the next start
cancels it, opens a new one, finds the record and reconciles from its body,
whose `Written:` time is all it says about how current it is.

Three things go wrong with that split.

A holding's return path can name a koto request leg, and koto's request store
and its wakes never leave the host that created them. A coordinator adopted on
another host reads `leg <request-id>:<leg>` and finds no such request; whether the
worker's result ever arrived is unknowable from there.

A real host migration showed the loop can't recover on its own from what a move
leaves behind. A Holdings row reading `dispatched` whose worker vanished with its
host can't be relaunched or retired through the loop (shirabe#732), and a worker
whose leg was already read has no route for its later reports (shirabe#711).

The stored set was shaped by a planned handoff. After a crash, a replacement
also needs to know which rules and briefs the coordinator ran with, where its
friction log is, each worker's branch and the last head it pushed, and who the
coordinator reports to as a role, since a session name only means something on
the host that has it.

koto 0.16.0 imports a session from its S3 object into a fresh local session on
another host, every context key included, and marks the source migrated so any
command on it refuses. The skill-session convention reserves `record/` and
`legs/` in a coordinator's own session for this state
(`references/skill-session-convention.md`). Nothing in the coordinate skill uses
either.

Any change has to leave running coordinators alone. Coordinators run a pinned
release, and records on GitHub mid-run are read outside the loop: a join on each
unit's `cost` entries (schema `unit-cost/1`), a reviewer who reads holdings,
decisions and verdicts before a merge, and the milestone verdict entries and
`verdict-owed` Work rows that live on the record by design.

## Glossary

The coordinate skill's glossary (`skills/coordinate/SKILL.md`) holds. This PRD
adds or pins:

- **State source.** Where a run reads and writes the record's state: `github`
  (the issue body and comments, as today) or `session` (keys in the
  coordinator's own koto session).
- **Session store.** The keys under `record/` and `legs/` in the coordinator's
  session, which hold the state on the `session` source.
- **Writer.** The one script allowed to change a key (R4's table). Every write
  goes through the record's write core.
- **The write core.** `skills/coordinate/scripts/record-write-core.sh`, which
  every writer sources, and the codec `record-codec.jq`, whose checks every
  value passes.
- **Provenance, live run, directed transition.** As the write core checks them
  today: the session was created from the shipped template for this plugin; it
  is the one live session of its scope on this host; its log holds no
  `koto next --to` transition.
- **Leg.** A koto request leg a worker answers. It is **open** until koto records
  its result, **taken** once the coordinator has read that result, and
  **unwatchable** when this host's request store doesn't hold its request.
- **Bound, attach.** A worker session is bound to a leg when koto's request
  store on this host names it as the leg's child; to attach is to bind it with
  `koto request attach`.
- **Quiet checks.** The skill's existing rule: a worker is quiet after 30 minutes
  with no message or push, checked at most once per 30 minutes, and a second
  silent check after a status message sends its unit to the failure branch.
- **Report up.** A message to whoever dispatched the coordinator. Reports are
  messages, never committed files or GitHub posts.
- **Seam.** The one library through which every script reads the record's state,
  whichever the source (R17).
- **Outward entries.** The entry kinds read outside the loop: `cost`,
  `milestone-verdict`, `goal-fit` and `milestone-failure`.

## Goals

- A roadmap coordinator on the session store survives a restart on the same host
  by resuming its session, and a move to another host by importing it, and in
  both cases passes the handover gate and continues with no other file.
- Every worker leg a migrated coordinator can no longer watch ends in a defined
  state: watched again, moved to the message path, or recovered through the loop.
- The protections the write core gives hold in the session store.
- Every existing record stays on GitHub and keeps working as today until its
  owner moves it, and the outward entries stay where outside readers read them.
- Every script that needs the record's state reads it through one seam, so the
  later removal of the GitHub record is a deletion, not a rewrite.

## User Stories

- As the owner of a coordinator that crashed, I want to start it again and have
  it resume its own session, so nothing it held is rebuilt from a snapshot.
- As the operator retiring a host, I want to import the coordinator's session on
  the new host and have it pass the handover gate, so I carry no handoff file.
- As that operator, I want each worker the old host ran to end up watched,
  reporting by message, or redispatched through the loop, so I never edit the
  record by hand to unstick a holding.
- As a worker whose coordinator moved, I want to be told its new address and to
  have my later reports accepted by message, so my result isn't lost.
- As a lane owner mid-run on a GitHub record, I want nothing about my record to
  change until I set it to move, so an upgrade never moves state under me.
- As the person who decides to move a record, I want to set it once, with my
  name on it, and have the next start do the move and say so on the record.
- As a cost join or a reviewer of milestone verdicts, I want the outward entries
  on the record's GitHub issue whatever the store, so moving the state doesn't
  break my read.
- As a reviewer of a moved coordinator's ready pull request, I want one command
  that prints its holdings, decisions and Work rows the way the record body did.
- As whoever removes the GitHub record later, I want every script that needs a
  holding's facts to get them from one place, so the removal deletes code.

## Requirements

### The state source

- **R1. A state source per record, fixed per run.** Every run has one state
  source, fixed at its start and recorded in the run (R2). It is decided in this
  order:
  1. A record found on GitHub whose Run section carries a `store` row: `session`
     or `github` as the row says. Any other value, or two `store` rows, stops
     the run before reconcile with `store-malformed`.
  2. A record found on GitHub with no `store` row: `github`.
  3. No record found (a new scope): `session` when the invocation passes
     `--store session`, otherwise `github`. Passing `--store` when a record is
     found changes nothing and is reported as ignored.
  Nothing else changes a record's source: no probe result, no default and no
  upgrade.
- **R2. The capability probe.** Every start probes koto by feature, not by
  version: it needs `koto context list --prefix` and `koto session import` on the
  session source (both from koto 0.16.0), and nothing extra on the `github`
  source. The probe's result and the run's source are sealed into the run as
  `coord/source.json`, and the reconcile report names the source. A run on the
  `session` source whose probe fails stops before reconcile naming the missing
  feature, and never falls back to `github`; a `github` run is unaffected by a
  failed probe, and shirabe's koto minimum for `github` runs doesn't change.
- **R3. Moving an existing record is its owner's act.** A record moves only after
  the stored set's writer records the `store session` Run row with `--by` naming
  the person who decided it, the person as owner as for any Standing row (the
  coordinator relays a person's word, as today). The next start on the record
  does the move in three steps, each skipped when a re-run finds it done:
  1. copy the record's state into the session store in one write through the
     write core, when no session of the scope on this host holds `record/meta`
     (otherwise R12's resume or carry-across applies, and the move resumes at
     step 2);
  2. post a `moved` entry to the GitHub record naming the session's run stamp;
  3. rewrite the GitHub body to the moved shape (R8).
  A crash between steps resumes at the first step not done. After step 3 every
  writer refuses to change the GitHub body's state tables (`store-moved`). A row
  reading `store github` on a moved record, a move back, is refused in this
  release. A record without a `store` row is never touched.
- **R4. Roadmap scope only.** The session source is available at roadmap scope.
  At discipline scope `--store session` is refused and a `store` row is refused,
  since a rotation's committed handoff file and pull request are its store until
  the later removal of the GitHub record settles them.

### The session store

- **R5. One key per part of the state, one writer per key.** On the session
  source the state is these keys, each writable only by the writer named:

  | Key | Holds | Writer |
  |---|---|---|
  | `record/meta` | the scope, the store, the written time | the write core, on every write |
  | `record/holdings` | Holdings | `record-write.sh`, directly or through `record-holding.sh`, as today |
  | `record/deferrals` | Deferrals | `record-write.sh` |
  | `record/side-effects` | Side effects in flight | `record-write.sh`, and `roadmap-status.sh` for its four roadmap-edit actions |
  | `record/reversals` | Reversals | `record-write.sh` |
  | `record/holds` | Holds | `record-hold.sh` |
  | `record/run`, `record/standing` | Run, Standing | `record-state.sh` |
  | `record/work` | Work | `record-state.sh`; `verdict-owed` and `rework` rows only `roadmap-status.sh`, as today |
  | `record/decisions` | Decisions | `record-decision.sh` |
  | `record/host` | host facts that never go to GitHub (R14, R17) | `record-state.sh` (`coordinate-open.sh` calls it after an import) |
  | `record/entries/<n>`, `record/posted/<n>` | one entry of the account; the GitHub comment an outward entry became | `record-append.sh` |
  | `legs/<request-id>/<leg>` | one worker leg (R13) | `dispatch-worker.sh`, `wait-target.sh`; state `unwatchable` only `reconcile-legs.sh` |

  A write by any other script to a key is refused (`not-owner`, exit 65, the
  code the write core uses today for a section another writer changed).
- **R6. The same data, checked the same way.** Each section key holds that
  section in the JSON form `record-parse.sh` produces, and every write passes the
  codec's full set of checks for the same section on GitHub (a worker is a
  dispatch topic; no status, CI or merge-state field; pipes, newlines and
  backticks round-trip without changing a row's shape; no private repository,
  home-directory path or token-shaped string on a public host). `record/host` is
  the one exception: it is never rendered to GitHub, so it may hold workspace
  paths, and it still refuses a token-shaped string.
- **R7. The write guarantees.** Every write to the session store is refused, and
  changes no key, when: the session fails provenance or isn't the scope's live
  run (exit 10); the run's log holds a directed transition (exit 10); `record/meta`
  was written since the writer read it (`record-changed`, exit 12); the state
  rendered as a record body would exceed 60,000 bytes, the same budget as today
  (`record-full`, exit 13); or the writer doesn't own a key it changes (exit
  65). A write changes its section keys and then `record/meta`. These are the
  skill's to keep; none is asked of koto.
- **R8. The GitHub record of a session-source coordinator.** It stays open, is
  found by the same find, and its body is the moved shape: the declaration line,
  the `Written:` line, every section `None.`, and a Run section holding only the
  `store session` row. It holds no other state, so nothing on it can contradict
  the session.

### The account

- **R9. Entries are append-only keys.** On the session source each entry is the
  key `record/entries/<n>`, `<n>` a zero-padded sequence one above the highest
  key present, holding its stamp (host clock, UTC to the second), kind and text.
  A key that exists is never written again (`entry-exists`). The order of the
  account is the sequence, not the stamp, and it continues across a resume and
  an import because the keys travel. Listing returns the GitHub reader's JSON
  shape, with author the coordinator's address and the edited flag always false.
- **R10. Outward entries stay on GitHub.** An outward entry is written to the
  session first and then posted to the GitHub record exactly as today, and the
  comment's URL is kept in `record/posted/<n>`. A retry posts nothing when that
  key exists, or when an entry of the same kind and text, by an author with write
  access, was created on the record at or after the session entry's stamp, so a
  retry never duplicates it and an earlier identical entry never stands in for
  it. A failed post leaves the session entry and exits 14, as a
  written-but-not-told change does today, and the post is retried once, later.
  The roadmap edits that tie a verdict or failure entry to its comment keep
  working unchanged.
- **R11. Reading a moved coordinator's state.** `record-source.sh --show` prints
  the state on the session source rendered exactly as the record body would be,
  so a reviewer reads holdings, decisions and Work rows, `verdict-owed` rows
  included, on the coordinator's host without knowing key names. koto's own
  session view shows the same keys.

### Resume and import

- **R12. A restart resumes.** On the session source a start first looks on this
  host for the scope's sessions, `coordinate-<slug>-<stamp>`, that hold
  `record/meta`, and takes the newest by stamp:
  - live, with the same template hash as the shipped template: the start resumes
    it (no new session, no cancel) and the run keeps its stamp;
  - live with a different template hash, or finished or cancelled: the start
    opens a new run, carries every `record/` and `legs/` key across through the
    write core, and cancels a live predecessor without deleting its log;
  - none, and no import was asked for, on a record whose source is `session`:
    the start stops before reconcile with `session-absent`, naming the import
    that would bring it.
  Coordinator sessions keep this open and resume path and are exempt from the
  resume convention's rule that a finished session is replaced on the next open;
  they use the convention's `record/` and `legs/` naming.
- **R13. A leg is a key.** When the coordinator dispatches through
  a leg, `dispatch-worker.sh` writes `legs/<request-id>/<leg>` with the request,
  the leg, the holding's topic and state `open`. Each time `wait-target.sh` reads
  the request it records the bound child's session name; when it reads a
  result, it writes the result and state `taken` before the report is classified.
- **R14. An import continues on another host.** `coordinate-open.sh --import
  <session> --from <workspace-path>` compiles the shipped template on this host,
  runs `koto session import`, and then starts as R12 does on the imported
  session; `--trust-template` reaches koto only when the operator passes it. A
  refusal from koto (a child source, a name taken, no template of that hash, an
  unreachable bucket) is printed with koto's code and leaves no session opened.
  The opener refuses an import while a live session of the same scope exists on
  this host (`session-live`), and koto refuses a name already taken. The run
  keeps the imported session's stamp. The source workspace path, the
  session name and the template hash are kept in `record/host` and named in
  every report up, so the next import knows what to pass; they never go to
  GitHub.
- **R15. Every leg has a disposition at the first start on a host.** Before
  reconcile can pass, every leg key in state `open` gets one outcome:

  | This host's request store holds the request | The bound child's session is on this host | Outcome |
  |---|---|---|
  | yes | (any) | watched as today |
  | no | yes, bound to no leg | re-leg: a new request on this host, the child attaches to it, the holding's return path and the leg key name the new leg |
  | no | yes, bound to another leg, or no | unwatchable: the holding moves to the message path |
  | no | unknown (no child name recorded) | unwatchable |

  The handover gate holds while any leg is undecided (`leg-unclassified
  <topic>`). An unwatchable holding's worker is told the coordinator's address
  through the gate's existing `told` rule. A worker on the message path that the
  quiet checks send to the failure branch can be marked stranded there, by the
  coordinator choosing a re-dispatch for it (`record-holding.sh --strand
  <topic>`, refused for a holding not on the message path); a
  stranded holding is retired and its unit dispatched again under a new topic,
  whose brief names the old branch and last pushed head (shirabe#732). A report
  that later arrives from the retired topic matches no holding and is refused as
  it is today.
- **R16. A read leg doesn't strand later reports.** Once a holding's leg is taken
  or unwatchable, a message from that worker is accepted as a message report
  from `worker <topic>`, and its questions reach report intake attributed to it.

### What a replacement needs after a crash

- **R17. The crash set.** The stored set also carries, on the session source:
  - Run rows `rules` and `briefs`, one per file, each `<label> sha256:<64 hex>`,
    the digest of the bytes the coordinator ran with, and their locations in
    `record/host`;
  - a Run row `friction` with its location in `record/host`;
  - a Run row `reports-to`, `<role>` or `<role> at <address>`, where the role is
    words naming who (such as `the lane's dispatcher`) and the address is in the
    coordinator-address grammar;
  - each holding's last pushed head next to its branch, written when a report or
    a verify reads the pull request's head.
  The handover gate lists `no-reports-to` on the session source. A `github` run
  is unchanged: the codec refuses these rows there as it refuses any unknown Run
  key.
- **R18. The handover gate reads the session.** The handover gate reads the
  stored set through the seam, so on the session source it reads the keys, on a
  resume as after an import.

### The seam

- **R19. One read seam.** `skills/coordinate/scripts/record-source.sh` is the one
  place the record's state is read. It gives the record as `record-parse.sh`'s
  JSON, its written time, and per holding topic `{unit, repo, pull_request,
  branch, verified_head, phase, dispatch_status, return_path, holds, pauses}`,
  from whichever source the run is on. Every script that reads a record body or
  a `record/` key today reads through it; their GitHub reads don't change.
- **R20. Delivery order.** The seam ships first, on its own, with every reader
  switched to it, and the session source refused (`store-unavailable`) wherever
  it would be chosen, so no run can be half on each source. The change that
  enables the session source enables the writers, the handover gate and the
  land check's and the merge's hold and pause reads together.

### Packaging and tests

- **R21. The real path in tests.** Tests of the session store drive real koto,
  and write keys only through the skill's writers. Where a test needs a cloud
  bucket, an in-memory S3-compatible stand-in serves it, and the suite's header
  says so.
- **R22. The acceptance test restated.** `handover_engine_test.sh` builds the
  coordinator's state through the writers on one simulated host (its own
  `HOME`), imports the session on a second through `coordinate-open.sh
  --import`, and runs today's five cases there.
- **R23. Declarations.** The skill's requirements file lists every koto call the
  session store makes, and the load-time check passes.

## Acceptance Criteria

Each criterion names the requirement it checks.

The state source:

- [ ] (R1) Every existing suite under `skills/coordinate/scripts/` passes with no
      change to its fixtures or expected output.
- [ ] (R1) Against a record with no `store` row, `--store session` is reported
      ignored and the run's `coord/source.json` reads `github`; a record with
      `store` reading `bogus`, or two `store` rows, stops with
      `store-malformed`.
- [ ] (R1, R8) A new scope opened with `--store session` opens a GitHub record in
      the moved shape and a session holding `record/meta`; without `--store` it
      opens today's record.
- [ ] (R2) `coord/source.json` carries the source and the probe's result on
      every start; a session-source start on a koto stand-in without `session
      import` stops naming it and writes nothing; a `github` start on that koto
      reaches reconcile.
- [ ] (R3) After `record-state.sh --run store session --by alice` on a GitHub
      record, the next start copies every section into its key, posts one
      `moved` entry and rewrites the body to the moved shape; killing the start
      after step 1, then starting again, completes steps 2 and 3 with one
      `moved` entry in all; afterwards `record-write.sh` on the GitHub body
      exits with `store-moved`; `--run store github` is refused.
- [ ] (R4) `--discipline ... --store session` is refused at open, and
      `record-state.sh --run store session` on a discipline record is refused.

The session store:

- [ ] (R5) For each key in R5's table, a test writes it through its writer and
      reads it back through the seam; `record-hold.sh` changing `record/run` is
      refused with exit 65.
- [ ] (R6) A worker shaped like a session id, a path or a job id, a status
      column, and a cell holding a pipe, a newline and a backtick each behave in
      the session store exactly as on GitHub (refused, or round-tripped).
- [ ] (R7) Against real koto, each refusal leaves every key unchanged: a session
      that isn't the live run (exit 10), after a `koto next --to` (exit 10), a
      stale written time (exit 12), a state that renders past 60,000 bytes (exit
      13), and a non-owner (exit 65).
- [ ] (R9) Two entries appended with the same frozen clock list in sequence
      order; an import followed by a third append numbers it three; writing an
      existing entry key is refused.
- [ ] (R10) On the session source, a `cost`, `milestone-verdict`, `goal-fit` and
      `milestone-failure` entry each lands in the session and on the GitHub
      record; with the GitHub post failing, the session entry stays and the
      script exits 14; the retry posts once; a second retry posts nothing.
      `roadmap-status.sh --verdict` accepts the verdict's GitHub comment URL.
- [ ] (R11) `record-source.sh --show` on the session source prints a body that
      `record-parse.sh` parses back to the session's state.

Resume and import:

- [ ] (R12) A second start on the same host prints the first run's session
      name, opens no session and cancels none; with the template's hash changed
      it opens a new run holding every `record/` and `legs/` key and the old
      run's log is still readable; a session-source record with no session on
      this host stops with `session-absent`.
- [ ] (R14) An import through the opener, with koto's cloud backend on the S3
      stand-in, brings every key; the source then refuses with
      `session_migrated`; the run keeps the source's stamp; `record/host`
      names the source workspace path, session and template hash; an import
      naming a child session, or with no locally compiled template, is refused
      with koto's code and no session is opened.
- [ ] (R22) `handover_engine_test.sh` runs from an imported session and passes
      its five cases: the stored set read back, the gate holding until each
      worker is told, the relay duty, the cap of one from the record reaching
      pick, and a holding with no next step holding the gate.

Legs:

- [ ] (R13) After a dispatch through a leg the leg key reads `open` with its
      topic; after the wait step reads the result, the key reads `taken` with
      the result before the report is classified.
- [ ] (R15) After an import: an imported worker session bound to no leg is
      attached to a new request on the new host, the holding's return path names
      it, and the worker's terminal result resolves it; a worker whose session is
      not on the new host has its holding moved to `message`, as does one whose
      session is bound to another leg or whose child name was never recorded; a
      leg whose request this host's store holds is watched as today; the gate
      lists `leg-unclassified` until each leg is decided.
- [ ] (R15) A holding on the message path whose quiet checks reach the failure
      branch, marked stranded, is retired; its unit is dispatched under a new
      topic whose brief names the old branch and last pushed head.
- [ ] (R16) A message from a worker whose leg is taken is accepted as a message
      report; one carrying a `Questions:` part opens a decision attributed to
      `worker <topic>`.

The crash set and the seam:

- [ ] (R17) After an import the stored set read back carries `rules`, `briefs`,
      `friction` and `reports-to` rows and each holding's last pushed head; with
      the `reports-to` row removed the handover gate lists `no-reports-to`; on a
      `github` run `record-state.sh --run reports-to ...` is refused.
- [ ] (R19) A structure test fails when any script under
      `skills/coordinate/scripts/` other than `record-source.sh` and the
      writers named in R5 calls `record-parse.sh`, `lib_parse` or
      `bl_record_parsed`, or reads a `record/` key.
- [ ] (R19) For the same state written to GitHub and to the session, the seam
      returns the same record JSON and the same per-topic facts.
- [ ] (R20) In the seam's release, `--store session` and a `store session` row
      each stop with `store-unavailable` before anything is written.
- [ ] (R23) The load-time check passes with the requirements file as committed.

## Out of Scope

- Removing the GitHub record as a store, or deleting the record scripts and their
  codec. The `github` source stays fully working.
- Moving any record by shipping this. The move exists; only a record's owner
  triggers it.
- The session source at discipline scope (R4).
- Making the session source the default for new scopes; see Decisions.
- Any change to koto; a store that needs a format koto lacks is proposed to koto.
- Carrying a pause to dispatched sessions (tsukumogami/niwa#362).
- A worker's run identity across hosts: `/execute` adopting its own merged pull
  requests after a cross-host resume (shirabe#733). The coordinator's own run
  identity is in scope (R12, R14); confirming a pull request merged outside the land step
  (shirabe#710); a delta review seat in the panel table (shirabe#758); and a
  question a worker sends while its leg is still open (the open-leg half of
  shirabe#711).
- The teardown archive and transcripts.

## Known Limitations

- A worker that stays on the old host after a move reports by message only:
  koto's request store doesn't cross hosts, and its leg resolves into the old
  host's store.
- The migrated marker is a flag. A source host that can't reach the bucket keeps
  running its copy with a warning; the operator retires the source before
  importing, as koto's import requires. Two coordinators on one host are refused
  by the live-run check; two on two hosts after an import are koto's accepted
  risk.
- A moved coordinator's holdings and decisions are read on its host (R11), not
  on GitHub.
- A write changes several keys without a transaction: a crash between them can
  leave a section newer than `record/meta`. Every section is still the last
  whole write of its own writer.

## Decisions and Trade-offs

- **GitHub stays the default for new scopes in this release.** A session default
  would land a new coordinator of another lane on a store its outside readers
  can't read yet: the cost join and the verdict readers are contracts on
  GitHub-readable records, and a new scope that lane opens would break them
  silently. Flipping the default belongs to the later work that removes the
  GitHub record, which has to settle those readers first, and it is that work's
  decision. `--store session` opts a new scope in.
- **The store a record is on is written on the record.** The `store` row on the
  GitHub record, read by the find at every start and sealed into the run, tells
  a successor which store it is on, so no successor guesses.
- **Outward entries stay on GitHub.** Moving them would break the cost join and
  the roadmap edits that tie a verdict to its comment.
- **A template change is a run boundary.** Resuming a session onto a newer
  template would run old gates against new scripts; carrying the keys into a new
  run keeps both the state and the template whole.
- **Stranded is decided by silence, not absence.** A worker missing from this
  host may be alive on another; only the quiet checks, which already govern
  silence, send it to the failure branch.
- **Roadmap scope first.** A rotation's committed handoff file is its own store;
  moving discipline scope means settling it, which belongs with the removal.
- **Re-attach rests on a measurement.** The re-leg row of R15 is what koto 0.16.0
  does when measured: an imported session arrives bound to no leg, the old
  request id is unknown on the new host, and `koto request attach` on a new
  request there succeeds, with the child's terminal result resolving it. The
  design carries the measurement.
- **Split issues stay split.** shirabe#710, #733, #758 and the open-leg half of
  #711 are loop or `/execute` defects that hold whatever store the state lives in.
  shirabe#733 is a worker's run identity, `/execute`'s; the coordinator's own run
  identity across hosts is in scope (R12, R14): an imported run keeps its stamp.

## Amendment — 2026-10-23

`DESIGN-coordinator-record-teardown.md` removes the GitHub coordinator
record. The original text above is left unedited; this section records
what no longer holds.

Discipline scope, which R4 kept out of this feature and deferred to this
removal, is settled: a discipline coordinator runs on its session too, with
`record/rotation` and `record/reasoning`.

The coordinate scripts named above have new names: `record-append.sh` is
`state-entry.sh`, `record-decision.sh` is `state-decision.sh`,
`record-hold.sh` is `state-hold.sh`, `record-holding.sh` is
`state-holding.sh`, `record-source.sh` is `state-read.sh`, `record-state.sh`
is `state-stored-set.sh`, `record-write.sh` is `state-write.sh` and
`record-write-core.sh` is `state-write-core.sh`. `record-parse.sh` is gone.
`record-codec.jq` is gone; its checks live in `state-schema.jq`, which
validates the state as JSON.
