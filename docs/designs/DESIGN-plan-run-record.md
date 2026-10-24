---
schema: design/v1
status: Planned
problem: |
  A merged PR gives a reader a repository and a number, and nothing in shirabe gets from
  that to the koto session that ran the plan. PR text can't carry the pointer by default,
  koto files a cloud session under a hash of the workspace path it ran in so a fresh
  workspace can't see it, the run's sessions don't hold the plan per step, departures or
  decision actors, nothing pins them, and `/execute` still stamps a hidden marker on every
  PR. The documentation disagrees about whether a finished PLAN is deleted.
decision: |
  Each run writes a small trail of keys into its own sessions (`trail/` area, one writer
  script) and one index session per PR at a shared store address, so a lookup script
  turns `owner/repo#n` into the record root's workspace and name and from there into the
  run's PRs and step sessions. Reaching another workspace's sessions needs one new koto
  capability, a read-only `--workspace` option (koto#455); writes to the shared address run
  from a fixed directory, and until the option ships reads run from the addressed
  directories, which works on the run's own host. A pin step
  before each qualifying terminal pins the record root, step sessions and index sessions
  through koto's session pin. The marker goes, ownership reads the index, an opt-in
  reference goes in Part 2 under `include`, and the switch is recorded at each opener.
rationale: |
  The index is the only lookup that works for single-pr, coordinated and multi-pr runs
  without PR text, and putting it in the store keeps it out of the repository. Asking koto
  for workspace addressing, rather than hashing a fixed path inside shirabe, keeps shirabe
  off koto's internal layout. Writing the trail into the sessions that already hold each
  step's proof, rather than copying it into a separate record, gives one account. Pinning
  through koto's pin, per session and after the last child tick, meets every removal
  without a shirabe retention rule and without touching the pin's design.
upstream: docs/prds/PRD-plan-run-record.md
decision_provenance: inline-resolved
---

# DESIGN: A plan's run outlives the plan as its record

## Status

Planned

## Context and Problem Statement

The upstream PRD (`docs/prds/PRD-plan-run-record.md`) asks that a reader holding only a
merged PR's repository and number reach the koto session that ran its plan, read the plan
as each step began, each step's proof, each departure and each decision with its actor, and
get from that session to every PR the plan produced. It must work from a fresh workspace
after the run's niwa instance is reaped. The sessions holding that evidence must survive
every koto removal through koto's session pin. PRs must carry no workflow content unless
the repository opted in. The technical problem has five parts.

**There's no address.** koto's cloud backend files each session under
`<first 16 hex of sha256(canonical cwd)>/<name>/`, with no override. A shirabe run's cwd is
a niwa worktree path specific to the host, the user and the instance. `koto session list`
and `koto context get` see only the current path's prefix. The one command that crosses
prefixes, `koto session import`, migrates the session and marks the original inert, so it
can't serve as a read. A reader in a fresh workspace can name nothing, and the name alone
isn't enough even when known: a re-run's `--replace-terminal` moves a kept predecessor to
`<name>_r<N>`.

**There's no lookup.** Nothing maps a PR to its run outside the PR's text. The head branch
fails for adopted branches (`/execute` adopts `/scope`'s `docs/<topic>`), can't be split for
coordinated nodes (`impl/<slug>-<node>`, both kebab-case) and carries no slug for multi-pr
(`feature/<N>-<desc>`). The hidden `<!-- shirabe-run: <id> -->` marker that `run-id.sh`
stamps on every `/execute` PR names the run but not its record, and it breaks the PR
default, which since #1124 keeps workflow content out of PR text unless
`scripts/pr-workflow-content.sh` prints `include`.

**The sessions don't hold the record.** Single-pr and coordinated runs have a root
`execute-<topic>`. Single-pr children are koto-materialized (`execute-<topic>.o-<step>`),
and coordinated children are separate `/work-on` sessions (`work-on-<slug>-<node>-<item>`)
tied to the root by a dispatched-by link. A multi-pr plan has no plan-level session: each
item runs as its own `issue_<N>` root in its own instance. Nothing records the PLAN as each
step began. `step_refine/<step>.md` holds steps 2 onward of a single-pr run, as new text with
no reason. Departures exist only as prose rows in `summary.md`. `koto decisions record` takes
`choice` and `rationale` and has no actor field. The PR list is `home_pr` for single-pr,
`run/node/*` and `run/follow-up/*` for coordinated, and nothing for multi-pr.

**Nothing keeps it.** koto keeps a finished session while its hierarchy is alive and then for
`retention.keep` (7 days by default), after which any prune at that workspace path removes
it from the bucket. koto's session pin (koto#441, specified in koto#444) keeps a pinned
session through the terminal tick, the parent sweep, the same-name replace and both prunes,
refuses `koto session cleanup` and `koto cancel --cleanup`, and keeps a pinned child after
its parent goes. It pins one session per call, and no niwa or shirabe state is involved.

**The documentation disagrees.** `skills/plan/references/plan-format.md` says the PLAN
"stays in `docs/plans/` through every state" and calls `Done` terminal.
`skills/roadmap/references/roadmap-format.md` calls a Done roadmap "a historical record".
The planning skill, `plan-doc-structure.md`, the roadmap skill, `references/pipeline-model.md`
and the cascade (`skills/work-on/scripts/run-cascade.sh`) all delete them, and the lifecycle
check (`crates/shirabe-validate/src/lifecycle.rs`, rule `L01`) fails a committed PLAN or
ROADMAP at `Done`.

## Decision Drivers

- **No PR text by default (PRD R1, R19, R20).** The lookup reads nothing from GitHub, and
  ownership can't rest on a marker in the body.
- **Any workspace, read-only (R3, R6).** Every read must leave the record as it is: no
  import, no migration marker, no write.
- **Retention is koto's (R12-R15).** shirabe pins through the pin's commands and adds no
  keep rule; it never unpins; nothing here may require a change to the pin's design.
- **All three plan modes (R2, R7).** A single-pr, a coordinated and a multi-pr run each get
  one record root and a complete PR list.
- **One writer per fact.** The coordinated `run/` keys already follow it through
  `run-record.sh`. New keys get the same discipline.
- **Works before koto ships K1 and K2 (R17).** shirabe must keep running on today's koto,
  with the new behaviour proved against a stub.
- **Nothing under `skills/coordinate/` (R27).** Another effort is renaming scripts there.
- **Bash 3.2, no new dependencies (R28), bounded reads (R29)**, and koto's per-read cost
  (one bucket listing per read, koto#439 and #446) makes the bound matter.

## Considered Options

### Decision 1: How a PR leads to its run's record, and how a fresh workspace reads it

Resolved inline.

A reader has `owner/repo#n` and nothing else. The question is where the mapping from that
pair to the run's record root lives, and how any workspace reaches both the mapping and the
root.

Key assumptions:
- koto will accept, as its own change, a way to address another workspace's sessions.
  If it doesn't, the shirabe side still works from the run's own workspace path.
- PR numbers aren't reused within a repository.

#### Chosen: an index session per PR at a shared address, reached through a koto workspace option

Each run writes, when it first records a PR (at open or adoption), one key into the index
session for that PR: session `pr.<owner>.<repo>.<n>` (lowercased; owners can't contain a
dot and the number is last, so the name decodes uniquely), key `run/<run_id>`, holding the
record root's address. The address is the workspace path the root was created in, its
session name and its koto `session_id`. The owner is held to GitHub's owner grammar
(`^[A-Za-z0-9](-?[A-Za-z0-9])*$`, lowercased) and the repository to `^[A-Za-z0-9._-]+$`,
`.` and `..` excluded, before either reaches a name or an address. The index session lives at
a shared store address, one per repository owner: the koto workspace of the fixed directory
`/tmp/shirabe-run-record/<owner>`. A multi-pr plan's record root lives there too.

koto addresses a workspace by its canonical working directory (the first 16 hex digits of the
SHA-256 of the canonicalized cwd). So every write to the shared address is an ordinary koto
call whose working directory is that fixed directory, which `record-store.sh` creates and
enters in a subshell. No write passes any address option. The directory's canonical form is
`/tmp/shirabe-run-record/<owner>` on Linux and `/private/tmp/shirabe-run-record/<owner>` on
macOS, so the shared address is one per operating system family, and a reader tries both.

The fixed directory is an interim. It works with koto as it stands, but it ties the address
to how koto canonicalizes a working directory, which is koto's internal detail rather than a
contract. The lasting answer is a named, writable workspace for the index, which is koto's to
offer and is proposed as tsukumogami/koto#456, separate from the read-only option. When it
lands, `record-store.sh` switches to it and the directory goes, as one
change: nothing outside that file and its test knows the address. The writer creates the
directory before each call, since `/tmp` may be cleared between runs.

Reading an address other than the cwd's from another workspace needs one koto capability,
named K2 in the PRD, now proposed to koto as koto#455: a global `--workspace <id>` option
that koto's read verbs (`status`, `context get`, `context list`, the session listing) accept,
and its write and removal verbs refuse. shirabe doesn't build it. Reads through it keep no
local copy and write nothing into the read session. Because K2 is read-only, the index can't
be written by address, which is why the shared address is a working directory rather than an
identifier.

What a reader with the cloud store's credentials and GitHub reaches, before and after K2:

| From | Before K2 | After K2 |
|---|---|---|
| The run's own host | the index (read from the fixed directory), the root and every step session from the run's workspace path | the same, from any directory |
| Any other workspace, fresh or not, on another host | nothing reliable | the index, the root, every step session in any workspace, the multi-pr plan root |
| GitHub alone, without store credentials | nothing about the run | nothing about the run |

All shirabe code touches K2 through one file, `scripts/lib/record-store.sh`. It decides
the address and how to reach it. A read checks once per process whether the installed koto
accepts `--workspace` on a read verb (it probes koto's own help for the option, never a
version table). When it does, the read passes `--workspace` with the recorded address. When
it doesn't, the read falls back to running koto from that address's directory: the fixed
directory for the index and the multi-pr root, and the root's recorded workspace path for the
record root and its step sessions. On today's koto that fallback works on the run's own host,
and `record-store_test.sh` covers both paths against the stub koto, with and without the
option.

The lookup, `scripts/run-record-lookup.sh <owner/repo> <n>`, reads the index session
(1 read), takes the entry with the latest `written_at` (ties broken by `run_id`; the field is
the writer's clock, so it orders entries but proves nothing), reads the root's PR list and step list (2 reads at
most), and confirms the PR is in the root's own list. Every value it reads back is checked against
the same closed patterns the writer used, and one that fails is reported in `missing`. When the root's `session_id`
doesn't match, it checks `<name>_r1` up to `<name>_r10` for a matching `session_id`
(1 read each). The bound is 2 + P + S reads, where P is the run's PR count and S its step
count, plus 1 per predecessor checked.

#### Alternatives Considered

- **Derive the run from the PR's head branch.** Rejected: it fails for adopted branches,
  coordinated node branches and every multi-pr branch, and it still needs the workspace path.
- **Index at a fixed absolute path that shirabe creates and `cd`s into.** It works on
  today's koto, but the canonical path differs across operating systems (`/tmp` resolves to
  `/private/tmp` on macOS), it collides with same-named local sessions in koto's flat local
  store, and it ties shirabe to koto's prefix rule. Rejected in favour of asking koto.
- **A koto-side search by key or attribute.** It would serve more than shirabe, but it's a
  larger koto design (an index over every session in a bucket) for a need one index session
  per PR meets. Rejected.
- **A git ref or note in the repository.** It reaches a fresh clone, but it writes workflow
  content into the repository by default, against the same rule that keeps it out of PRs.
  Rejected.

### Decision 2: What the record holds and where it's written

Resolved inline.

The PRD asks for the PLAN as each step began, each step's proof, each departure against its
step and each decision with an actor, in every mode, readable from the root by name.

Key assumptions:
- A step's proof stays where `/work-on` writes it today (`summary.md`,
  `verification_results.json`, `review_results.json`). Copying it would make two accounts.
- koto may drop unknown fields from `koto decisions record --with-data`, so the actor can't
  live only there.

#### Chosen: a `trail/` key area in the sessions that already hold the evidence, one writer script

A new session area, `trail/`, is added to `references/skill-session-convention.md`. All
writes go through `scripts/run-trail.sh`, whose verbs each own fixed keys and validate
every value (step ids against `^[A-Za-z0-9][A-Za-z0-9._-]*$`, kinds against a closed set).
Free text never arrives as a shell argument or a file path: `departure` and `decision` read
one JSON document on stdin, and `plan` reads only the path `--plan` names, which must match
`^docs/plans/PLAN-[a-z0-9-]+\.md$`, through `git show HEAD:<path>`. Each text field is capped
at 16 KiB and the PLAN at 256 KiB, and a value holding a private-key header, an
`Authorization:` line or a common token shape (`ghp_`, `github_pat_`, `AKIA`, `xoxb-`) is
refused with exit 65 before anything is written, the copy `decision` sends through
`koto decisions record` included:

| Verb | Session | Keys |
|------|---------|------|
| `pr` | record root | `trail/pr/<owner>.<repo>.<n>`: `{repo, number, role, state, recorded_at}` |
| `plan` | record root (multi-pr: the item session) | `trail/plan/<step>.md` (the PLAN's full text from `git show HEAD:<plan>`), `trail/plan/<step>.json`: `{sha, entry, recorded_at}` |
| `step` | record root | `trail/step/<step>`: `{session, workspace, superseded: [names]}` |
| `departure` | the session where it happened | `trail/departure/<n>.json`: `{step, kind, what, why, at}` |
| `decision` | the session where it happened | `trail/decision/<n>.json`: `{step, actor, choice, rationale, at}`, plus the same choice and rationale through `koto decisions record` |
| `item` | multi-pr plan root | `trail/item/<step>`: `{session, workspace, pr}` |
| `index` | the PR's index session | `run/<run_id>`: `{workspace, session, session_id, mode, topic, written_at}` |
| `self` | record root, called once by the opener | `trail/self`: `{workspace, session, session_id, run_id}` |

`trail/unpinned` has one writer too: `run-record-pin.sh`, which writes it after a pin attempt
and removes it once every session it names is pinned.

Departure kinds are `deviated`, `deferral`, `scope-change` and `entry-rewritten`. The actor
is `agent:<anchor or session name>` or `person`, with `person:<login>` when the gate
recorded a login. Steps are keyed by the id `plan-to-tasks.sh` already gives them
(`issue-<N>` for plan/v1, `step-<N>` for plan/v2).

The writes happen where the fact arises:
- **Plan snapshot.** Single-pr: in `spawn_and_await`'s lead shape, before each step agent
  starts, step 1 included. The entry rewrite also records an `entry-rewritten` departure in
  the root. Coordinated: before each `dispatch:<node>` hand-off. Multi-pr: at the item's
  start in `/work-on`.
- **Step session.** Recorded by the owning session at hand-off, and rewritten with the
  earlier name moved to `superseded` when a step gets a new step agent.
- **Departures and decisions.** In `/work-on`, at the sites that already record them: the
  deviated-criterion rows at finalization, the deferral approval, `scope_changed_retry`, and
  every `koto decisions record` call, which now goes through `run-trail.sh decision`.
- **PRs.** Where the run already records a PR (`adopt-or-create-pr.sh`, `node-push.sh`,
  `record-coord-setup.sh` for follow-ups, `/work-on`'s PR creation for multi-pr), and again
  where it observes a state change (ready in `plan_completion`, merged in `merge_confirm`).

The coordinated opener already carries `run/` keys across a pause's replace. The same carry
is extended to `trail/` in `execute-open.sh` for both templates, so a pause never drops the
trail.

#### Alternatives Considered

- **Copy everything into one record session at the end.** Rejected: two accounts that can
  drift, a copy step that can fail after the run is gone, and a size problem for the PLAN
  texts.
- **Extend the coordinated `run/` namespace to all modes.** `run-record.sh` and its key
  grammar are built for the coordinated record and its recovery. Bending them to single-pr
  and multi-pr widens a reader that every coordinated script relies on. Rejected.
- **Record decisions only through `koto decisions record`.** It has no actor field, and
  adding one is a koto change this need doesn't justify. Rejected.

### Decision 3: Which sessions are pinned, when, with what reason, and who releases

Resolved inline.

Key assumptions:
- koto's pin ships as koto#444 specifies, and its first release is unknown today.
- A pin set after a run's last child tick can't be lost to a batch respawn.

#### Chosen: one pin step before every qualifying terminal, a fixed reason, release left to koto

`scripts/run-record-pin.sh --root <session>` pins, one `koto session pin` call each, the
record root, every step session named in `trail/step/*` (never one in `superseded`), and
every index session the run wrote. It decides what belongs to this run from local facts, not from
bucket-read names alone. A step session is pinned only when it's the root's own koto child
(`koto workflows --children <root>`) or its dispatched-by link names the root
(`koto session hierarchy`), both read on the run's own host. An index or plan session is
pinned only when it holds a `run/<run_id>` or `trail/item/*` entry for this run. Addresses come
from the run's own open-time record (`trail/self`, written by the opener with the workspace and
`session_id`), never from a workspace value read back from the bucket. At most S + P + 1 pins
are made per run, and any other name it's handed is skipped and reported. Before K2, a step
session created in a workspace other than the root's can't be reached to pin, and it's reported
in `trail/unpinned` with the reason `other-workspace`, never skipped silently. shirabe can't reverse
a pin it sets. A multi-pr item pins the plan root (a repeat pin is
idempotent), its own session and its index session. The reason is
`record of plan <topic>: <owner>/<repo>#<n>`, with the topic truncated so the whole stays
within 500 characters. It never holds plan prose.

It runs in a new state in each template, which every route into a qualifying terminal passes
through:
- `skills/execute/koto-templates/execute.md`: `record_keep`, before `merged` and
  `ready_awaiting_merge`.
- `skills/execute/koto-templates/execute-coordinated.md`: `record_keep`, before `merged`
  and `ready_awaiting_merge`. `paused_awaiting_merges` doesn't qualify, since not every PR
  is ready.
- `skills/work-on/koto-templates/work-on.md`: `record_keep`, before `done`, only for a
  top-level multi-pr item run whose PR is ready or merged. A plan-backed child skips it, as
  its parent pins it.

The state is a default action that never blocks the terminal. Any pin koto refuses (exit 2)
or can't confirm (exit 3) is written to the root's `trail/unpinned` key with koto's error
code. The terminal's `result:` carries `record: unpinned` and the list. The next invocation's
opener reruns `run-record-pin.sh --retry`, which takes the names from that key and puts each
through the same local provenance check as a first attempt before pinning it. The pin has two floors in
`run-record-pin.sh`, because koto ships it in two parts. `RECORD_PIN_FLOOR` is the release
carrying koto#444 (pin and unpin, the engine reading the pin, prune keeping pinned sessions,
one removal guard at every removal point, the reporting surfaces and unreadable pins, and the
start hook recording authority). Below it, or while it's unset, no `koto session pin` call is
made and the result says `record: unpinned`. `RECORD_PIN_CLOUD_FLOOR` is the release carrying
the pin's cloud follow-up (the bucket check before every delete, keeping across hosts, and
pins travelling with import). Under the cloud backend, a run on a koto at or above the first
floor but below the second pins as usual and its result says `record: pinned-local`: removals
on its own host keep the sessions, but a removal on another host sharing the bucket isn't yet
held to the pin.

shirabe never calls `koto session unpin`. A pin comes off by hand, or from an agent session
whose start was handed koto's `release-pin` authority, as koto's pin defines.
`references/koto-session-retention.md` says which sessions shirabe pins and how to release
them.

#### Alternatives Considered

- **Pin when the merge is observed.** Rejected: `/execute` without `--merge` stops at a ready
  PR and a person merges later, when nothing of shirabe's is running.
- **Pin each child at its own terminal.** Rejected: a batch child pinned while its parent can
  still respawn it can lose the pin, as koto's pin design notes.
- **A shirabe retention window on top of the pin.** It would let shirabe keep records on a koto
  without the pin, but every removal koto applies would need a second, shirabe-side guard, and
  koto's prune and cleanup on another host never consult one, so it couldn't keep anything
  there. The PRD rules it out for that reason: retention is koto's.

### Decision 4: What PRs carry, how ownership works without the marker, and how the switch is read

Resolved inline.

Key assumptions:
- The squash commit takes Part 1 only (`scripts/lib/squash-message.sh`), so Part 2 never
  reaches the default branch.
- niwa writes `CLAUDE.local.md` into each worktree from the workspace config, which is how a
  workspace opts a repository in.

#### Chosen: drop the marker everywhere, own PRs through the index, record the switch at each opener

- **No marker.** `run-id.sh` keeps `mint`, `get`, `seed` and `adopt`, and loses `stamp`,
  `restamp`, `carry` and `marker`. No writer stamps a body.
- **Ownership.** `owned-pr.sh --run-id` keeps its five checks (same repository, the
  authenticated author, the expected base, the head branch, the state) as required for every
  survivor, and the index can only take a PR away: a candidate whose latest index entry names
  another run is foreign, and every other candidate that passed the five checks survives,
  whether its entry names this run or it has none. A planted entry can't make a PR this run's. `--take-over` writes this run's index entry instead of
  restamping. `record-coord-setup.sh` recovery reads run identity from the index and the
  carried `run_id`, never from markers.
- **How it's turned on.** A repository opts in with the header
  `## PR Workflow Content: include` in its `CLAUDE.local.md`, which niwa writes into each
  worktree from the workspace configuration (the repository's content file in the workspace's
  config repo), or in its own `CLAUDE.md`. With no header, or any value but `include`, the
  reader prints `omit`: the integration is off by default.
- **The switch, recorded.** `scripts/pr-workflow-content.sh` gains `--record <session>`,
  which reads the header from the checkout once and stores `include` or `omit` as key
  `pr_content` in that session, and `--session <session>`, which prints the recorded value,
  falling back to the files only when the key is absent. Only exit 0 with `include` counts.
  `execute-open.sh`, `work-on-open.sh`, `scope-open.sh` and `deliver-open.sh` call
  `--record` once per invocation. Every PR writer reads `--session`. A plan-backed child
  reads its parent's key. So an invocation started after the header is turned off records
  `omit` and writes no session reference. A PR body it rewrites loses an earlier Part 2
  reference, and a PR it doesn't touch keeps what it had.
- **No step posts a record.** No teardown, cleanup, cascade or reporting step posts a run
  record, a pin result or a cost entry to a public pull request, as a comment or in its text.
  Under omit that holds for every repository; `result:` text, `trail/unpinned` and any cost
  figure stay in the session.
- **Under omit,** a PR body is its plain description and verification. That holds for
  coordinated bodies too. `coord-render.sh` renders Part 1 alone, with no run lines, PR index
  or merge-order block. `node-push.sh` writes the node body without the deferral section,
  whose gate takes the session's `verification_deferral` key, as it already does under omit
  for other PRs. A coordinated run under omit seals `store: session`, since recovery from the
  body needs a body that carries the record. `check-pr-output.sh --pr-body` refuses
  `shirabe-run`, run lines and PR index lines under omit.
- **Under include,** every PR the run opens, and every body it rewrites, gets one Part 2
  line, `Run record: <record root session> (run <run_id>)`. It never goes in the title or
  Part 1.

The checkout limit stays: `pr-workflow-content.sh` reads files, so an opener outside a
checkout records `omit`, and README.md says so. A checkout-free source is #1130's subject,
not this design's.

#### Alternatives Considered

- **Keep the marker as a named exception.** Rejected: it's workflow content by default, which
  the PRD rules out.
- **Read the switch at every write.** That's today's behaviour, and it flips mid-run when a
  step runs without a checkout. Rejected.
- **Read the switch once at the run's first open and carry it.** Rejected: a resumed run
  would keep writing references after the option was turned off.

## Decision Outcome

The four decisions meet in the record root. The run writes its trail into the sessions that
already hold each step's proof (Decision 2). It writes one index entry per PR at a shared
address (Decision 1), and that entry is also what tells two runs' PRs apart once the marker
is gone (Decision 4). Before its qualifying terminal it pins exactly the sessions the trail
and the index name (Decision 3). A reader runs `run-record-lookup.sh owner/repo n` anywhere
on the bucket: it reads the index entry, confirms the PR in the root's `trail/pr/*`, and
lists PRs and step sessions. The reader then reads `trail/plan/*`, `trail/departure/*`,
`trail/decision/*` and each step session's proof keys with ordinary `koto context get`
through the same address. PR text carries nothing unless the recorded `pr_content` is
`include`, and then only one Part 2 line.

Cross-validation found one coupling. Decision 4's ownership check reads the index on every
`owned-pr.sh --run-id` call, so Decision 1's index must be written before the first
ownership lookup that could see the PR again. Every writer records the index entry in the
same step that records the PR, before any later lookup, which settles it.

Three things wait on koto. K1, the pin, ships in two parts. koto#444's release lets
shirabe pin and keeps pinned sessions through every removal on the host that reads the pin;
until then `RECORD_PIN_FLOOR` is unset and runs report `record: unpinned`. The pin's cloud
follow-up, a later koto PR, adds the bucket check before every delete, keeping across hosts and
import; until it ships `RECORD_PIN_CLOUD_FLOOR` is unset and a cloud-backed run reports
`record: pinned-local`. K2, the read-only workspace option, is koto#455, built outside this
change: until it lands, the index and the multi-pr root are written at the fixed directory as
always, and a lookup reads them, the root and its step sessions by running koto from their
directories, which works on the run's own host.

## Solution Architecture

### Overview

The record is three kinds of session: the record root (`execute-<topic>`, or the multi-pr
plan root `plan.<owner>.<repo>.<topic>.<sha12>` at the shared address), its step sessions,
and one index session per PR at the shared address. Four new scripts write, read and keep
them, and every existing writer of PR text or decisions calls them at the point the fact
arises.

### Components

New files:

- `scripts/lib/record-store.sh` (sourced): `rs_shared_dir <owner>` returns the fixed
  directory for the shared address. `rs_koto_write <dir> <koto args>` runs a koto write from
  that directory. `rs_koto_read <dir> <koto args>` runs a koto read, passing `--workspace`
  when `rs_has_workspace_option` finds the installed koto accepts it on a read verb, and
  otherwise running from the directory (for the shared address, each canonical form in turn).
  `rs_index_name <owner/repo> <n>` and `rs_plan_root_name` return names. It's the only file
  that knows about koto's `--workspace`.
- `scripts/run-trail.sh`: the one writer of `trail/` keys and index entries (verbs in
  Decision 2). Exit 0 written, 64 usage, 65 a value its verb refuses, 70 a koto write failed.
- `scripts/run-record-lookup.sh <owner/repo> <n> [--steps]`: R1 and R2. JSON on stdout,
  `{record_root: {workspace, session}, run_id, complete, unique, missing: [], prs: [{repo,
  number, state}], others: [run_id], steps: [...]}`. Exits 0, 3 (no index entry), 2 (read failure),
  64 (malformed input).
- `scripts/run-record-pin.sh --root <session> [--retry]`: R12-R17 (Decision 3).
- `scripts/testdata/record-koto/koto`: the stub koto. It implements the pin as koto#444's PRD
  specifies (pin, unpin, `kept_by_pin`, prune past retention, exit codes 2 and 3 on demand),
  K2's `--workspace`, today's context, decision and status commands, and a call log.
- Tests: `scripts/run-trail_test.sh`, `scripts/run-record-lookup_test.sh`,
  `scripts/run-record-pin_test.sh`, `scripts/record-store_test.sh`, and
  `scripts/check-run-record-rules.sh` with its `_test.sh`. The rules check fails on any
  `koto session unpin` call, any retention window defined in shirabe, any cleanup instruction
  whose paragraph doesn't say "pinned", and any diff under `skills/coordinate/`.
- `scripts/bash-floor/run-record.list` and `.github/workflows/check-run-record.yml`, which
  runs the suites on Linux and on the macOS bash 3.2 floor.

Modified files, by concern:

- **Lookup, index and ownership:** `skills/execute/scripts/adopt-or-create-pr.sh`,
  `skills/execute/scripts/node-push.sh`, `skills/execute/scripts/record-coord-setup.sh`,
  `skills/execute/scripts/owned-pr.sh`, `skills/execute/scripts/run-id.sh`,
  `skills/execute/scripts/coord-render.sh`, `scripts/lib/coordination-body.sh`.
- **Trail writes:** `skills/execute/koto-templates/execute.md`,
  `skills/execute/koto-templates/execute-coordinated.md`,
  `skills/execute/scripts/execute-open.sh` (the `trail/` carry and pin retry),
  `skills/execute/references/step-agent-handoff.md`,
  `skills/work-on/koto-templates/work-on.md`, `skills/work-on/SKILL.md`,
  `skills/work-on/references/phases/phase-3-analysis.md`,
  `skills/work-on/references/phases/phase-4-implementation.md`,
  `skills/work-on/references/phases/phase-5-finalization.md`,
  `skills/work-on/references/phases/phase-6-pr.md`, `scripts/rule-dispute.sh`.
- **The switch:** `scripts/pr-workflow-content.sh` and its test,
  `skills/execute/scripts/execute-open.sh`, `skills/work-on/scripts/work-on-open.sh`,
  `skills/scope/scripts/scope-open.sh`, `skills/scope/scripts/publish-scoping-pr.sh`,
  `skills/deliver/scripts/deliver-open.sh`, `skills/work-on/scripts/check-pr-output.sh`,
  `skills/work-on/scripts/run-cascade.sh` (its commit message reads the recorded value).
- **Tool declarations:** `skills/execute/requires.tsv`, `skills/work-on/requires.tsv`
  (`koto session pin`).
- **Documentation:** `skills/plan/references/plan-format.md`, `skills/plan/SKILL.md`,
  `skills/plan/references/quality/plan-doc-structure.md`,
  `skills/roadmap/references/roadmap-format.md`, `skills/roadmap/SKILL.md`,
  `references/pipeline-model.md`, the header of `skills/work-on/scripts/run-cascade.sh`,
  `references/koto-session-retention.md`, `references/skill-session-convention.md`,
  `references/pr-body-conformance.md`, `references/decision-protocol.md`,
  `skills/execute/SKILL.md`, `README.md`.
- **Tests of modified scripts:** `adopt-or-create-pr_test.sh`, `node-push_test.sh`,
  `record-coord-setup_test.sh`, `owned-pr_test.sh`, `run-id_test.sh`, `coord-render_test.sh`,
  `execute-open_test.sh`, `execute-template-structure_test.sh` and `terminal-retention_test.sh`
  under `skills/execute/scripts/`; `work-on-open_test.sh`, `check-pr-output_test.sh` and
  `run-cascade_test.sh` under `skills/work-on/scripts/`; `scope-open_test.sh` and
  `publish-scoping-pr_test.sh` under `skills/scope/scripts/`; `deliver-open_test.sh` under
  `skills/deliver/scripts/`; and `scripts/pr-workflow-content_test.sh` and
  `scripts/rule-dispute_test.sh`.

No file under `skills/coordinate/` is on the list. Its `land-merge.sh` uses the shared squash
builder, which already takes Part 1 only. Its `roadmap-status.sh` opens a status-only ROADMAP
PR outside any plan run and writes no record. Neither changes.

### Key Interfaces

```text
run-trail.sh pr        --session S --repo owner/repo --number N --role home|node|follow-up|coordination|item --state open|ready|merged|closed
run-trail.sh plan      --session S --step ID --plan docs/plans/PLAN-<topic>.md
run-trail.sh step      --session S --step ID --child NAME [--supersede]
run-trail.sh departure --session S --step ID --kind deviated|deferral|scope-change|entry-rewritten   < {"what": ..., "why": ...}
run-trail.sh decision  --session S --step ID --actor agent:NAME|person[:LOGIN]   < {"choice": ..., "rationale": ..., "alternatives_considered": [...]}
run-trail.sh item      --plan-root NAME --step ID --child NAME --repo owner/repo --number N
run-trail.sh index     --repo owner/repo --number N --session S --mode single-pr|coordinated|multi-pr --topic T

run-record-lookup.sh owner/repo N [--steps]     exit 0 | 3 | 2 | 64
run-record-pin.sh --root S [--retry]            exit 0 always once it ran; result in trail/unpinned
pr-workflow-content.sh --record S | --session S | [<dir>]
```

The record root's address is `{workspace, session, session_id}`, where `workspace` is
`pwd -P` of the checkout at the run's open and `session_id` comes from koto's session list
row. Index names are `pr.<owner>.<repo>.<n>`. The multi-pr plan root is
`plan.<owner>.<repo>.<topic>.<sha12>`, where `sha12` is the commit that added the PLAN to
the default branch, so a topic reused by a later plan gets a new root. Index and plan-root
sessions are opened from `koto-templates/skill-session.md` and never ticked.

### Data Flow

A single-pr run. `execute-open.sh` mints `run_id`, records `pr_content`, carries `trail/` from
a replaced predecessor and retries any `trail/unpinned` pins.
`adopt-or-create-pr.sh` creates or adopts the home PR, then calls `run-trail.sh pr` and
`run-trail.sh index`. `spawn_and_await` calls `run-trail.sh plan` and `run-trail.sh step`
before each step agent. Each `/work-on` child records departures and decisions in its own
session through `run-trail.sh`. `plan_completion` records the PR `ready`, and `merge_confirm`
records it `merged`. `record_keep` runs `run-record-pin.sh`, and the run reaches `merged` or
`ready_awaiting_merge`.

A coordinated run does the same per node, follow-up and coordination PR, records the plan
snapshot before each `dispatch:<node>`, and pins at its `record_keep`. A multi-pr item run
finds or creates the plan root at the shared address, writes its `item`, `plan`, `pr` and
`index` entries, and pins at its own `record_keep`.

A reader runs `run-record-lookup.sh owner/repo n`. It reads `pr.<owner>.<repo>.<n>` at the
shared address, picks the latest `run/<run_id>` entry, reads the root's `trail/pr/*` (and
for multi-pr `trail/item/*`), confirms the PR, and prints the JSON. With `--steps` it adds
each `trail/step/*` and `trail/plan/*.json`. Every read goes through `rs_koto`, so it addresses
the right prefix and writes nothing.

## Implementation Approach

### Phase 1: The walking skeleton, single-pr lookup

Build `record-store.sh`, the stub koto, `run-trail.sh` (`pr` and `index`), and
`run-record-lookup.sh`, and call `pr` and `index` from `adopt-or-create-pr.sh`. A test
creates a single-pr run's root and home PR against the stub and looks it up from a fresh
directory.

Deliverables: `scripts/lib/record-store.sh`, `scripts/run-trail.sh`,
`scripts/run-record-lookup.sh`, `scripts/testdata/record-koto/koto`,
`scripts/record-store_test.sh`, `scripts/run-trail_test.sh`,
`scripts/run-record-lookup_test.sh`, `skills/execute/scripts/adopt-or-create-pr.sh` and its
test, `skills/execute/scripts/execute-open.sh` (the `trail/self` record) and its test,
`scripts/bash-floor/run-record.list`, `.github/workflows/check-run-record.yml`.

### Phase 2: The trail per step

Add `plan`, `step`, `departure` and `decision`, the hooks in `execute.md`'s lead shape and in
`/work-on`'s decision, deviation, deferral and scope-change sites, and the `trail/` carry in
`execute-open.sh`.

Deliverables: `scripts/run-trail.sh` and its test, `scripts/run-record-lookup.sh` (`--steps`),
`skills/execute/koto-templates/execute.md`, `skills/execute/scripts/execute-open.sh` and its
test, `skills/execute/scripts/execute-template-structure_test.sh`,
`skills/work-on/koto-templates/work-on.md`, `skills/work-on/SKILL.md`,
`skills/work-on/references/phases/phase-3-analysis.md`,
`skills/work-on/references/phases/phase-4-implementation.md`,
`skills/work-on/references/phases/phase-5-finalization.md`, and `scripts/rule-dispute.sh`,
whose `by=` actor moves into the decision record, with its test.

### Phase 3: Coordinated and multi-pr records

Index and trail writes in `node-push.sh` and `record-coord-setup.sh`, coordinated hand-off
snapshots, the multi-pr plan root and `item` verb, and the lookup's coordinated and multi-pr
branches.

Deliverables: `skills/execute/scripts/node-push.sh` and
`skills/execute/scripts/record-coord-setup.sh` with their tests,
`skills/execute/koto-templates/execute-coordinated.md`,
`skills/execute/references/step-agent-handoff.md`,
`skills/work-on/references/phases/phase-6-pr.md`, `skills/work-on/koto-templates/work-on.md`
(the multi-pr item start), and `scripts/run-trail.sh` (`item`) and
`scripts/run-record-lookup.sh` with their tests.

### Phase 4: Pins

`run-record-pin.sh`, the `record_keep` states in the three templates, `trail/unpinned` and
the opener's retry, `requires.tsv` entries, and `check-run-record-rules.sh`.

Deliverables: `scripts/run-record-pin.sh`, `scripts/run-record-pin_test.sh`,
`scripts/check-run-record-rules.sh`, `scripts/check-run-record-rules_test.sh`, the three
templates, `skills/execute/scripts/execute-open.sh`, `skills/work-on/scripts/work-on-open.sh`
and their tests, `skills/execute/scripts/terminal-retention_test.sh`, `skills/execute/requires.tsv` and
`skills/work-on/requires.tsv`.

### Phase 5: PR content

Marker removal in `run-id.sh` and its callers, index-based ownership in `owned-pr.sh` and
`record-coord-setup.sh`, the recorded switch, omit-mode coordinated bodies, the Part 2
reference under include, and the `check-pr-output.sh` rules.

Deliverables: `skills/execute/scripts/run-id.sh`, `skills/execute/scripts/owned-pr.sh`,
`skills/execute/scripts/adopt-or-create-pr.sh`, `skills/execute/scripts/node-push.sh`,
`skills/execute/scripts/coord-render.sh`, `scripts/lib/coordination-body.sh`,
`skills/execute/scripts/record-coord-setup.sh`, `scripts/pr-workflow-content.sh`, the four
openers (`execute-open.sh`, `work-on-open.sh`, `scope-open.sh`, `deliver-open.sh`),
`skills/scope/scripts/publish-scoping-pr.sh`, `skills/work-on/scripts/check-pr-output.sh`,
`skills/work-on/scripts/run-cascade.sh`, `skills/execute/koto-templates/execute.md`
(`pr_finalization` stops carrying the marker), and the test beside each.

### Phase 6: Documentation

The lifecycle statement in the seven files, the retention reference, the session convention's
`trail/` area, `pr-body-conformance.md`, `decision-protocol.md`, the execute skill and the
README's checkout limit.

Deliverables: the seven lifecycle files listed under Components,
`references/koto-session-retention.md`, `references/skill-session-convention.md`,
`references/pr-body-conformance.md`, `references/decision-protocol.md`,
`skills/execute/SKILL.md`, `README.md`, and the rules check's lifecycle and retention greps.

### Outside this repository

- **K2 in koto.** The read-only `--workspace` option described in Decision 1 is koto#455,
  built outside this change. It doesn't change the pin's code or design. shirabe detects it by
  probing koto's help, so nothing in shirabe changes when it ships.
- **K1's two releases.** When koto releases koto#444, `RECORD_PIN_FLOOR` is set to that
  version, and the local-backend pin checks can also run against a real koto. When it releases
  the pin's cloud follow-up, `RECORD_PIN_CLOUD_FLOOR` is set to that version.
- **What waits on which.** Built and tested now against the stub, from the pin's PRD as
  written: everything. Proved against a real koto once koto#444 ships: pinning the record root,
  step and index sessions at `record_keep`, refusal and retry, `kept_by_pin` in a same-host
  prune, `koto session cleanup` refusing a pinned session, and the release routes. Proved only
  once the pin's cloud follow-up ships: a prune or cleanup on a second host keeping the
  sessions, a failed bucket check keeping them, and a pin surviving import.
- **The end-to-end walkthrough** from a fresh workspace on another host with no local copy,
  against a real koto and a real bucket, covering the lookup and a removal there, rests on K2
  and on the pin's cloud follow-up. It's done after they ship, not as part of this change.

## Security Considerations

**Trust model.** The bucket is the trust boundary. Anyone who can write to it can write index
entries, trail keys and sessions. The design adds no authentication to records. It makes
forgery visible and bounded, and a record is as trustworthy as the bucket's write access.

**Writes.** Untrusted text (PLAN entries, issue bodies, summaries, reports) is data.
`run-trail.sh` takes free text only as a JSON document on stdin, stores it through `jq`, caps
its size and refuses token and key shapes, and reads a PLAN only from a path matching
`docs/plans/PLAN-<topic>.md`, so it can't read an arbitrary file into the store. The secret
check is a backstop, not a guarantee: private-origin prose an agent writes into a public
repository's trail stays readable by the bucket's audience, a known residual. Step ids, session
names, repository names and numbers are checked against closed patterns before they reach a
koto command line, and each key has a size cap. The pin reason and the opt-in reference are
fixed templates over the topic (held to `^[a-z0-9-]+$`), the repository, the number, the
session name and the `run_id`. Neither carries plan prose.

**Reads.** Every value read back from the bucket (workspace, session, session id, step and item
names, superseded names, `trail/unpinned` entries) is checked again against the same closed
patterns before use. Values reach koto after `--` or as `--flag=value`, a workspace is treated
as an opaque identifier, and the lookup builds its JSON only through `jq --arg`. A value that
fails the check is reported in `missing` and never used.

**Shared index sessions.** A pinned `pr.<owner>.<repo>.<n>` session keeps every entry in it,
another run's or a forged one included, and shirabe can't remove them.
`references/koto-session-retention.md` documents the purge path: who holds koto's `release-pin`
authority in a workspace, and the by-hand `koto session unpin` that lets the next prune take a
session, so content that slipped past the secret check has a known way out.

**Lookup output.** The lookup's JSON holds names, ids, numbers, states and the workspace
path, never free text. The workspace names a user and an instance, so the skill text marks it
internal, not for pasting into PRs or issues. `--steps` adds step ids, session names and
commit SHAs only. Reading plan text, departures or rationales is a separate
`koto context get`, whose output is fenced and labelled untrusted wherever a skill reads it:
`skills/work-on/references/phases/phase-3-analysis.md` (a child reading earlier steps),
`skills/execute/koto-templates/execute.md`'s lead shape (detailing the next step) and the lookup
section of `skills/execute/SKILL.md`. `check-run-record-rules.sh` greps those three for the
fence label.

**Forged or competing entries.** The lookup returns a root only when the root's own
`trail/pr/*` lists the PR. That stops a forged index entry naming an unrelated session. It
doesn't stop someone who can write both an entry and a matching root, so the lookup never picks
silently: it returns every other run id in `others` and reports `unique: false` when more than
one record claims the PR. For ownership, a foreign entry makes a PR foreign, never mine, so a
forged entry can at worst stop a run from adopting a PR, which the run reports. That
denial of service is a residual: a forged later `written_at` can make a PR read as foreign.

**Record text is data.** Plan text, departures and decision rationales come from PRs, issues and
agents. A reader, person or agent, treats them as data and never as instructions.

**Pins.** `run-record-pin.sh` is the one action driven partly by read-back data, so it checks
provenance locally: a step session must be the root's own child or dispatched by it, an index
or plan session must hold this run's entry, and every address comes from the opener's
open-time record. At most S + P + 1 pins per run. A trail entry naming anything else is skipped
and reported. shirabe can't reverse a pin it sets, and it never unpins. A pin comes off by hand or with koto's release authority,
as koto defines it, and shirabe claims no stronger guarantee.

**What the store holds.** Index entries name `owner/repo#n` and a workspace path, which names a
user and an instance. `trail/plan/*` holds the PLAN's text, and the trail holds agent-written
departure and decision text. The shared address is the identifier `shirabe-run-record/<owner>`,
so one owner's index never shares a prefix with another's. A private repository's PLAN, names
and paths are readable by every holder of that bucket's credentials, the same audience that can
already read every session in it. A public repository's PLAN is public already, but its
departure text is not, and it must hold no credentials. Under omit nothing from the store
reaches PR text. Under include the reference names a session and a run id, never a path.
`result:` text and `trail/unpinned` codes are never copied into PR text.

**Dependencies.** No new packages. The floors (`RECORD_PIN_FLOOR`, `RECORD_PIN_CLOUD_FLOOR`)
are checked against the installed koto's version and fail closed: `record: unpinned`. The
workspace option is detected from koto's help and fails closed to reading from the address's
own directory. The stub koto is built from koto's specifications, so the floors
are set only after the end-to-end walkthrough against a real koto passes. The stub is test-only
and never on a production `PATH`. The workspace option is a new cross-prefix address in koto and
gets koto's own review. It's an addressing option, not an access boundary.

**Dropping the marker.** Removing the hidden marker removes workflow content from public PR
text. On a koto below the workspace-option floor, two runs in different workspaces that share a
login, topic and branch are told apart only by login and branch, as `/scope`'s PR is today, so
one could adopt, push to or rewrite the other's PR. Two runs in one workspace still see each
other's index entries. Unique topic names stay the separation on that path, as they are for
`/scope` now.

**Stub and floors.** `check-run-record-rules.sh` fails when the stub's path appears outside
`scripts/testdata/` and the test files. A koto version that doesn't parse, or a pre-release,
compares below both floors, so the run falls back to unpinned and its own workspace.

## Consequences

### Positive

- A merged PR leads to its run's record in every plan mode with nothing in the PR's text.
- The record is the run's own sessions, so the proof a reader sees is the proof the run used.
- Retention is one koto mechanism, used as specified, and visible in every prune's output.
- PR bodies under omit are free of workflow content in every mode, coordinated included.
- The lifecycle has one statement in every document that describes it.

### Negative

- The fresh-workspace reach depends on a koto change that isn't agreed yet.
- Every PR record now costs an extra store write, and `owned-pr.sh` an extra read per
  candidate PR.
- A coordinated run under omit loses body-based recovery.
- Runs that stop at a ready PR later closed unmerged stay pinned until someone releases them.
- A run that never reaches a qualifying terminal (abandoned, failed, or paused awaiting merges
  past `retention.keep`) loses its record to koto's ordinary retention, index sessions included.
- The change touches many files across `/execute`, `/work-on` and the shared scripts in one PR.

### Mitigations

- `record-store.sh` isolates the koto change to one file, and the same code works at the run's
  own workspace on today's koto.
- Index writes are one small key per PR, and the ownership read happens only when there are
  candidates.
- Session-store recovery already exists for coordinated runs, and `include` keeps the body path
  for repositories that want it.
- `koto session list --pinned` finds every pin, and the retention reference says how to release.
- The PLAN's steps follow the phases above, each with its own tests, so the PR's review can go
  step by step.
