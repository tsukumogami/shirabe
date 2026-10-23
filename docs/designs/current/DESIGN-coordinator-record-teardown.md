---
schema: design/v1
status: Current
problem: |
  The coordinate skill reads and writes a coordinator's state through sixteen
  record-*.sh scripts and a markdown codec that serve two stores, the GitHub
  record and the coordinator's koto session. The session path still renders the
  state to an issue body and parses it back to validate a write, the codec's
  validators run only inside its renderer, discipline scope refuses the session
  in six places, four entry kinds are posted on a coordinator issue that outside
  readers depend on, and about twenty shipped documents name the GitHub record
  as the store. Removing the record means taking all of that out without losing
  a guarantee and without touching a coordinator that still runs on it.
decision: |
  Split the codec's checks into a JSON validation module, state-schema.jq, and
  have the write core take the next state as JSON, so no write renders or
  parses a body. Rename every surviving record-*.sh to a state-* script that
  serves the session alone, delete the GitHub backend, the store choice, the
  move, the codec's markdown half and the discipline handoff machinery, and
  keep the session's key layout, adding only record/rotation and
  record/reasoning for discipline scope. Post cost and goal-fit entries on the
  pull request they concern and verdicts and failures on the roadmap pull
  request that records them. Land the changes that remove nothing first, hold
  the removal behind a precondition anyone can check on GitHub, then the
  rename, then the amendments and the supersession.
rationale: |
  The removal's acceptance is a grep, so the survivors need a namespace the
  grep can't confuse with the record's. Validating JSON directly keeps every
  refusal the codec makes while deleting the round trip that only existed to
  reach them through a renderer. The session layout stays because sessions
  already on it must resume across the change. Outward entries go where their
  readers already look, on items GitHub owns. Ordering the work by what a
  running coordinator reads lets most of it land before the external gate
  opens.
upstream: docs/prds/PRD-coordinator-record-teardown.md
decision_provenance: inline-resolved
---

# DESIGN: Tear down the GitHub coordinator record

## Status

Current

Five decision questions were resolved inline under `/scope`; the list of
documents to amend and supersede was mechanical and is settled in Solution
Architecture. The reasoning that survived the decision reports is carried in
Considered Options below.

## Context and Problem Statement

`docs/prds/PRD-coordinator-record-teardown.md` requires the GitHub coordinator
record removed and everything that exists only because of it, with the
coordinator's koto session as the one store (R1). This section restates the
technical picture its requirements land on, read from `skills/coordinate/` at
the head of `main` on 2026-10-21.

**The record scripts serve both stores.** Sixteen non-test `record-*.sh` scripts
and `record-codec.jq` sit under the skill. `record-source.sh` is the one reader:
`rs_record` returns the state as the codec's JSON from either store, and on the
session it gets there by assembling the `record/*` keys, rendering them to an
issue body at `record/meta`'s written time and parsing that body back. Every
writer (`record-holding.sh`, `record-hold.sh`, `record-state.sh`,
`record-decision.sh`, `roadmap-status.sh`) builds a markdown body with
`record-render.sh` and hands it to `record-write-core.sh`, which parses it
(the canonical check), re-renders it with its own written time, checks it
against `RECORD_BUDGET=60000`, and on the session parses it back once more to
find the sections whose JSON changed. The codec's checks (`check_top`,
`check_row`, `check_cell`, `check_worker`, `check_holds`, `check_state`,
`check_decisions`, `text_problem`, `text_named_repos`) run inside
`render_record`, and a few callers reach some of them directly
(`record-append.sh` and `roadmap-status.sh` call `text_problem`, and
`reconcile-salvage.jq` calls `check_decisions`), so splitting them out has to
keep those callers working too. About thirty-six
other scripts read or write the state through the record scripts; none outside
`skills/coordinate/` does.

**The GitHub record's own machinery.** `record-find.sh` lists open issues by the
exact title `Coordinator record: ROADMAP-<name>` (`record-common.sh`'s
`lib_open_issues`), judges the declaration line, then the author's authority
through a collaborator-permission read (`lib_authority`), and seals a
`RECORD_FIND` token that `coord-log.sh run-facts` and `run-store` read for the
issue number and the store. `record-open.sh` creates the issue, or at discipline
scope the `coordinate/discipline-<name>` branch, a commit and a draft pull
request. `record-append.sh` posts and lists marked comments
(`<!-- coordinator-record-entry v1 kind=<kind> -->`) and counts only those by an
author with write access (`lib_has_write_access`). `record-move.sh` and the
template's `record_move` state move a GitHub record onto the session, leaving
a moved-shape stub issue that outward entries are still posted on. The
`store` Run row, `--store` and the `STORE` template variable choose the store
per run.

**Discipline scope is GitHub-only.** `coordinate-open.sh`, `record-open.sh`,
`record-find.sh` and `record-state.sh` refuse the session at discipline scope
(`store-discipline`), and `record-append.sh` refuses it in its own words.
A rotation's window lives in its pull request's title, its host in the branch's
repository, and what it hands its successor in `docs/disciplines/<name>.md`,
committed by `rotation-close.sh` and read by `closeout-read.sh`,
`decision-next.sh`, `deferral-check.sh`, `record-decision.sh --carry` and
`reconcile-read.sh`. `predecessor-handoff.sh` renders that file from an expired
predecessor's pull request body. The template's `rotation_close`,
`rotation_step`, `rotation_done` and five `predecessor_*` states drive those
steps.

**Outward entries depend on the issue.** `record-append.sh` writes the
`cost`, `milestone-verdict`, `milestone-failure` and `goal-fit` kinds to the
session and posts them on the record issue, keeping the comment URL in
`record/posted/<n>`. The cost reading guide in
`skills/coordinate/references/unit-cost.md` lists one issue's comments.
`roadmap-status.sh --verdict`, `--reopen` and `--confirm` read an entry back
through `posted_entry`, which accepts only a comment on `issues/<record>`, and a
roadmap's `## Progress` line carries that comment's URL and the entry's hash.

**The documents.** `DESIGN-coordinate-record-container.md` exists to choose the
GitHub container. Ten other designs and eight requirements documents name the
record on GitHub as where their facts live. The PRD's R19 asks for the first to
be superseded and the rest amended.

## Decision Drivers

- **The removal is grep-shaped.** PRD R16 and R17: after the last change no file
  under `skills/coordinate/scripts/` or `koto-templates/` is named `record-*.sh`
  or `record-codec.jq`, names the record libraries, the title, a collaborator
  endpoint or `docs/disciplines/`, and a structure test keeps it that way.
- **Every guarantee survives, on JSON.** R8: one writer per key, the compare
  that refuses a changed state as `record-changed` (exit 12), the field,
  column, hold, stored-set and Decisions rules, and the private-repository,
  home-path and token refusals, with no markdown rendered or parsed.
- **Sessions already on the store must not notice.** R14: every existing key
  keeps its name and JSON shape, so a coordinator on its session resumes and
  imports across the change.
- **Nothing touches a live run.** R20: a change that removes a reader or writer
  of the GitHub record waits until no coordinator runs on one; what removes
  nothing may land first, and the script rename and the documents come last.
- **Readers outside the coordinator keep their entries.** R5 to R7: the four
  outward kinds keep their marker line and text, posted on the item each is
  about; old progress links keep being accepted; nothing on GitHub is deleted,
  closed or edited.
- **Discipline scope gets a store.** R10 and R11: a rotation's window, host and
  reasoning move into the session, and a rotation finds and carries its
  predecessor there.
- **The skill's floor.** R21: bash 3.2 and jq, no new koto feature, no raised
  koto floor.
- **One reviewable change at a time.** The removal touches about fifty scripts,
  the template, a dozen references and twenty documents; the order should let
  each piece be reviewed and land on its own.

## Considered Options

### Decision 1: The shape of the session-only state code

Resolved inline.

The record scripts serve two stores and validate through a renderer. After the
removal they serve one store, and R16's grep has to tell a survivor from a
leftover.

**Chosen: a `state-` namespace, a JSON validation module, and a write core that
takes JSON.** Each surviving `record-*.sh` becomes a `state-*.sh` script with the
same job on the session alone (the table in Solution Architecture). The
codec's checks move into `state-schema.jq`, a jq module whose functions take a
state as JSON and refuse with the same `refused: ` messages; the markdown
encoding, the table renderers, the parsers, the canonical comparison and the
handoff format are deleted with `record-parse.sh` and `record-render.sh`. A
writer builds the next state as JSON, as its jq already does before it
renders today, and hands the core a state file (`--state-file`) instead of a
body. The core validates it with `state-schema.jq`, runs the owner diffs and
the compare against `record/meta`, scans for private repositories, and writes
the changed keys. `state-read.sh` keeps `rs_record` returning the state's JSON
and drops the `.md` and `.raw` outputs, `rs_view`, `rs_record_api` and
`--show`. The template keeps its `record_*` state names and the `RECORD_FIND`
capture: they name the coordinator's record, which the session still is, and
they aren't scripts.

*Keep the `record-*` names and strip their GitHub halves.* The least churn, and
rejected because it fails R16 by construction: "no file named `record-*`" is the
one form of the check that can't drift, and a maintainer can't tell a stripped
survivor from a forgotten script.

*One combined state library.* Fewer files, and rejected because the one writer
per key that R8 keeps is enforced per script by the writer flags
(`DECISIONS_WRITER`, `HOLDS_WRITER`, `STATE_WRITER`, `VERDICT_WRITER`) and the
structure test that holds each to one script.

*Keep a renderer for a person to read the state.* Rejected by R13: koto's
session view is the human surface, signed off by the owner.

### Decision 2: How outward entries reach their items

Resolved inline.

R5 fixes the item per kind: a unit's pull request (or issue) for `cost`, the
named pull request for `goal-fit`, the roadmap pull request for
`milestone-verdict` and `milestone-failure`.

**Chosen: an explicit target, and `roadmap-status.sh` posting its own
entries through the entry script.** `state-entry.sh` (today's
`record-append.sh`) takes `--on <owner/repo#n>` for `cost` and `goal-fit`,
checks it against `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*$`, refuses a
repository that isn't one of the run's (the host repository or a holding's),
and refuses a `goal-fit` whose text names a different pull request. The
private-repository, home-path and token scan of the entry's text runs against
the destination's visibility, not the host's: an entry bound for a public
repository may name no private one. Both reads fail toward refusing: a
destination whose visibility can't be read counts as public, and a named
repository whose visibility can't be read counts as private. The destination's
visibility is read when the entry is posted, not when it was written.
`unit-cost.sh` passes the holding's Pull
request, or the unit's issue, or no target, in which case the entry stays in the
session and the archive and the capture's output says so. A verdict or failure
can only be posted once its roadmap pull request exists, and the progress line
needs the comment's URL, so `roadmap-status.sh --verdict` and `--reopen` change
order: commit the milestone edit to the branch, open the pull request with the
whole entry in its body as today, post the session entry as a comment on that
pull request by calling `state-entry.sh --repost <n> --on <roadmap pull
request>` (so the content checks and the `@` escaping apply), then commit the
progress line with the comment's URL and hash and push it before printing the
result. They take `--entry <n>` (the session entry) instead of `--entry-url`.
`posted_entry` reads a comment by id through
`repos/<roadmap repo>/issues/comments/<id>`, which serves issue and pull request
conversation comments alike, so `--confirm` accepts both a new progress line (a
`/pull/<n>#issuecomment-<id>` URL, which must be on the pull request the row's
Side effects entry names) and one written before the removal (an
`/issues/<n>#issuecomment-<id>` URL). A retry deduplicates on
`record/posted/<n>`, then on a comment on the target with the same marker and
text, created at or after the entry's stamp by the login `gh api user` returns,
compared without case, and not already claimed by another entry's
`record/posted/`. When `gh api user` can't answer (an App token has no user),
the retry posts nothing and exits 2 naming the entry, so a duplicate is never
risked. Nothing in the skill's normal path reads a collaborator permission;
the one read left is inside the legacy importer (Solution Architecture), for
entries written before the removal.

The three readers that consume outward entries today, and what each reads
after the removal:

| Reader | Today | After the removal |
|---|---|---|
| `roadmap-status.sh`'s check that a verdict was posted before a Done edit (`--verdict`, `--reopen`, and `--confirm` at merge) | reads the comment on the record issue by the URL it is given | `--verdict` and `--reopen` read the entry from the session (`--entry <n>`), post it on their roadmap pull request and refuse to finish (exit 14) until it is posted and the progress line names it; the Done edit reaches the default branch only through that pull request, and `--confirm` re-reads the cited comment by id and checks its author, marker, kind, text and hash |
| `unit-cost.sh`'s dedupe (one `cost` entry per capture key) | lists the record's entries through `record-append.sh --list` | lists the session's entries (`record/entries/`, kind `cost`) through `state-entry.sh --list`, which a session-store run already reads today; nothing on GitHub |
| the cost join (`references/unit-cost.md`, "Reading entries") | lists one record issue's comments with the `kind=cost` marker | lists a scope's units from the session's Holdings, or the roadmap's Delivered lines, and reads each unit's pull request (or issue) comments with the same marker filter and an author filter on the coordinator's login |

*Post a verdict on the unit's pull request.* Rejected: a verdict judges a
milestone, which may cover several pull requests or none.

*Cite the roadmap pull request instead of a comment.* Rejected: the progress
line is written before the pull request's number exists, and a pull request
body can be edited after the fact, while the hash in the progress line is
checked against a comment's text.

*A per-scope GitHub issue for outward entries only.* Rejected: a coordinator
issue under another name.

### Decision 3: Discipline scope on the session

Resolved inline.

R10 and R11 put a rotation's window, host and reasoning in the session and have
a rotation find and carry its predecessor there.

**Chosen: two keys, the predecessor found by slug and stamp, carried through the
core.** `record/rotation` holds `{start, end, host_repo, predecessor}` (the
predecessor's session name, or null for a first rotation) and
`record/reasoning` holds the reasoning for the next rotation as text. Both are
written by `state-stored-set.sh` (today's `record-state.sh`) under
`STATE_WRITER`, which already owns Run, Standing and Work. At a discipline
start, `state-find.sh` lists the discipline's sessions with `koto session list`
by the scope's slug, as `coord-log.sh` already does for a roadmap scope's
earlier runs, and takes the one with the latest stamp earlier than this run's
that holds `record/meta`. A candidate is the predecessor only when its name
matches `coordinate-<slug>-<YYYYMMDDTHHMMSSZ>` whole, it passes the provenance
check a resume applies today (`coord-log.sh provenance`, built from the shipped
template, or a template the carry-across already accepted), its own
`DISCIPLINE` and `HOST_REPO` variables equal this run's, its rotation has
ended (the same rule as below; the opener never hands the find an open one, and
a direct call on one is `unreadable`), and no other session of the discipline
already names it as its predecessor (one predecessor is never carried
twice). Two candidates with the same stamp, or a candidate that fails any of
these, is `unreadable`. It seals one of: `found` (this run's own state exists,
a resume), `predecessor <session>`, `first` (no earlier rotation) or
`unreadable <session>` (the predecessor's `record/meta` or a section key fails
`state-schema.jq`). A new `predecessor_carry` state runs `state-open.sh
--carry-from <session>`, which copies the predecessor's Holdings, Deferrals,
Side effects, Reversals, Holds, Run, Standing, Work, unsettled Decisions and
next decision number into this run through `core_carry`, and records the
predecessor in `record/rotation`. The carry's output lists what it carried
(the holds, and the Standing rows by kind and owner), which the start reports
up, so the owner sees an approval or a missing hold that came from the
predecessor before anything acts on it. Reconcile reads `record/reasoning`
from the predecessor's session and classifies it `present` or `not_recorded` with the
rule it applies to the handoff file today. An expired predecessor that never
closed has no `record/reasoning`, so it reads as `not_recorded`. Closing a
rotation writes `record/reasoning` and ends the run; nothing is committed and
no pull request is opened. A predecessor on another host is imported first by
its owner with `coordinate-open.sh --import`, which this change allows at
discipline scope.

**A restart and a new rotation are told apart by the window.** At discipline
scope the opener looks at the newest session of the discipline that holds
`record/meta`. A rotation is open while the current UTC date is on or before
its `record/rotation` end date and it holds no `record/reasoning` (closing a
rotation writes that key), and ended otherwise; the check is made against the
time of the start. While that session's rotation is open, a start
is a restart of the same rotation, so the opener's existing resume and
carry-across apply as at roadmap scope: resume it when it is live and its
template matches, otherwise open a new run, cancel the live one as the opener
does today, and carry the whole record across, window included. Once the
rotation has ended, by date or by closing, a start is a new rotation: the opener opens a new run with a new
window and the find goes to the predecessor path above, never to the
whole-record carry-across. So there is never a second rotation of one
discipline open on a host: a start inside the window continues the current
rotation, and a start after it closes that rotation and opens the next.

*One session per discipline across all rotations.* Rejected: each rotation's
run stamp is what its Decisions stamps key on, and a template change would
carry everything into a new session anyway.

*A rotation index in a shared, well-known session.* Rejected: new state, in a
store nobody owns.

### Decision 4: Size bounds, `record-full` and the decisions archive

Resolved inline.

R9 removes every bound that came from GitHub's body limit.

**Chosen: one bound survives, with a new reason.** The 60,000-byte record budget,
the 65,536-byte `MAX_BYTES`, `record-full` (exit 13) and the template's
`record_conflict` route on it are removed. An outward entry is still posted as a
GitHub comment, whose limit is 65,536 characters, so `state-entry.sh` keeps its
60,000-byte cap on an outward kind's text, now justified by the comment limit;
session-only kinds have no cap beyond koto's. `record-decision.sh --archive`,
which only fires within 4,096 bytes of the budget, is removed with
`decision-next.sh`'s `archive` move. Restoring an archived row stays: a session
moved from a GitHub record may carry an Archived line and `decisions` entries,
and an arrival naming one of those rows still brings it back.

*A new per-key session budget.* Rejected: a limit with no consumer, which R9
asks not to invent.

*Keep the archive with a session-size trigger.* Rejected: a new state policy the
PRD rules out.

### Decision 5: The order, and the live-run precondition

Resolved inline.

R20 lets changes that remove nothing a running coordinator reads land first,
holds every change that removes a reader or writer of the GitHub record until no
coordinator runs on one, and puts the script rename and the documents last.

**Chosen: five additive changes and the legacy importer, one gated removal,
a rename, then the documents.** The early changes add the session path beside the GitHub one and
pick between them by the run's sealed store, so a coordinator on its GitHub
record keeps today's behaviour, which its unchanged suites prove: the JSON
validation (the GitHub path renders
from validated JSON), the outward targets for session-store runs, discipline on
the session (a rotation on GitHub keeps its machinery until it ends, and the
first session rotation carries its handoff file once), the session as the
default store for a scope with no record, and the structure test in a
transitional form. Then, behind the precondition, the GitHub backend, the store
choice and those GitHub-store branches come out at both scopes. Then the
codec's markdown half goes and the survivors are renamed, with the registries
and the CI path filters. Last, the amendments and the supersession, which carry
no runtime risk, land in their own change. The precondition is two searches
anyone can run plus a per-discipline check (Implementation Approach).

*Replace the GitHub paths in place in the early changes.* Rejected: a
coordinator on its GitHub record has no session entries or keys, so changing
`roadmap-status.sh`'s arguments or the retry's dedup under it would break a
live run, which R20 forbids.

*One pull request after the gate.* Rejected: too large to review, and it holds
the safe changes behind an external gate for no reason.

*Remove the GitHub backend before discipline scope runs on the session.*
Rejected: a discipline rotation would have no store.

### The documents (mechanical)

`DESIGN-coordinate-record-container.md` is superseded; its decisions are about
the container, and the stored set it introduced (Run, Standing, Work) and its
landed-feature write-back are restated in Solution Architecture so they keep a
current statement. Every other document whose text makes the GitHub record the
store gets an amendment in the fold-record removal's pinned form, keeping its
status. A document that mentions the record only in passing, or is about what
stays GitHub's, gets nothing.

## Decision Outcome

The coordinate skill keeps a coordinator's state in its session and nowhere
else. Its scripts read and write that state as JSON through a `state-`
namespace, validated by `state-schema.jq` with every refusal the codec made
except markdown layout and GitHub's body limit, and written by the same writers
with the same owner flags through a core that takes JSON. The session layout is
unchanged apart from `record/rotation` and `record/reasoning`, which give
discipline scope its window, host and handoff, and a rotation finds and carries
its predecessor through `koto session list` and the core's carry. Outward
entries keep their marker and text and go on the pull request they concern, or
on the roadmap pull request that records a status change. Nothing on GitHub is
deleted or edited, and old progress links stay accepted. The work lands in
eight changes: five additive ones that leave a GitHub-record coordinator's
behaviour as it is today, one removal behind a precondition (with the legacy
importer landed just before it, dormant), the rename, and the documents. The
PLAN files each as its own issue and pull request: nine, since the importer
is an issue of its own.

## Solution Architecture

### What each record script becomes

| Today | After | What changes |
|---|---|---|
| `record-common.sh` | `state-common.sh` | loses `lib_open_issues`, `lib_discipline_read`, `lib_authority`, `lib_has_write_access`, `ISSUE_TITLE`, `lib_rotation_dates` and `lib_file_at`; keeps `ENTRY_MARKER_PREFIX` for outward posts |
| `record-source.sh` | `state-read.sh` | session backend only; `rs_record` returns JSON, no `.md` or `.raw`; `rs_view`, `rs_record_api`, the store choice in `rs_source` and `--show` removed; `rs_facts`, the resume and carry candidates stay, and `rs_probe` (which reports koto's features) moves into the opener |
| `record-codec.jq` | `state-schema.jq` | the `check_*`, `text_*`, `pr_link`, `d_*` and `rework_problem` functions over JSON; no `enc`, `dec`, table renderer, parser, `normalized` or handoff format |
| `record-parse.sh`, `record-render.sh` | removed | |
| `record-write-core.sh` | `state-write-core.sh` | takes `--state-file`; validates with `state-schema.jq`; no budget, no render, no `gh issue edit` or `gh pr edit`, no `store-moved`; `core_carry` and `core_write_host` stay |
| `record-write.sh` | `state-write.sh` | no `--close` (it closed the issue); `--end` and `--pushed-head` stay |
| `record-holding.sh` | `state-holding.sh` | builds JSON instead of a body |
| `record-hold.sh` | `state-hold.sh` | as above |
| `record-state.sh` | `state-stored-set.sh` | as above; no `store` Run key; writes `record/rotation` and `record/reasoning` |
| `record-decision.sh` | `state-decision.sh` | as above; no `--archive`; `--carry` reads the predecessor's session instead of the handoff file |
| `record-append.sh` | `state-entry.sh` | no issue read before an append; `--on` target for outward kinds; dedup by `record/posted/<n>` and the coordinator's login |
| `record-confirm.sh` | `state-confirm.sh` | compares `record/meta`'s written time instead of a body's `Written:` line |
| `record-handover.sh` | `state-handover.sh` | reads through `state-read.sh` |
| `record-find.sh` | `state-find.sh` | reads the session only: `found`, `none`, `malformed`, and at discipline scope `predecessor`, `first`, `unreadable`; no title search, authority read or store token |
| `record-open.sh` | `state-open.sh` | seeds the session's keys; at discipline scope writes `record/rotation` and runs `--carry-from` |
| `record-move.sh` | removed | |
| `rotation-close.sh`, `predecessor-handoff.sh` | removed | closing a rotation is `state-stored-set.sh --reasoning` and `state-write.sh --end` |

Every caller changes the name it calls and, where it read a body, reads JSON:
`reconcile-read.sh` drops `rs_view` and `reconcile-salvage.jq`'s body parse;
`pick-facts.sh`, `closeout-read.sh` and `deferral-check.sh` read
`rs_record`'s JSON; `progress-view.sh` and `milestone.sh` include
`state-schema`. `coord-log.sh run-facts` returns `{scope, name, repo}` with no
issue number, and `run-store` is removed; `unit-cost.sh` reads the unit's
milestone from those facts and its pull request from the holding.
`quiet-check.sh` and `holding-link.sh` lose their GitHub-mode
`--scope --name --repo --ref` calls, and `posture-read.sh` drops
`record-write.sh --close` from its close verbs. Beyond those, every script that
calls or sources a removed name changes: about forty today, among them
`board-lib.sh` (and through it `land-check.sh` and `land-merge.sh`),
`board-record.sh`, `start-check.sh`, `pause-read.sh`, `merged-facts.sh`, the
`reconcile-*`, `report-*` and `decision-*` scripts, `dispatch-worker.sh`,
`dispatch-common.sh`, `wait-target.sh`, `teardown-verdict.sh`, `pick-facts.sh`,
`roadmap-status.sh` and `coordinate-open.sh`. The rename's change takes the list
from `grep -l` over the removed names at its base commit, so nothing is missed
by a list written earlier.

Every session on the store today holds a `store` Run row reading `session`
(`record-open.sh --store session` and the move both write it).
`state-schema.jq` accepts that one legacy row, nothing writes a new `store`
row, and `state-stored-set.sh --run store` is refused, so every session already
on the store resumes unchanged (R14). The codec's `check_state` refuses the
crash-set Run rows (`rules`, `briefs`, `friction`, `reports-to`) unless the Run
section holds that `store session` row, a gate that kept them off GitHub
records. With one store the gate has nothing to guard: `state-schema.jq` allows
the crash-set rows in any session, and a test opens a fresh session after step
6 (with no `store` row) and writes each of them. Until step 6 the gate stays as
it is, and a scope that starts on the session by default from step 4 gets the
`store session` row
the opener writes today.

### The session layout

Unchanged from the session store (R14): `record/meta`, `record/holdings`,
`record/deferrals`, `record/side-effects`, `record/reversals`, `record/holds`,
`record/run`, `record/standing`, `record/work`, `record/decisions`,
`record/host`, `record/entries/<n>`, `record/posted/<n>` and
`legs/<request-id>/<leg>`, each with today's JSON. Added for discipline scope
(R10): `record/rotation` and `record/reasoning`, both owned by
`state-stored-set.sh`. The writer of each key:

| Key | Writer (flag) |
|---|---|
| `record/meta` | `state-write-core.sh`, for every writer |
| `record/holdings`, `deferrals`, `side-effects`, `reversals` | `state-write.sh` via `state-holding.sh` (general writer); `roadmap-status.sh` adds Side effects rows |
| `record/holds` | `state-hold.sh` (`HOLDS_WRITER`) |
| `record/run`, `standing`, `work`, `rotation`, `reasoning` | `state-stored-set.sh` (`STATE_WRITER`); `verdict-owed` and `rework` rows by `roadmap-status.sh` (`VERDICT_WRITER`) |
| any section key, through the core's carry | `state-open.sh` (seeding a new run, `--carry-from` a predecessor) and the legacy importer, under the carry's own flag, as `record-move.sh` and the carry-across write today |
| `record/decisions` | `state-decision.sh` (`DECISIONS_WRITER`) |
| `record/host` | `state-stored-set.sh --host` |
| `record/entries/<n>`, `record/posted/<n>` | `state-entry.sh` |
| `legs/<request>/<leg>` | `dispatch-worker.sh`, `wait-target.sh`, `reconcile-legs.sh` |

`coordinate-template-structure_engine_test.sh`, which holds each writer flag to
one script today, gains a row per key in this table and fails when a script
other than the key's writer writes it.

### The write path

```
writer: rs_record -> jq builds next state JSON -> state file -> core_write --state-file
core_write: lib_write_guard -> state-schema.jq validate (65) -> rs_record (live)
            -> compare record/meta written (12) -> owner diffs (65) -> private-repo scan (65)
            -> record/meta pending -> changed section keys -> record/meta written
```

The refusals kept, from `record-codec.jq` and `record-write-core.sh` at the
PLAN's base commit (R8), each with a session test: a changed state
(`record-changed`, 12); a second writer of an owned key; an unknown top-level
field; a control character in a cell; an empty required column; a column that
records what GitHub recomputes; a malformed worker or address; a malformed pull
request link; a malformed hold or an illegal hold change; an unknown Run key or
a stored-set row breaking its rules (rework, pause-until); an illegal Decisions
state, transition or stamp; and a private repository name, a home-directory
path or a token-shaped string in a value that can leave the host. The scan
walks every string in the state recursively, `record/rotation` and
`record/reasoning` included, rather than a list of columns, and a test fails
when a state with a new string-bearing field isn't scanned. The
private-repository scan still reads each named repository's visibility and
counts one it can't read as private. `record/reasoning` keeps a 16 KiB cap,
the size an entry text has today. It is the one new bound, a deliberate
exception to R9's rule against inventing limits: it is prose an agent writes,
carried into every later rotation and shown to the owner in the carry report,
so its size is read by a person each time.

### The start

`coordinate-open.sh` loses `--store`, the `STORE` variable and the
`store-discipline` refusals, and keeps its resume, carry-across and `--import`
at both scopes, with the window rule of Decision 3 choosing between a restart
and a new rotation at discipline scope. `state-find.sh` keeps writing
`coord/source.json`, now always reading `session`, because the resume
candidate (`rs_resume_candidate`) resumes or carries only a session whose
`coord/source.json` reads `session`; a test starts a coordinator after the
removal, stops it, and checks the next start resumes it. A koto without the session store's features is refused at
start with `store-unsupported`, as the probe does today. The template's
`record_find` runs `state-find.sh`: `found` goes to `reconcile_pass`, `none`
to `record_open`, `malformed` to `record_conflict`, `predecessor` to the new
`predecessor_carry`, `first` to `record_open`, and `unreadable` to
`record_conflict` with the predecessor named. `record_move`,
`predecessor_handoff`, `predecessor_close`, `predecessor_step`,
`predecessor_done`, `predecessor_handed_over`, `rotation_close`,
`rotation_step` and `rotation_done` are removed. One new state, `rotation_end`,
takes their place where `rotation_close` was entered: the coordinator writes the
reasoning for the next rotation with `state-stored-set.sh --reasoning`, and the
state's action runs `state-write.sh --end`. The terminal results' `record:`
field names the session instead of an issue URL.

`predecessor_carry` runs `state-open.sh --carry-from <session>` as its default
action, capturing the carry's report as `PREDECESSOR_CARRY`; its gate passes on
exit 0 and goes to `reconcile_pass`, and any refusal goes to `record_conflict`
with the predecessor named. The handover gate (`state-handover.sh`) then lists
`carry-unacknowledged` until a Standing go-ahead whose Set time is after this
run's start exists (the start is the timestamp the run log already carries
on its `workflow_initialized` event, read by a `coord-log.sh` subcommand the
gate adds, not any time stored in the session's keys), so a carried rotation dispatches and merges nothing first;
`handover_engine_test.sh` gains that case.

Step 3's bridge for a discipline whose last rotation ran on GitHub: when
`state-find.sh` finds no earlier session of the discipline, it reads
`docs/disciplines/<name>.md` at the host's default branch with today's handoff
reader. A file it finds is sealed as `predecessor handoff:<sha>`; `state-open.sh
--carry-from handoff:<sha>` copies the file's sections into this run as the
handoff carry does today, and reconcile reads its reasoning from the file. No
file is `first`. The bridge is removed in step 6, after the precondition's
third condition has held. The template change also updates
`coordinate.mermaid.md`, the decider declarations that name a removed state
(`coordinate.*.decider.jsonl`, checked by `check-decider-declarations`), and
the rule-coverage rows for the removed and added states.

`roadmap-status.sh --verdict` and `--reopen` record the roadmap pull request
in their Side effects row as soon as it opens. When the post or the progress
commit fails after that, they exit 14 with the row naming the pull request,
and a re-run with the same entry finds the row, reposts (deduplicated as
above) and pushes the missing commit, so a failure never leaves a second pull
request or a progress line without its comment.

### Outward entries

| Kind | Target | Who posts | Read back by |
|---|---|---|---|
| `cost` | the holding's pull request; else the unit's issue; else none | `unit-cost.sh` via `state-entry.sh --on` | the reading guide in `references/unit-cost.md`, which lists a scope's units from the session's Holdings (or the roadmap's Delivered lines) and reads each pull request's comments with today's marker filter and an author filter on the coordinator's login, which replaces the permission read |
| `goal-fit` | the pull request the entry names | the coordinator via `state-entry.sh --on` | people reviewing that pull request; `milestone.sh check-goal-fit` reads the session entry, not the comment |
| `milestone-verdict` | the roadmap pull request `roadmap-status.sh --verdict` opens | `roadmap-status.sh` | `roadmap-status.sh --confirm`, through the progress line |
| `milestone-failure` | the roadmap pull request `roadmap-status.sh --reopen` opens | `roadmap-status.sh` | as above |

### Discipline scope

```
start --> record_find
  found                --> reconcile_pass            (resume of this rotation)
  predecessor <s>      --> predecessor_carry --> reconcile_pass
  first                --> record_open       --> reconcile_pass
  unreadable <s>       --> record_conflict          (stop for the person)
rotation end: state-stored-set.sh --reasoning; state-write.sh --end
```

### What stays on GitHub

Pull request state, head, checks, reviews, mergeability and the merge; the
review panel table a worker writes in its pull request body; issues used as
units of work; the roadmap at the default branch and the roadmap pull requests
`roadmap-status.sh` opens; the merge-order block a person reads; the CI
merge-last gate's reads; the worker's handoff comment on its merged pull
request; and the outward entries posted on the items above (R15). The scripts
that read these (`board-verdict.sh`, `panel-evidence.sh`, `squash-message.sh`,
`github-refs.sh`, `teardown-inventory.sh`, `merge-confirm.sh`,
`merged-facts.sh`, `teardown-handoff.sh`) change only where they called a
record script.

### The stored set and the write-back, restated

`DESIGN-coordinate-record-container.md` introduced three sections and a
write-back that outlive its container. **Run** holds the run's arguments, its
cap, the coordinator's address and one `told` row per party that has been given
it; **Standing** holds the events only a person owns that still bind the run
(pause, go-ahead, approval, answer, assignment), each with its owner, who
relayed it and when; **Work** holds a next step for every holding and a row for
work outside the holdings, local agents included. `state-stored-set.sh` is their
one writer and appends the matching entry. The handover gate on `reconcile`
holds a start while a holding has no next step or a live worker hasn't been
told the current address. A landed feature's Status and Outcome reach the
roadmap through `roadmap-status.sh`, run from the `landed` event: it opens the
roadmap pull request and records it as a side effect in flight, which pick reads
so the feature isn't offered again while the pull request waits. All of this is
unchanged; only its store is the session.

### The documents

Superseded, moved to `docs/designs/archive/` with `superseded_by` naming this
design once it is Current:

- `docs/designs/archive/DESIGN-coordinate-record-container.md`

Amended, each with a `## Amendment — <date>` section appended whose first
paragraph is "`DESIGN-coordinator-record-teardown.md` removes the GitHub
coordinator record. The original text above is left unedited; this section
records what no longer holds.", followed by what moved:

| Document | What the amendment records |
|---|---|
| `DESIGN-coordinate-record.md` | the find, open, write and confirm funnel reads and writes the session; no issue or pull request container, declaration-line authority, `Written:` compare or committed handoff; the codec's checks are `state-schema.jq` over JSON |
| `DESIGN-coordinate-skill.md` | Decision 2's layout on GitHub and both containers no longer hold; the rest stands |
| `DESIGN-coordinate-reconcile.md` | the reader reads the session, and the predecessor's handoff is its session's `record/reasoning` |
| `DESIGN-coordinate-merge-policy.md` | Holds are the session's `record/holds`; a rotation's carry moves them; no record pull request's Part 1 |
| `DESIGN-coordinate-paused-state.md` | Standing and Work are session keys; a person's resume reaches the coordinator by message, not a comment on the record |
| `DESIGN-coordinate-decisions.md` | Decisions are the session's `record/decisions`; no body limit, `record-full` or archive; `--carry` reads the predecessor's session |
| `DESIGN-coordinate-dispatch-path.md` | the holding's reader and writer are `state-holding.sh` over the session |
| `DESIGN-coordinate-teardown-agent.md` | the record row the coordinator clears last is a session key |
| `DESIGN-milestone-verdicts.md` | decisions are made from the session plus the default branch; verdict and failure entries are posted on the roadmap pull request |
| `DESIGN-coordinator-session-record.md` | the GitHub backend, the store choice (Decision 2), the moved shape (Decision 10) and the move (Decision 11) are removed; discipline scope runs on the session |
| `PRD-coordinate-skill.md` | R27's record on GitHub no longer holds |
| `PRD-coordinate-record.md` | the glossary's Record, R14's body and R17 to R20's find, open, close-out and rotation title no longer hold |
| `PRD-coordinate-reconcile.md` | R1's issue or pull request read and the handoff file read move to the session |
| `PRD-coordinate-decisions.md` | R6's take-over and handoff carry read the predecessor's session |
| `PRD-coordinator-session-record.md` | discipline scope, deferred to this removal by R4, is settled |
| `PRD-milestone-verdicts.md` | the glossary's record body and entry move to the session and the roadmap pull request |
| `PRD-coordinate-dispatch-path.md` | "the record on GitHub" is the coordinator's session |
| `BRIEF-coordinate-record.md` | the container question it framed is answered by the session |

Not changed: `DESIGN-coordinated-run-session-record.md` and its PRD (the
coordination pull request is out of scope), `DESIGN-settled-branch-record.md`
(an unrelated record), and the passing mentions in the milestone format
documents.

### The structure test

`state-structure_test.sh`, added early by step 5, replaces
`record-source_test.sh`'s `body_readers` (removed with that suite's rename) with a
check over every file under `skills/coordinate/scripts/` and
`skills/coordinate/koto-templates/`: no file named `record-*.sh` or
`record-codec.jq`; no file naming `record-(common|source|parse|render)\.sh`,
`record-codec`, `Coordinator record:`, `collaborators/`, `docs/disciplines/` or
the five removed `store-*` codes; only its own fixtures may match, and each
pattern has one. Its transitional form, which lands early, refuses any new file
matching the patterns and allows the existing ones by name, so the list can
only shrink.

### The legacy importer

The owner's ruling on an unmoved record (a coordinator still on a GitHub record
that nobody moved, started on the release that removes the record) is a slim,
one-way importer rather than a start-up guard. A guard would tell the operator
to move the record on the earlier release, which means downgrading to migrate;
keeping today's move path would keep most of what this removal deletes.

By the gate's own terms the importer should never fire: the gate holds step 6
until no record still runs on GitHub. It exists for the cases where the gate
fails or is bypassed: a search that misses a record (an organization the
token can't read, an index that lags), a record whose owner reopens or never
closes it, or an operator who starts an old coordinator on the new release
anyway. It is the second protection, not the first, and the removal's grep is
deliberately scoped around it: R16 and the structure test cover
`skills/coordinate/scripts/` and `koto-templates/`, and the importer lives
beside them so that its parser and its one collaborator-permission read stay
out of the skill's normal path, with one call site, until the cleanup feature
deletes them.

- **Where it lives.** `skills/coordinate/legacy-import/`, outside the
  `scripts/` and `koto-templates/` directories the removal's grep and structure
  test cover. It holds its own copy of the parse half of the record codec (no
  renderer), its own reader for the record's marked comments with the
  write-access filter, and its own lookup for an open record: at roadmap scope
  an open issue with the record title in the roadmap's repository whose body
  isn't in the moved shape, at discipline scope an open rotation pull request.
  It calls none of the record writers the removal deletes.
- **When it loads.** It lands before step 6 with no caller, since it removes
  nothing a running coordinator reads and isn't held by the precondition; step
  6 adds the one call. From then, `coordinate-open.sh` calls it once, on a
  fresh start (no `record/meta` for the scope on this host). A resume, a
  carry-across or an import of a session never calls it.
- **What it does, in an order that survives a crash.** It parses the body,
  dropping any `store` Run row (the session is the store now), and writes each
  section key and each writer-authored entry (`record/entries/<n>`) through the
  write core's carry, every key passing `state-schema.jq` and the writer flags.
  It then posts one `moved` note on the record naming the session, unless one by
  the coordinator's login is already there, and writes `record/meta` last. A
  crash at any point before `record/meta` leaves the start fresh, so the next
  start calls the importer again, which rewrites the same sections whole and
  finds the note already posted; after `record/meta`, the next start is an
  ordinary resume. It makes no other GitHub write: no body edit, no close. A
  body that doesn't parse, or an entry author whose permission can't be read,
  stops the start with `record-unreadable <ref>` and writes nothing.
- **Its copies.** The parser, the comment reader and the permission read are
  copied from the scripts step 6 deletes, as they are when the importer lands
  (after step 1 split the codec's checks), and step 6 refreshes the copies if
  those scripts changed in between, so the importer sources nothing step 6 or
  step 7 removes. Its suite
  and scripts are registered in `run-tests.sh`, the bash-floor list and the
  check-skill rows like any other.
- **When it goes.** A later cleanup feature, outside this design's PLAN,
  deletes the directory and its one call, once no GitHub coordinator record and
  no coordination pull request is open anywhere in the organization.

### Registries and CI

The rename updates `scripts/bash-floor/coordinate.list`, the check-skill rows,
`scripts/testdata/rule-coverage.tsv` (the record-find and record-open rows, the
body grammar rows, the discipline handoff rows and the store rows S1 to S19,
retired or repointed), `skills/coordinate/scripts/requires.tsv` (the GitHub
write and codec comments, `koto session import`'s mode), and the path filter
`skills/coordinate/scripts/record-*` in
`.github/workflows/check-coordinate-reconcile-scripts.yml`, which becomes
`skills/coordinate/scripts/state-*`. `docs/disciplines/performance.md` is
removed and the eval fixture
`skills/coordinate/evals/fixtures/rotation-start-carries-reasoning/` is
rewritten to start from a predecessor session.

## Implementation Approach

**Before the precondition**, in any order their dependencies allow, each as
its own pull request:

Every step before the precondition is additive: it adds the session-store
path and leaves the GitHub-store path exactly as it is, choosing between them
by the run's sealed store (`coord-log.sh run-store`), so a coordinator still on
its GitHub record runs the code it runs today.

1. **JSON validation.** Split `record-codec.jq`'s checks into `state-schema.jq`;
   the write core validates the next state's JSON with it, and the renderer
   calls the same functions, so the GitHub path is unchanged. Port each refusal
   case of `record-codec_test.sh` to a JSON case. The schema accepts a `store`
   Run row reading `github` or `session`, as the codec does today; step 6
   narrows it to the legacy `session` row. The same change adds
   `skills/coordinate/scripts/state-*` to the reconcile workflow's path filter,
   so CI runs on the new files from the start.
2. **Outward targets, for session-store runs.** `--on` for `cost` and
   `goal-fit`; `roadmap-status.sh --verdict` and `--reopen` taking `--entry
   <n>` and posting on their roadmap pull request, then pushing the progress
   line; `posted_entry` reading any comment of the roadmap's repository; dedup
   by the coordinator's login; the cost reading guide. A GitHub-store run keeps
   `--entry-url` and posting on its issue until step 6.
3. **Discipline on the session.** Lift `store-discipline` for a new rotation;
   `record/rotation` and `record/reasoning`; the predecessor find and
   `predecessor_carry`; the rotation end; `--import` at discipline scope. A
   rotation on GitHub keeps its machinery until it ends. A first session
   rotation whose discipline's last rotation ran on GitHub carries that
   rotation's committed `docs/disciplines/<name>.md` once, through today's
   handoff reader, so the cutover drops nothing; that bridge goes in step 6.
4. **The session as the default.** A scope with no record starts on its
   session; a GitHub record a start finds stays on GitHub until its owner moves
   it.
5. **The transitional structure test.**

**The precondition** (R20). The PLAN's gate block carries the same commands
and governs if the two ever differ (design step 6 is the PLAN's #984, with
the importer #983 landed before it; step 7 is #985). The gate is spent once step 6 merges; its moved-shape test
stops being runnable once step 7 deletes the parser it uses. No coordinator runs on the
GitHub record when these pass, for every organization a coordinator writes to,
run with a token that can read every repository in it, private ones included:

```bash
gh search issues --owner <org> --state open --match title "Coordinator record:" --limit 1000 \
  --json repository,number --jq '.[] | "\(.repository.nameWithOwner) \(.number)"'
# for each <repo> <n> it lists, from a checkout of main before step 6 merges:
gh issue view <n> --repo <repo> --json body --jq .body \
  | bash skills/coordinate/scripts/record-parse.sh --container issue - \
  | jq -e '([.holdings, .deferrals, .side_effects, .reversals, .holds, .standing, .work] | all(. == null or . == []))
           and (has("decisions") | not)
           and ([(.run // [])[] | "\(.key)=\(.value)"] == ["store=session"])'
gh search prs --owner <org> --state open --match title "rotation" --limit 1000 \
  --json repository,number,title \
  --jq '.[] | select(.title | test("^docs\\(coordinate\\): .+ rotation [0-9]{4}-[0-9]{2}-[0-9]{2} to ")) | "\(.repository.nameWithOwner)#\(.number)"'
```

The first search lists every open roadmap record; each must then pass the
moved-shape test that follows it, the same test `record-source.sh`'s `rs_moved`
applies (every section empty, Decisions absent, and a Run section holding only
the `store session` row), because a record whose owner wrote the `store
session` row still holds its state until its next start moves it. A record that
fails the test, or a body that doesn't parse, keeps the gate shut. The second
search lists open rotation pull requests. A third condition can't be searched: every discipline
whose last rotation ran on GitHub has started a rotation on the session (which
carried its handoff file through step 3's bridge), or its owner has retired it.
GitHub's search index can lag an edit, so both searches run again immediately
before step 6 merges, at least an hour after the last owner closed or moved a
record. A record closed while its coordinator is still tearing down counts as
finished: its owner closes it only after the teardown. An owner ends either by moving the coordinator at its
next start, by letting a rotation end, or by closing the issue or pull request.

**After the precondition:**

6. **Remove the GitHub backend and the store choice.** The title search, the
   authority read, issue and pull request creation and edits, the comment
   listing and the permission read, the moved shape, `record-move.sh` and
   `record_move`, `--store`, `STORE` and new `store` Run rows, the GitHub-store
   branches of steps 2 and 3 (`--entry-url`, posting on an issue, step 3's
   handoff bridge), the issue number in `run-facts` and `run-store` itself, the
   GitHub-mode `--scope --name --repo --ref` call sites in `quiet-check.sh` and
   `holding-link.sh`, `record-write.sh --close` and `posture-read.sh`'s use of
   it, the discipline handoff and rotation pull request machinery, and
   `docs/disciplines/performance.md`. The koto feature probe moves into
   `coordinate-open.sh` as the start-up check that refuses
   `store-unsupported`. The legacy importer has already landed, dormant; this
   step adds the opener's one call into it, so no release removes the GitHub
   record without it.
7. **Remove the codec's markdown half and rename.** Convert the writers and the
   core to `--state-file` first, in the same pull request, since the parse and
   render scripts can't go while a writer still hands the core a body; then
   delete `record-parse.sh` and `record-render.sh` and rename every survivor to its `state-*` name with its
   callers, tests, registries and CI filters; the full structure test; the
   skill's text, `references/record-template.md` rewritten as
   `references/state-keys.md` (each key's JSON and its writer), and the other
   references. The callers to change are every file `grep -l` finds for the
   removed names at the change's base commit, not a list written now.
8. **The documents.** The amendments and the supersession, in their own pull
   request after step 7, so each describes what has landed and none waits on
   the rename's review.

Verification for each: the coordinate suites (`run-tests.sh`, and `--engine`
where the change touches a start or a move), the bash-floor leg, and `shirabe
validate` over the changed documents.

## Security Considerations

**The private-repository and token checks keep their reach, and follow the
destination.** They move from the renderer to `state-schema.jq` and the write
core, walk every string in the state rather than a list of columns, and still
run on every value that can leave the host. After the removal fewer values leave
it: only outward entries, which `state-entry.sh` checks before posting. Since an
entry can now go to any of the run's repositories, the check keys on the
destination's visibility, so an entry naming a private repository is refused
for a public destination even when the host is private. `roadmap-status.sh`
posts through `state-entry.sh` for the same reason. `--on` and every stored
comment URL are checked against fixed patterns before they reach `gh`.

**The collaborator-permission read goes, and its job is narrower.** It decided
which comments on a coordinator issue were entries; with no comment stream
there is nothing to authorise. The places a GitHub comment still stands in for
an entry (the retry's dedup, a new progress line's comment, the cost reading
guide) accept only the coordinator's own login, which is stricter than write
access, and the dedup fails closed when the login can't be read.

**The bucket and the local store are now the only store.** The session store's
residual risk, recorded in `DESIGN-coordinator-session-record.md`, stays: anyone
holding the bucket's credentials or able to write the local store can rewrite a
session, and the store needs the same access control as the repositories whose
work it holds. The removal takes away the GitHub copy that a hand edit couldn't
touch without leaving a trace. The reconcile pass re-checks Holdings against
GitHub before acting, so a forged holding can't merge anything GitHub doesn't
show. It can't re-check a Standing approval or a hold's absence, so a
discipline carry binds its predecessor by name pattern, provenance, discipline
and host, refuses a predecessor another session of the discipline already
names in its `record/rotation` (so one predecessor is never carried twice),
stops on any ambiguity, and reports every hold and Standing row it carried to
the owner before the run acts on them.

This is residual risk the owner accepts by accepting this design: with the
GitHub copy gone, a Standing approval, the absence of a hold and the carried
reasoning can be rewritten by anyone with write access to the session store,
and nothing outside the store can contradict them.

**The legacy importer reads untrusted bodies, once.** A coordinator whose state
is still on an unmoved GitHub record, started on the release after step 6, would
otherwise start empty, without that record's holds, and could merge past one.
The precondition is the first protection; the importer (Solution Architecture)
is the second. It reads a body and comments from GitHub, which anyone with write
access could have edited, so everything it writes goes through
`state-schema.jq` and the write core like any other write, entries count only
from authors with write access (the one collaborator-permission read left in
the repository, inside the importer), and a body that doesn't parse stops the
start rather than importing part of it. Its one GitHub write is the moved note.

**`--confirm` reads a comment by id within one repository.** Widening
`posted_entry` from one issue to any comment of the roadmap's repository is
bounded by the marker, kind, text and hash checks it already makes, and a new
progress line's comment must sit on the roadmap pull request its Side effects
row names. A comment elsewhere in the repository can't confirm an entry it
doesn't reproduce byte for byte.

**`--confirm` also checks the comment's author.** For a progress line written
after the removal, a comment confirms an entry only when its author's login is
the coordinator's (compared without case), in addition to the marker, kind,
text and hash. A line written before the removal is confirmed as today, which
checked marker, kind, text and hash and never the author. For both, the issue or
pull request a comment sits on is read from the API's answer (`issue_url`), not
from the URL's path.

**Carried state is data, and the owner sees it first.** `record/reasoning` and
the carried Standing rows were written by an agent and are read by the next
rotation's agent as data, never as instructions. A rotation that started from a
carry reports what it carried and takes no dispatch or merge until the owner's
go-ahead is recorded as a Standing row, the way a person's word is recorded
today. Only a go-ahead set in this run counts: carried Standing rows, a carried
go-ahead or approval included, never satisfy that gate.

**Outward entries are public where their destination is.** A cost entry posted
on a public pull request is public content. One whose text fails the scan for
its destination is not posted: it stays in the session and the archive, and
the capture says so.

**The precondition fails closed.** A search error, a result count at the limit,
or an organization the token can't read leaves the gate shut. The search's
output can name private repositories, so it goes in a report, never in a public
pull request or issue.

**No new input reaches a command.** The new keys hold dates, a repository, a
session name and prose; the session name is checked against the scope's
`coordinate-<slug>-<stamp>` pattern before it reaches `koto`, and the prose is
only ever read as JSON. The one new path is the state file a writer hands the
core: it is created with `mktemp` in the writer's private working directory
(mode 0600, as the body file is today), read once by the core, and removed with
the directory.

## Consequences

### Positive

- One store: a change to what a coordinator remembers is made and tested once,
  with no renderer, parser or body budget.
- Discipline coordinators get the session, its resume and its import.
- The grep and the structure test make the removal checkable and keep it.
- Outward entries sit on the item a person reviewing that change already reads.

### Negative

- A large rename touches nearly every coordinate script and test, in one change.
- A cost reviewer reads one pull request per unit instead of one issue per
  scope, and a unit with no pull request or issue has its cost only in the
  session and the archive.
- A slim importer keeps a parser for the old body format alive, outside the
  skill's normal path, until a later cleanup feature removes it.
- A roadmap pull request for a verdict carries two commits instead of one.

### Mitigations

- The rename lands last and alone with its registries, when nothing reads the
  old names, and the transitional structure test stops new `record-*` files
  meanwhile.
- The cost reading guide gives the command for a scope's set.
- The precondition is checked before the removal merges, and a record nobody
  moved is imported at its next start rather than lost. The importer is one
  directory with one call site, so its removal is a deletion.
- `roadmap-status.sh` pushes the progress commit before it reports, so the pull
  request is never handed over without it.
