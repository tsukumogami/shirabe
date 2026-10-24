---
schema: design/v1
status: Proposed
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
  capability, a `--workspace` address on koto's commands, proposed to koto as its own step;
  until it ships the same code writes and reads at the run's own workspace. A pin step
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

Proposed

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
`.` and `..` excluded, before either reaches a name or an address. The index session lives at a shared store address:
the koto workspace prefix of the identifier `shirabe-run-record/<owner>`, one per repository
owner. A multi-pr plan's
record root lives there too.

Reaching an address other than the cwd's needs one koto capability that doesn't exist,
named K2 in the PRD. The proposal to koto is one change to koto's address resolution, not to
any command: a global `--workspace <identifier>` option, resolved once into the backend
before any command runs, so every command (`init`, `context`, `status`, `decisions`, and the
pin's commands too) addresses that identifier's prefix instead of the cwd's. The prefix is the
same function koto applies to a cwd today, the first 16 hex digits of the SHA-256 of the
string, applied to the identifier as given. koto canonicalizes a cwd before hashing, and
shirabe records `pwd -P`, which is already canonical, so `--workspace <recorded path>`
reaches exactly the prefix the run wrote to, on macOS and Linux alike. Reads through the
option keep no local copy, spool nothing and write nothing into the read session. Concurrent
`context add`s of distinct keys from two workspaces must both land. K2 lands after the pin
(koto#441, #444) ships and adds no code to the pin's commands, which inherit the address
through the shared resolver, so the pin's code and design are unchanged.

What a reader with the cloud store's credentials and GitHub reaches, before and after K2:

| From | Before K2 | After K2 |
|---|---|---|
| The run's own workspace path | the index, the root, every step session in that workspace, that workspace's multi-pr root | the same |
| Any other workspace, fresh or not | nothing | the index, the root, every step session in any workspace, the multi-pr plan root |
| GitHub alone, without store credentials | nothing about the run | nothing about the run |

All shirabe code touches K2 through one file, `scripts/lib/record-store.sh`. It decides
the address. When the installed koto is below the K2 floor constant (unset until koto
releases K2), the shared address is the run's own workspace and `--workspace` is never
passed, so the same index and lookup work from the run's workspace path, on today's koto.

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
refused with exit 65 before anything is written:

| Verb | Session | Keys |
|------|---------|------|
| `pr` | record root | `trail/pr/<owner>.<repo>.<n>`: `{repo, number, role, state, recorded_at}` |
| `plan` | record root (multi-pr: the item session) | `trail/plan/<step>.md` (the PLAN's full text from `git show HEAD:<plan>`), `trail/plan/<step>.json`: `{sha, entry, recorded_at}` |
| `step` | record root | `trail/step/<step>`: `{session, workspace, superseded: [names]}` |
| `departure` | the session where it happened | `trail/departure/<n>.json`: `{step, kind, what, why, at}` |
| `decision` | the session where it happened | `trail/decision/<n>.json`: `{step, actor, choice, rationale, at}`, plus the same choice and rationale through `koto decisions record` |
| `item` | multi-pr plan root | `trail/item/<step>`: `{session, workspace, pr}` |
| `index` | the PR's index session | `run/<run_id>`: `{workspace, session, session_id, mode, topic, written_at}` |

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
are made per run, and any other name it's handed is skipped and reported. shirabe can't reverse
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
opener retries every session that key names. The pin floor is one constant,
`RECORD_PIN_FLOOR`, in `run-record-pin.sh`. Below it, or while it's unset, no
`koto session pin` call is made and the result says `record: unpinned`.

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
- **Ownership.** `owned-pr.sh --run-id` classifies each candidate PR by its index entry
  through `record-store.sh`: an entry for this run is mine, the latest entry naming another
  run is foreign, and no entry falls back to today's login-and-branch match (as `/scope`'s
  unmarked PR already does). `--take-over` writes this run's index entry instead of
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

Two things wait on koto. K1, the pin, waits on koto#444's release: until then
`RECORD_PIN_FLOOR` is unset and runs report `record: unpinned`. K2, the workspace option, is
a separate proposal to koto, pending koto's acceptance: until it lands the index and the
multi-pr root live at the run's own workspace, so a lookup works from that workspace path
and a multi-pr plan whose items ran in different workspaces has one root per workspace.

## Solution Architecture

### Overview

The record is three kinds of session: the record root (`execute-<topic>`, or the multi-pr
plan root `plan.<owner>.<repo>.<topic>.<sha12>` at the shared address), its step sessions,
and one index session per PR at the shared address. Four new scripts write, read and keep
them, and every existing writer of PR text or decisions calls them at the point the fact
arises.

### Components

New files:

- `scripts/lib/record-store.sh` (sourced): `rs_address` returns the shared address and
  whether `--workspace` is passed. `rs_koto <address> <koto args>` runs koto against an
  address. `rs_index_name <owner/repo> <n>` and `rs_plan_root_name` return names. The K2
  floor is the constant `RECORD_STORE_FLOOR` here. It's the only file that knows about
  koto's `--workspace`.
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
run-trail.sh departure --session S --step ID --kind deviated|deferral|scope-change|entry-rewritten --what-file F --why-file F
run-trail.sh decision  --session S --step ID --actor agent:NAME|person[:LOGIN] --data-file F
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
test, `skills/execute/scripts/execute-open.sh` (the `trail/self` record),
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
templates, `skills/execute/scripts/execute-open.sh`, `skills/work-on/scripts/work-on-open.sh`,
`skills/execute/scripts/terminal-retention_test.sh`, `skills/execute/requires.tsv` and
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

- **K2 in koto.** The `--workspace` option described in Decision 1 is a proposal to koto, a
  separate step in koto and pending koto's acceptance. It must not change the pin's code or
  design. When it ships, `RECORD_STORE_FLOOR` is set to its release.
- **K1's release.** When koto releases the pin, `RECORD_PIN_FLOOR` is set to that version.
- **The end-to-end walkthrough** from a fresh workspace on another host, against a real koto
  and a real bucket, waits on both. It's done after they ship, not as part of this change.

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

**Lookup output.** The lookup's JSON holds names, ids, numbers, states and the workspace
path, never free text. The workspace names a user and an instance, so the skill text marks it
internal, not for pasting into PRs or issues. `--steps` adds step ids, session names and
commit SHAs only. Reading plan text, departures or rationales is a separate
`koto context get`, whose output is fenced and labelled untrusted wherever a skill reads it.

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

**Dependencies.** No new packages. The floors (`RECORD_PIN_FLOOR`, `RECORD_STORE_FLOOR`) are
checked against the installed koto's version and fail closed: `record: unpinned`, and the run's
own workspace as the address. The stub koto is built from koto's specifications, so the floors
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
