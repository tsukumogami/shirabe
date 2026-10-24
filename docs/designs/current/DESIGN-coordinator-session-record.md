---
schema: design/v1
status: Current
upstream: docs/prds/PRD-coordinator-session-record.md
problem: |
  The coordinate skill reads and writes a coordinator's state as a GitHub issue
  body, from about thirty scripts that each parse the body themselves, and opens
  a new koto session at every start. Moving the state into the coordinator's own
  session needs one place every script reads the state through, a per-record
  choice of where the state lives that never moves a record on its own, a
  session layout that keeps the write core's guarantees, a resume and import
  path, and a defined fate for each worker leg after a host move, which koto's
  host-local request store makes unwatchable.
decision: |
  A new sourced library, record-source.sh, becomes the one reader: it returns the
  record as record-parse.sh's JSON and per-topic facts from either source, and
  every script that parses a body today calls it instead. The source is fixed per
  run from a `store` Run row on the GitHub record (or `--store` for a new scope),
  sealed into the run, with GitHub the default. On the session source the state
  is one key per section under `record/`, entries under `record/entries/<n>`, and
  legs under `legs/<request>/<leg>`, written by the same writers through the same
  write core, which validates by rendering the whole state as a record body and
  compares a written time in `record/meta`. A start resumes the scope's live
  session, carries keys into a new run on a template change, and imports through
  `koto session import`. After a move each open leg is re-legged, moved to the
  message path, or later stranded and redispatched.
rationale: |
  Making the seam return the parsed record rather than a narrow tuple means each
  reader changes one call, not its logic, and the later removal of the GitHub
  record deletes one backend. Validating session writes by rendering keeps one
  codec and one byte budget for both sources. Keys per section preserve one
  writer per key, which a single state key can't. Resuming keeps the run's
  sealed checks and stamp, which a fresh run seeded from an export loses. The leg
  table rests on a measurement against koto 0.16.0, not on a reading of koto's
  design.
---

# DESIGN: The coordinator's session as its record

## Status

Current

## Context and Problem Statement

`PRD-coordinator-session-record.md` sets the requirements; this design cites them
by number. What follows is the technical picture they land on, read from the
coordinate skill's scripts at the head of `main`.

**Thirty readers, no seam.** The record's state is read in three ways. Five
section readers print one section from a fresh `gh issue view` plus
`record-parse.sh` (`record-holding.sh --list|--read`, `record-state.sh --list`,
`record-decision.sh --list|--read`, `record-hold.sh --list`, `roadmap-status.sh
--list`), and most mixed scripts call them. Ten scripts parse the whole body
themselves (`deferral-check.sh`, `record-confirm.sh`, `closeout-read.sh`,
`predecessor-handoff.sh`, `reconcile-read.sh`, `record-handover.sh`,
`roadmap-status.sh`, `decision-next.sh`, `rotation-close.sh`, and `board-lib.sh`'s
`bl_record_parsed` and `bl_human_holds_merge`). The writers read the live body
too, for their compare. The mixed scripts need more than the roadmap's
`{topic -> repository, pull request, verified head, holds, pauses}`: pause
coverage keys on the Holdings Unit, not the topic; pauses need Standing's
go-ahead rows as well as its pauses; `record-confirm.sh` needs Side effects,
Reversals, Deferrals, Work, Phase, Return path and the written time; the leg path
needs Dispatch status and Return path; teardown and report reads need Branch. And
the land path's verified head is a sealed log capture (`VERIFIED`, `LAND`), not
the record's cell, which `record-confirm.sh --verified`, `lib_parked`,
`lib_row_merged` and reconcile read.

**Writers and what the core guarantees.** `record-write-core.sh` checks provenance,
the live run and directed transitions (through `lib_write_guard`), the 60,000-byte
budget (exit 13), the canonical parse, the `Written:` compare (exit 12), section
ownership for Decisions, Holds, Run/Standing/Work and the `verdict-owed` and
`rework` rows (exit 65), and, on a public host, a scan refusing any cell that
names a private repository. Holdings, Deferrals, Side effects and Reversals have
no enforced owner: `record-holding.sh` is the Holdings writer by convention, and
the rest are written whole by the coordinator through `record-write.sh`, with
`roadmap-status.sh` adding its own Side effects rows.

**The session is thrown away.** `coordinate-open.sh` names every run
`coordinate-<slug>-<UTC stamp>` and, once the new run is open, cancels every other
live run of the scope. The stamp prefixes every Decisions stamp
(`lib_run_stamp`), so a decision written in one run is told apart from the next
run's.

**koto as shipped.** koto 0.16.0's `koto session import <name> --from <workspace>`
reads the source's state file and every context key from the bucket, needs the
compiled template in the importer's own cache by hash (or `--trust-template`),
refuses a child session as its source, and marks the source migrated so its
commands refuse with `session_migrated`. koto's request store and wakes stay on
the host that created them. `koto context list --prefix` lists keys by prefix.
Context keys are replaced whole by `koto context add`; there is no multi-key
write and no append.

**The other lane's readers.** Three readers outside the loop read a record on
GitHub: a join on `cost` entries, which selects comments whose body starts with
the exact marker `<!-- coordinator-record-entry v1 kind=cost -->`
(`skills/coordinate/references/unit-cost.md`); a reviewer reading holdings, decisions and verdicts
before a merge; and `roadmap-status.sh --verdict|--reopen|--confirm`, which reads
a verdict or failure entry back by its comment URL and requires its text byte for
byte.

## Decision Drivers

- Every existing record keeps working byte for byte on GitHub until its owner
  moves it (PRD R1, R3); the cost join's marker and the verdict entries' text
  can't change.
- One read seam that a later removal of the GitHub record turns into a deletion
  (R19, R20).
- One writer per key and every write-core guarantee kept by the skill, not asked
  of koto (R5 to R7).
- A coordinator's run identity, its sealed checks and its stamp, survive a
  restart and an import (R12, R14).
- No leg left in an unknown state after a move, decided from what koto actually
  does (R15).
- The skill's floor: bash 3.2 and jq, and no new koto feature.

## Considered Options

### Decision 1: The shape of the seam

The roadmap names the seam as a `{topic -> repository, pull request, verified
head, holds, pauses}` source. The readers need more (see Context).

- **Chosen: a library returning the parsed record, with the tuple as a
  projection.** `skills/coordinate/scripts/record-source.sh`, sourced like
  `record-common.sh`, gives `rs_record <out>` (the record in
  `record-parse.sh`'s JSON form, and `RS_WRITTEN`), `rs_facts <topic> <out>`
  (`{unit, repo, pull_request, branch, verified_head, phase, dispatch_status,
  return_path, holds, pauses}` for one holding), `rs_source` and, run as a
  script, `--record`, `--facts <topic>`, `--source` and `--show`. Every script
  that parses a body today replaces its `gh ... view` plus `lib_parse` (or
  `bl_record_parsed`) with `rs_record`; the five section readers keep their
  command lines and read through it. A reader changes one call; its jq stays. The
  GitHub backend keeps each caller's call shape: `rs_record` makes the `gh issue
  view` or `gh pr view` read the section readers and whole-body readers make
  today, and `rs_record_api` makes `board-lib.sh`'s `gh api` read under its
  deadline, so the stand-in `gh` every suite uses answers both unchanged. The
  readers switched are the ten whole-body readers above, `reconcile-deps.sh` (which
  hands reconcile its parser), the five section readers, and through
  `board-lib.sh` the land check and the merge.
- **Alternative: the tuple alone.** Rejected: `record-confirm.sh`, `pick-facts.sh`,
  `deferral-check.sh`, `closeout-read.sh` and reconcile read sections outside it,
  so each would keep a second path to the record, which is the thing the seam
  exists to end.
- **Alternative: the section readers as the seam.** They already funnel most
  Holdings reads. Rejected as the whole answer: ten scripts read the whole body,
  and a reader that needs three sections would make three reads of a body it
  could read once.

### Decision 2: Where the choice of source lives

- **Chosen: a `store` Run row on the GitHub record, `--store` for a new scope,
  GitHub by default.** The find already reads the record at every start, so the
  row is where a successor learns the store without guessing. `record-find.sh`
  seals the source it read into `RECORD_FIND` and writes `coord/source.json`
  (`{source, reason, probe}`), and every later reader takes the source from that
  key. The row is written only by `record-state.sh --run store session --by
  <person>`, which records the person as the decider and posts the entry, like any
  person-owned change.
  A person with write access can still edit the issue body by hand, which the
  find's author check admits. Two checks close that: a `store session` row the
  run hasn't moved yet is acted on only when the record's entries, through the
  author filter, hold the `run` entry `record-state.sh` posted with it (otherwise
  `store-unverified`, a stop for the person); and, while a session of the scope
  on this host holds `record/meta`, a body reading `store github`, or carrying
  state tables with no `store session` row, is `store-conflict`, a stop for the
  person, never a switch back to GitHub state. A body with the `store session` row
  and its state tables still present is a move in progress, which `record_move`
  resumes. A new host with no session of the scope has nothing to compare against
  until an import brings one; that window is accepted, and the import's own checks
  apply once it does.
- **Alternative: a session default when koto passes the probe.** Rejected, by the
  coordinator's ruling of 2026-10-11: a session default would land a new
  coordinator of another lane on a store its outside readers can't read yet, and a
  new scope that lane opened would break its cost join and verdict readers
  silently. Flipping the default belongs to the later work that removes the GitHub
  record, which has to settle those readers first.
- **Alternative: an issue label.** Rejected: anyone with triage access can change
  a label, it leaves no decider, and the find would need a second read.

### Decision 3: The session layout

- **Chosen: one key per section.** `record/meta`, `record/holdings`,
  `record/deferrals`, `record/side-effects`, `record/reversals`, `record/holds`,
  `record/run`, `record/standing`, `record/work`, `record/decisions`,
  `record/host`, `record/entries/<n>` and `legs/<request-id>/<leg>` (PRD R5's
  table). Each section key holds its `record-parse.sh` section verbatim
  (`.holdings`, `.side_effects` and so on), so the seam assembles the record
  with one `jq` over the keys.
- **Alternative: one `record/state` key holding the whole JSON, or one
  `record/body` key holding the rendered body.** A write would be atomic, and with
  the rendered body the write core would change least: it already compares the
  whole record and enforces ownership by diffing parsed sections. Rejected for two
  reasons. One writer per key, the constraint this work carries from the record
  container design, would become one key every writer replaces, with ownership a
  diff over a shared value rather than a property of the key. And a body key
  keeps the markdown codec as the storage format of the session: the later
  removal of the GitHub record could not delete the renderer and parser, only
  the GitHub calls around them. Per-section keys hold the codec's JSON, which the
  removal keeps, and koto's session view shows each section on its own. The cost,
  a write that spans keys, is bounded below.
- **Alternative: koto's decisions or events for the account.** Rejected: koto's
  decisions are scoped to the current state, and its log carries no free text an
  entry could live in.

### Decision 4: How the write core keeps its guarantees on the session

- **Chosen: the same `core_write`, the same body input, a session backend at the
  end.** The caller still hands the core a rendered body file, as every writer
  does today, so no writer changes how it builds its write. The core runs
  `lib_write_guard`, the budget, the canonical parse, the ownership diffs and the
  private-repository scan exactly as today, with the live record read through
  `rs_record` instead of `gh`. Only the last step differs by source: on GitHub it
  edits the issue or pull request; on the session it parses the body it was about
  to write, checks the session-only fields (`pushed_head`, 40 hex or empty), reads
  `record/meta` and refuses `record-changed` (exit 12) when its written time isn't
  the one the caller read, writes `record/meta` marked `pending`, writes each
  section key whose JSON changed, and writes `record/meta` with the new time and no
  mark last. Ownership is today's: Decisions, Holds,
  Run/Standing/Work and the `verdict-owed` and `rework` rows keep their writer
  flags (`DECISIONS_WRITER`, `HOLDS_WRITER`, `STATE_WRITER`, `VERDICT_WRITER`),
  and Holdings, Deferrals, Side effects and Reversals stay `record-write.sh`'s,
  which `record-holding.sh` calls. Each key's owner is its section's owner, so one
  writer per key holds with no new flag, and the core's diff is what enforces it
  on both sources.
- **Alternative: per-key compare-and-swap with a written time in each key.**
  Rejected: the guarantee callers rely on is that nothing changed since they read
  the record, not since they read one section.
- **Alternative: ask koto for a compare-and-swap.** Rejected by the strategy
  behind this work: one writer by construction, so the guarantees are the
  skill's.

A write touches several keys, and koto has no multi-key write, so a crash between
keys can leave a section newer than `record/meta`. Each section is still the last
whole write of its own writer, and the next write's compare reads `record/meta`,
so the cost is one refused write, not a corrupt record. A reader could also see
some sections of a write and not others, such as a new hold beside old Holdings,
which the land check reads together. `rs_record` reads `record/meta` before and
after the section keys and re-reads, up to three times, when it is marked
`pending` or the two reads differ, then exits 12 as a write's compare would; a
`pending` mark a crash left is cleared by the next write, whose compare reads the
time beside it. A batch context write is
proposed to koto (Consequences).

### Decision 5: The account and the outward entries

- **Chosen: one key per entry, outward kinds also posted, deduplicated by
  content.** `record-append.sh` on the session source writes
  `record/entries/<n>`, `<n>` a six-digit sequence one above the highest key
  `koto context list --prefix record/entries/` returns, holding `{n, stamp,
  kind, text}`; it refuses a key that exists, and on that refusal takes the next
  number, at most three times (two local agents appending at once). For the
  outward kinds (`cost`, `milestone-verdict`, `goal-fit`, `milestone-failure`) it
  then posts the comment exactly as today and writes the comment's URL to
  `record/posted/<n>`. A failed post exits 14 with the session entry kept; the
  coordinator retries once, later, with `record-append.sh --repost <n>`, which posts
  nothing when `record/posted/<n>` exists, or when the record's entries, read
  through the same author filter the reader applies (write access to the host),
  hold one of the same kind and text created at or after the entry's stamp, which
  covers a post that landed before a crash. An identical earlier comment, a
  verdict repeated after a reopen or a comment a reader without write access
  pre-posted, never stands in for the entry. The marker line and the text are
  unchanged, so the cost join's exact-prefix select and the roadmap edits' byte
  comparison hold.
- **Alternative: a sequence number in the marker for deduplication.** Rejected:
  the cost join selects on the exact marker line, and a verdict entry's text is
  compared byte for byte.
- **Alternative: one key holding the whole account.** Rejected: an account only
  grows, and rewriting it whole on every entry is the archive problem the comment
  stream was chosen to end.

### Decision 6: Resume, carry-across and import

- **Chosen: resume the live session; carry keys into a new run on a template
  change; import through the opener.** On the session source `coordinate-open.sh`
  lists the scope's sessions on this host (`coordinate-<slug>-*`) holding
  `record/meta`, takes the newest stamp, and compares its recorded template hash
  with the shipped template's (`koto template compile` prints it). Same hash and
  live: check the session's name against the scope's `coordinate-<slug>-<stamp>`
  pattern, its provenance (`coord-log.sh provenance`, built from the shipped
  template) and its sealed `coord/source.json` reading `session`; then print
  `session=<that name>` and `resumed=1`, open nothing, cancel nothing;
  the first tick continues from the state the crash left, so the loop's own
  re-entry rules (reconcile re-checks before acting) still apply. Otherwise: open a
  new run as today, copy every `record/` and `legs/` key into it in one
  `GENERAL_WRITER`-style carry through the core, and cancel a live predecessor.
  `--import <session> --from <workspace-path> [--trust-template]` compiles the
  shipped template, refuses first with `session-live` when the scope has a live
  session here and with `session-name` when the name isn't this scope's
  `coordinate-<slug>-<stamp>`, runs `koto session import`, and continues as a
  resume of the imported session, with the same provenance check; under
  `--trust-template` that check still compares the imported template's hash with
  the shipped one and refuses a mismatch. An imported log carries its sealed
  `VERIFIED` and `LAND` captures; the land step re-reads the remote head before
  acting, as it does today, so a capture never stands for a head on its own. The opener then writes `record/host` through
  `record-state.sh --host` with the source workspace, session name and template
  hash.
- **Alternative: a stable session name with no stamp.** Rejected: the stamp is
  part of every Decisions stamp, and a template change needs a new session anyway.
- **Alternative: always a new run, seeded from the predecessor's keys.** That is
  the carry-across applied to every start, not only to a template change. Rejected
  as the default: it throws away
  the sealed checks and the run stamp a resume keeps, and a seeded copy of a
  crashed run's keys gains nothing over the run itself.

The opener on the GitHub source is unchanged: a new run, and the old one
cancelled.

### Decision 7: Legs after a move

Whether a leg can be re-attached after an import was measured, not assumed (see
the Spike below). The result decides the table.

- **Chosen: the PRD's R15 table.** A leg key in state `open` whose request this
  host's store lacks is re-legged when its recorded child session is on this host
  and bound to no leg, by `dispatch-worker.sh --releg-imported <topic>`. The leg
  key carries the child's session name as recorded on the old host; the script
  checks the name against koto's session-name grammar, recomputes the leg's
  declaration (template and inputs) from the holding row the way it does at
  dispatch rather than reading it from the key, and refuses unless the holding's
  Worker is the leg key's topic and the child session's own template and `TOPIC`
  match that declaration, which koto's `request attach` checks again. It writes the new request id into
  the leg key as state `releg-pending` before it attaches, then attaches, writes
  the new request's key `open` with `from` naming the old request, rewrites the
  holding's return path, and marks the old key `relegged`; a re-run that finds
  `releg-pending` reads the new request and finishes whichever step is missing,
  so a crash leaves no leg bound to nothing. Every other such
  leg is unwatchable: the holding's return path becomes `message`, and the
  handover gate's `told` rule makes the coordinator tell the worker its new
  address. A holding dispatched before leg keys existed has no key and no
  recorded child, so after a move its leg is unwatchable; on its own host it is
  watched through its return path as today. `reconcile-pass.sh` launches the
  classification as a write job of its own, `reconcile-legs.sh`, beside the
  settle, and runs one record write at a time so the two can't refuse each
  other as record-changed. `reconcile-legs.sh` is the third writer of leg keys:
  it sets a key `unwatchable`, first abandoning the new request a `releg-pending`
  key names. The gate lists `leg-unclassified <topic>` until each leg has its
  end.

A leg key's state is one of `open` (dispatched, or re-legged onto this
request), `replaced` (a new leg replaced it), `spent` (its launch failed, or it
ended with no result its worker promoted), `taken` (its result was read), `releg-pending`,
`relegged` and `unwatchable`; `dispatch-common.sh` holds the list every writer
checks.
- **Alternative: re-attach to the original request id.** Measured impossible:
  the new host's store answers `request_not_found`.
- **Alternative: every moved leg to the message path.** Rejected: it gives up a
  leg the measurement shows can be kept, for a worker that moved with the
  coordinator.

`wait-target.sh` records the bound child's session name in the leg key the first
time it reads the request with a child bound (`koto request get` returns
`bound_child`), keeping a list of the legs already recorded in the context key
`leg_children` so later ticks don't re-read every key, and writes the result and
state `taken` when it reads one, so a leg resolved before an import is readable
after it.

### Decision 8: Stranded holdings and spent legs

- **Chosen: a `stranded` dispatch status, set by the coordinator.** When the
  quiet checks send a message-path holding to the failure branch and the
  coordinator chooses to re-dispatch, `record-holding.sh --strand <topic>` sets
  Dispatch status `stranded` (refused unless the return path is `message`).
  `dispatch-worker.sh` treats `stranded` as it treats `dispatch-failed`: the unit
  is dispatched under a new topic, the old row is retired, and the new brief names
  the old row's branch and last pushed head. This closes shirabe#732 on either
  source: the case it reports is a GitHub record adopted on a new host.
- **Chosen: a message after a taken or unwatchable leg is a message report.**
  `report-source.sh` accepts a message from a holding whose leg key is `taken` or
  whose request this host can't read, as `worker <topic>`; `report_questions`
  reads its `Questions:` part as for any message.
- **Alternative: mark stranded automatically when the worker's session is absent
  from this host.** Rejected: a worker missing here may be alive on its own host,
  and silence is what the quiet checks already govern.

### Decision 9: The crash set

- **Chosen: Run rows on the session source, host facts in `record/host`, the
  pushed head beside the branch.** `record-state.sh` takes Run keys `rules`,
  `briefs` (repeatable, `<label> sha256:<hex>`), `friction` and `reports-to`
  (`<role>` or `<role> at <address>`) only when the run's source is `session`, and
  `--host KEY VALUE` writes their locations to `record/host`. A holding row on the
  session source may carry `pushed_head`, which `holding-link.sh` and
  `report-facts.sh` write through `record-holding.sh` whenever they read the pull
  request's head; the session backend checks it (40 hex or empty) and strips it
  before the codec render, and `--show` omits it.
- **Alternative: a Holdings column for the pushed head.** Rejected: a new column
  changes every GitHub record's bytes.

### Decision 10: The GitHub record of a session-source coordinator

- **Chosen: the moved shape.** A session-source record stays an open issue found
  by the same find, whose body is the declaration line, `Written:`, every section
  `None.`, and a Run section holding only the `store session` row. `record-open.sh
  --store session` opens it in that shape; the move (Decision 11) rewrites an
  existing body to it. After that the core refuses every GitHub body write on the
  record (`store-moved`, exit 65). `record-source.sh --show` renders the session's
  state as a body for a reviewer on the coordinator's host.
- **Alternative: keep mirroring the state tables to GitHub.** Rejected: two
  copies of the state with one writer each is the split this work ends, and a
  mirror that lags contradicts the session.

### Decision 11: Moving an existing record

- **Chosen: three idempotent steps in a new template state, `record_move`.** When
  the find reads `store session` on a record whose body still holds state tables,
  the run goes from `record_find` to `record_move`, whose directive runs
  `record-move.sh`: (1) when no session of the scope on this host holds
  `record/meta`, write the parsed GitHub state into this session through the core
  with every owner flag set (`MOVE_WRITER`); (2) post a `moved` entry on GitHub
  naming the run stamp, unless one is there; (3) rewrite the GitHub body to the
  moved shape with the core's GitHub backend. A re-run skips each step it finds
  done. A `store github` row on a moved record is refused by `record-state.sh`.
- **Alternative: copy on the owner's write.** Rejected: the owner may relay the
  decision from any session; the move must run in the run that will own the
  session.

### The spike: re-attaching a leg after an import

Run on 2026-10-11 against koto 0.16.0, with two simulated hosts (separate `HOME`,
XDG directories and workspace paths) sharing an in-memory, path-style
S3-compatible endpoint modelled on koto's own test endpoint. Both hosts used the
store template `koto-templates/skill-session.md`.

1. Host A: a coordinator session with a `record/` key; a request with one leg; a
   worker session started with `--koto-leg` on it, bound (`bound_child` named the
   worker); a `legs/<request>/<leg>` key written on the coordinator.
2. Host B: the template compiled, then `koto session import coord --from <A's
   workspace>`: `imported: true`, both keys present byte for byte.
3. Host B: `koto request get <request>`: `request_not_found`; `koto request list`
   for the coordinator: empty. Host A: `koto next coord`: `session_migrated`.
4. Host A: the worker closed; its result was promoted into A's request store
   (`result_source: promoted`). Host B still answered `request_not_found`.
5. A second worker, bound on A, imported to B. Its leg binding lives in A's
   request store, not in its session log, so it arrived bound to no leg.
6. Host B: a new request with the same leg declaration; `koto request attach
   --session <worker> <request> worker` succeeded (`bound_child` the worker,
   `attach: self`); closing the worker on B promoted its result into the new
   request.
7. Host B: attaching the imported worker to the original request id:
   `request_not_found`.

Steps 3 and 4 make a worker left on the old host unwatchable from the new one;
steps 5 and 6 make a worker imported alongside re-leggable; step 7 rules out
keeping the old request id.

## Decision Outcome

The coordinate skill gets one reader, `record-source.sh`, and every script reads
the state through it; the GitHub source sits behind it unchanged. A record's
source is a `store` row on the record itself, defaulting to GitHub, sealed into
each run. On the session source the state is keys under `record/` and `legs/`,
one owner each, written by the same writers through the same core, which keeps
every guarantee by rendering the state as a record body before writing keys and
comparing the written time in `record/meta`. Outward entries are written to the
session and posted to GitHub as today. A start resumes the scope's live session,
carries keys into a new run on a template change, and imports through
`koto session import`; after a move each leg is re-legged, sent to the message
path, or later stranded and redispatched. Moving a record is its owner's row and
three idempotent steps.

## Solution Architecture

### Components

| Component | Change |
|---|---|
| `scripts/record-source.sh` (new) | the seam: `rs_source`, `rs_probe`, `rs_record`, `rs_facts`, `rs_show`; GitHub and session backends |
| `scripts/record-find.sh` | reads the `store` row; seals the source; writes `coord/source.json`; `store-unverified`, `store-conflict` |
| `scripts/record-codec.jq` | Run keys `store`, `rules`, `briefs`, `friction`, `reports-to`; Dispatch status `stranded` |
| `scripts/record-write-core.sh` | live record through the seam; session backend; `store-moved` |
| `scripts/record-append.sh` | session entries; outward post, `record/posted/<n>`, `--repost` |
| `scripts/record-hold.sh` | reads via seam; a `hold` entry on the session source |
| `scripts/record-state.sh` | `store`, crash-set keys, `--host` |
| `scripts/record-holding.sh` | reads via seam; `--strand`; `pushed_head` |
| `scripts/record-open.sh` | `--store session` opens the moved shape |
| `scripts/record-move.sh` (new) | the three move steps |
| `scripts/coordinate-open.sh` | `--store`, the probe, resume, carry-across, `--import` |
| `scripts/dispatch-worker.sh` | leg keys; `--releg-imported`; `stranded` like `dispatch-failed` |
| `scripts/wait-target.sh` | leg key child and result |
| `scripts/report-source.sh` | message after a taken or unwatchable leg |
| `scripts/reconcile-pass.sh` | launches the leg classification as a write job, one record write at a time |
| `scripts/reconcile-legs.sh` (new) | leg classification: `--releg-imported`, or the message path and `unwatchable` |
| `scripts/record-handover.sh` | `leg-unclassified`, `no-reports-to` |
| readers switched to the seam | `board-lib.sh` (and through it `land-check.sh`, `land-merge.sh`), `deferral-check.sh`, `record-confirm.sh`, `closeout-read.sh`, `predecessor-handoff.sh`, `reconcile-read.sh`, `reconcile-deps.sh`, `roadmap-status.sh`, `decision-next.sh`, `rotation-close.sh`, `record-decision.sh` |
| tests and harness | `record-source_test.sh` (with the structure test), `record-move_test.sh`, session cases in the writers' suites, `session-store_engine_test.sh`, `legs-move_engine_test.sh`, `handover_engine_test.sh`; `testdata/fake-s3.py`; `run-tests.sh` (the new suites, and `python3` for the engine suites); `rule-coverage.tsv`; `coordinate-open.wording.tsv`, `coordinate-open_engine_test.sh` and `coordinate-template-structure_engine_test.sh` for the new opener codes and state |
| `koto-templates/coordinate.md`, `coordinate.mermaid.md` | `STORE` variable; `record_move`; directives for the session source |
| `requires.tsv` | `koto context list --prefix`, `koto session import`, `koto request attach` |

### The seam's backends

```
rs_record OUT
  source github : gh issue|pr view (or the issues API for bl_*) -> record-parse.sh -> OUT; RS_WRITTEN = .written
  source session: koto context get <session> record/meta, record/<section>... -> jq assemble -> OUT
                  (absent section key = empty section; absent record/meta = exit 3 "no session record")
rs_facts TOPIC OUT
  rs_record, then the Holdings row whose worker == TOPIC, its holds (on == repo#n),
  and pause-read.sh over Standing for its Unit -> one JSON object
rs_source
  coord/source.json in this run; before record_find, the STORE variable
```

### Data flow on a session-source write

```
writer: rs_record -> modify JSON -> record-render.sh -> body file -> core_write
core_write: lib_write_guard -> budget (13) -> canonical parse -> rs_record (live)
            -> compare written (12) -> ownership diffs (65) -> private scan
            -> github : gh issue edit | gh pr edit
            -> session: parse body -> per changed section: koto context add record/<key>
                        -> koto context add record/meta {written: now}
```

### The template

```
record_find --store session, state tables present--> record_move --moved--> reconcile_pass
record_find --otherwise--> (as today)
```

`STORE` is a new variable (`github` or `session`, default `github`), refused at
discipline scope by `coordinate-open.sh`. No other state changes routing; the
directives that name the record (record, reconcile, the close-outs) gain a
sentence for the session source.

## Implementation Approach

Four pull requests, each a working deliverable, merged in this order; the seam
merges before the writers move. All four shipped, as #773, #796, #852 and #911.

1. **The seam.** `record-source.sh` with the GitHub backend, every reader switched
   to it, `record-find.sh` sealing the source and writing `coord/source.json`, the
   probe, the codec's `store` key and the `STORE` variable. Wherever the session
   source would be chosen (`--store session`, a `store session` row), the run stops
   with `store-unavailable` before anything is written, and `record-state.sh`
   refuses `--run store session`. A structure test refuses any parse of a body
   outside the seam and the writers. Every existing suite passes unchanged; the
   one visible difference on GitHub is the new `coord/source.json` key and the
   template's hash, which the `STORE` variable changes.
2. **The session store.** The session backend of the seam and of the core, the
   owners per key, the account and outward entries, `record-open.sh --store
   session`, the move (`record-move.sh`, `record_move`), `--show`, and the removal
   of the three `store-unavailable` refusals. The handover gate and the land
   check's and the merge's hold and pause reads read the session from this change,
   because they read through the seam, and a named test proves it: on a session
   record holding a hold and a pause, `land-check.sh` and `land-merge.sh` both
   refuse. Tests against real koto, keys written only by the writers.
3. **Resume, import and the crash set.** The opener's resume, carry-across and
   `--import`; `record/host`; the crash-set Run rows and `pushed_head`; the
   gate's `no-reports-to`. `handover_engine_test.sh` builds the state through the
   writers on one simulated host, imports it on another through the opener with
   koto's cloud backend on an in-memory S3 stand-in (a small Python endpoint in
   `testdata/`, used only by the engine suites, which skip without `python3` the
   way they skip without koto), and runs its five cases.
4. **Legs after a move.** Leg keys at dispatch and wait, the classification in
   reconcile (`reconcile-legs.sh`) with `--releg-imported`, `leg-unclassified`, `stranded` and the
   redispatch, and the message route after a taken leg. An engine test moves a
   coordinator with one worker imported alongside and one left behind and checks
   every row of R15's table.

Eval scenarios run only where a change bears on one: the seam and the session
store change no routing the evals reach; the third and fourth add a start path
and a reconcile gap, which the existing handover and restart scenarios cover.

## Security Considerations

- **What reaches a command.** Every value read from the session store is checked
  against its grammar before any koto or `gh` call and reaches it only as an
  argument, never through a shell string: topics (`RE_TOPIC`), session names (the
  session-name pattern), request ids and leg names (koto's grammars), entry
  numbers (six digits), and a leg's stored declaration and result, which are read
  as JSON with `jq` and compared, never interpolated. `record/host` values are
  only printed, in reports up, so an operator knows what to pass the next import;
  no script reads them back into a command. `record/posted/<n>` has one writer,
  `record-append.sh`, and its value must be a comment URL on the record's own
  repository. A structure test holds the two broad write paths, the move's and the
  carry-across's, to `record-move.sh` and `coordinate-open.sh`.
- **The store a record is on.** A hand edit of the GitHub body by someone with
  write access can't flip a record: a new `store session` row needs the entry
  its writer posts, and a GitHub body that disagrees with a session holding
  `record/meta` stops the run (Decision 2).
- **Re-legging.** A leg is re-attached only to the child its key names, when the
  holding's Worker, the child's template and its `TOPIC` all agree (Decision 7).
- **The bucket, a residual risk.** On the session source the state syncs to
  koto's configured bucket, and anyone holding the bucket's credentials can
  rewrite any key, with no author recorded. That is weaker than GitHub, where a
  write needs repository write access and the find checks the author. The design
  doesn't close it: the skill's checks hold against a wrong or skipped write by
  the coordinator, not against a bucket writer, and the bucket needs the same
  access control as the repositories whose work it holds. The import takes the
  compiled template from the importer's cache unless the operator passes
  `--trust-template`; the opener never adds it.
- **Public hosts.** Every value bound for GitHub still passes the private-repository
  scan and the token check; on the session source the write applies the same
  checks to state that never leaves the host. The new Run rows are rendered, so the
  private-repository scan and the token check cover them; the visibility lookups
  stay fail-closed (a repository that can't be read counts as private).
  `record/host` and `pushed_head` never reach GitHub, and `--show` omits both.
- **Older releases.** A coordinator on a release before this change reads a moved
  record's `store` row as an unknown Run key, which its codec refuses, so its find
  reports the record malformed and stops for the person instead of writing to it.
- **Holds from a person.** A person can't edit a moved record's state by hand. A
  hold reaches it as it does today, through the relay duty: the person tells the
  coordinator, on the record or anywhere, and the coordinator writes it with
  `record-hold.sh`, which on the session source also posts a `hold` entry so the
  account shows when it was set and lifted.
- **Forged state on this host.** Anyone who can write the local store can rewrite
  a session; as with the bucket, the core's checks are against a wrong or skipped
  write by the coordinator.
- **Outward entries.** They are posted with the same marker, author check and text
  checks as today. A retry is keyed by the session entry's number and its
  `record/posted/<n>`; its fallback counts only comments by authors with write
  access created at or after the entry's stamp, so neither an earlier identical
  comment nor one a reader without write access posts can stand in for it.
  Nothing is ever deleted.

## Consequences

### Positive

- One reader for the state, and a removal of the GitHub record that deletes a
  backend.
- A crashed coordinator resumes its own run; a moved one continues through the
  gate with no handoff file.
- Every leg has a defined end after a move, and a vanished worker is recovered
  through the loop on either source.
- Existing records and their outside readers are untouched.

### Negative

- A write to the session store is several koto calls, and a crash between them can
  leave a section newer than `record/meta`.
- A moved coordinator's holdings and decisions are read on its host.
- The seam's release adds a structure test that fails on any new direct parse,
  which future scripts have to respect.

### Mitigations

- The next write's compare refuses once and the coordinator re-reads; the state is
  never a mix within a section. Proposed to koto as a feature: a batch
  `koto context add` that writes several keys as one change, and an append-only
  key stream for the account.
- `record-source.sh --show` prints the whole state as a record body, and koto's
  session view shows the keys.
- The structure test names the seam in its refusal.

## Amendment — 2026-10-23

`DESIGN-coordinator-record-teardown.md` removes the GitHub coordinator
record. The original text above is left unedited; this section records
what no longer holds.

The GitHub backend this design keeps beside the session is removed, and so is
the store choice (Decision 2): every coordinator runs on its session, and
`state-stored-set.sh` refuses a `store` Run key. The moved shape of a
session-source coordinator's GitHub record (Decision 10) and the move of an
existing record (Decision 11) go with it; a record nobody moved is imported
once by the legacy importer instead. Discipline scope, which this design left
on the GitHub record, runs on the session.

The coordinate scripts named above have new names: `record-append.sh` is
`state-entry.sh`, `record-common.sh` is `state-common.sh`, `record-confirm.sh`
is `state-confirm.sh`, `record-decision.sh` is `state-decision.sh`,
`record-find.sh` is `state-find.sh`, `record-handover.sh` is
`state-handover.sh`, `record-hold.sh` is `state-hold.sh`, `record-holding.sh`
is `state-holding.sh`, `record-open.sh` is `state-open.sh`, `record-source.sh`
is `state-read.sh`, `record-write.sh` is `state-write.sh` and
`record-write-core.sh` is `state-write-core.sh`. `record-parse.sh` and
`record-render.sh` are gone. `record-codec.jq` is gone; its checks live in
`state-schema.jq`, which validates the state as JSON.
