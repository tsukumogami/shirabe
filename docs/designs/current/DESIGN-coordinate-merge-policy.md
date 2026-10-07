---
schema: design/v1
status: Current
upstream: docs/prds/PRD-coordinate-skill.md
problem: |
  The coordinate skill's land step merges a pull request on a verified CI
  board and a posture that permits the merge. The merge contract this
  workspace actually runs on is stricter and lives outside the skill: a
  unanimous panel of three reviewers at the head, a squash message built from
  the first part of the body, and a person who merges. Because nothing in the
  land step reads the worker's own review round, every merged pull request got
  two three-seat panels at its head, the worker's and the merger's. A panel
  claim is also only as good as its wording: one worker called a serial review
  in a single agent independent panels. And a hold on a merge is a note a
  coordinator remembers, so one pull request merged before its hold took
  effect.
decision: |
  The worker's round is the panel, written as a table under a `## Review
  panel` heading in the body's second part: one row per seat with its role,
  model, a run id unique to that seat, its pass or fail verdict and the head it
  reviewed. One script, `panel-evidence.sh`, parses it. `verify_board` refuses
  a table that breaks the format, seats that can't be told apart included, so
  no verified head is recorded on such a claim. `land` re-reads the body live
  and refuses, with a reason, a head that has no table, fewer than three
  distinct seats, any verdict but pass, or a reviewed head that differs from
  the head by more than merge-ins of the base branch. It never runs a panel.
  The same check runs the repository's mechanical body checks and builds the
  squash message from the title and Part 1; the merge builds it again from the
  live body and carries it, and a merge the workspace reserves goes to the
  person with it. The posture stays what `posture-read.sh` reads from the
  workspace's permission rules and hooks. The coordinator's one judgment at
  the step is goal fit against the brief, never a panel. A hold becomes a
  Holds row in the record with a condition `land-check.sh` evaluates live, and a merge that
  happens while a hold is unmet is written to the record with who made it.
rationale: |
  Reading evidence that already exists is the cheapest way to stop paying
  for a second panel, and a table is the one form both a reviewer and a
  bash 3.2 parser read without help. Seat verdicts are closed (pass or
  fail), so aggregating them moves into the script; the seats' judgment of
  the code and of Part 1 against the diff stays open and stays with sonnet
  seats, because the decider that would replace them hasn't earned trust in
  its shadow trial. Allowing base-branch merge-ins between the reviewed head
  and the head keeps the commonest move after a round (merging main in) from
  costing a new round, and a check on the files each merge-in changed stops an
  edit to a file the base branch never touched from riding in with one. The
  posture is already read from the hooks that enforce it, so a second setting
  could only disagree with them.
---

# DESIGN: coordinate-merge-policy

## Status

Current

Decisions 1 to 5 and 7 are implemented. Decision 6, holds, follows in its own
pull request, and until it lands `land_merge` keeps `merge: held`. The goal-fit
state ships without its shadow decider: the decider needs a modes-table row and
forty golden fixtures, which follow once `goal_fit` has run on real pull
requests.

## Context and Problem Statement

The `coordinate` skill drives a roadmap or a discipline rotation by handing
units of work to worker sessions and landing what they push. Its land step is
three states in `skills/coordinate/koto-templates/coordinate.md`: `land`, whose
check `land-check.sh` re-reads the head against the one `verify_board`
verified, reads the merge state and reads the merge posture; `land_merge`,
where the coordinator runs `land-merge.sh`, which calls the execute skill's
`merge-exec.sh`, which merges with `--match-head-commit`; and `merge_confirm`, which reads
the changed files back from the default branch.

It satisfies the skill's PRD (`docs/prds/PRD-coordinate-skill.md`): where the
workspace permits the merge the coordinator merges once it has verified the
work, and otherwise it hands the human a merge-order table. This design narrows
what "verified" means at that step.

That is a CI board and a permission check. The merges in this workspace follow
a contract the skill doesn't carry. The repository owner granted one session
the merge on 2026-09-27, standing until revoked, after a panel of at least
three reviewers agrees, with a plain squash message built from the first part
of the pull request body; the first merge under it was tsukumogami/shirabe#457
(the coordinator-session record, 2026-09-27, the merge grant and its first
merge). The dogfooding readiness check on 2026-09-28 found that the skill
"would merge on a verified board with no reviewer panel and no Part 1 squash
message" (the record, 2026-09-28, dogfooding readiness). The first dogfooded
pull request, tsukumogami/shirabe#489, shows why the panel matters: CI was
green throughout, and only the panel caught statements the committed data
contradicted (the record, 2026-09-28, the first dogfood merge).

Four problems follow, each named in the coordinator roadmap's Feature 8 and its
amendment of 2026-10-01.

**Two panels per head.** The worker runs a three-seat round before it reports
ready, and the merger ran its own three seats because nothing it trusted read
the first. Panels are the dominant spend of the loop: about 480k tokens for the
seats on tsukumogami/koto#292 and 410k on tsukumogami/niwa#346 (the
coordinator roadmap's Progress, review-panel cost). On 2026-10-01 the
repository owner directed that features making the coordination cheaper be
adopted first, and from 13:50 that day the merger accepted the worker's round
as the panel when the body carried each seat's verdict and the sha it
reviewed, reading only the delta when the head had moved (the record,
2026-10-01, the directive on cheaper running). This feature makes that the
land step's own behaviour.

**Panel claims that overstate.** On 2026-09-30 the body of
tsukumogami/niwa#346 claimed independent panels for a serial review in one
agent, the second self-reported panel that night to overstate its
independence (the record, 2026-09-30, the niwa#346 panel). A claim the land
step reads has to say which seats ran.

**The squash message.** The org's repositories squash-merge with the pull
request body as the commit message, so a merge with no message given lands the
whole body, reviewer context included. The merger builds the message from Part
1 by hand today.

**Where the merge is reserved, and holds.** The strategy's autonomy decision
puts the bound on what a coordinator may do in the workspace's declared posture
and the hooks that enforce it, never in the skill. A hold is a different thing:
a condition on another lane's state ("hold the release until #346 merges").
One pull request was "verified and held, to merge only on the human's go
signal" and merged before the hold took effect (the coordinator roadmap,
Feature 8's amendment of 2026-10-01). Today the skill's only hold is
`land_merge`'s `merge: held`, which is the coordinator's word that the human
said so.

## Decision Drivers

- **Never run a second panel.** The land step reads evidence; it doesn't
  produce it.
- **A script reads it.** The evidence's form must be parseable in bash 3.2 with
  jq, the skill's floor, and must not depend on a model's reading.
- **The workflow reads, the coordinator writes.** The template's one rule: no
  check reads what the coordinator writes, except the record on GitHub through
  its codec. Evidence lives in the pull request body, which the worker wrote and
  GitHub serves.
- **Closed checks move to scripts; open judgment stays with seats.** The
  repository owner's view of 2026-09-28 was that reviewer verdicts are pass or
  fail, so that logic could move to a decider and cut token cost (the record,
  2026-09-28, the coordinator's own usage). The strategy's entry of 2026-09-29
  bounds it: the three-seat panel stays required until the owner rules on the
  review-shadow trial (tsukumogami/shirabe#563), and until then a decider pass
  approves nothing.
- **No permission rule of the skill's own.** The posture is the workspace's.
- **Cheap where it's common.** Merging the base branch in after a round is the
  commonest change to a head that's been reviewed.

## Considered Options

### Decision 1: The evidence's form and who reads it

The body's second part carries one table under a fixed heading:

```markdown
## Review panel

| Seat | Model | Run | Verdict | Reviewed head |
|---|---|---|---|---|
| architect | sonnet | <run id> | pass | <40-hex sha> |
| maintainer | sonnet | <run id> | pass | <40-hex sha> |
| pragmatic | sonnet | <run id> | pass | <40-hex sha> |
```

`Seat` is the seat's role; `Model` the model it ran on; `Run` an identifier
unique to that seat's run, which an auditor can match against the seat's own
output: an agent or session id, or a review comment the seat's verdict was
posted as, written `comment-<id>`; `Verdict` is `pass` or `fail`; `Reviewed
head` the full sha the seat read.

`panel-evidence.sh` reads it exactly this way. Part 1 is the body above its
first top-level `---` line outside a code fence, as in the repository's PR-body
rule (`references/pr-body-conformance.md`); it becomes the commit message and is
never searched. A body with no such line has no Part 2 and no evidence. In Part
2, the first line outside a fence that reads exactly `## Review panel`
(trailing spaces ignored) starts the evidence. The next non-blank line must be
the header row, whose cells, trimmed and compared without case, are `Seat`,
`Model`, `Run`, `Verdict`, `Reviewed head` in that order; then a separator row;
then the seat rows, up to the first line that doesn't start with `|`. Cells are
trimmed, and a cell wrapped in backticks is read without them.

It prints JSON: `absent` (no heading), `ok` with the seats, or `malformed` with
the first rule broken. Rows are checked in order, and within a row the rules in
the order below; the table-wide rules (the last three) come after every row
passes:

| Reason | Rule broken |
|---|---|
| `no-table` | the heading isn't followed by a table |
| `header` | the header names other columns, or no separator row follows |
| `no-rows` | no seat row follows the separator |
| `control` | a cell holds a control character |
| `cells` | a row hasn't five non-empty cells |
| `run` | a Run doesn't match `^[A-Za-z0-9][A-Za-z0-9._:/#-]{3,}$` |
| `verdict` | a Verdict isn't `pass` or `fail` |
| `head` | a Reviewed head isn't a full lowercase sha |
| `seat-repeated` | two rows name the same Seat |
| `run-repeated` | two rows name the same Run |
| `heads-differ` | the rows name different reviewed heads |

Distinct seats means distinct Seat, compared without case, and distinct Run,
compared exactly. A table with a repeated
Seat or Run is a panel claim whose seats can't be told apart, the
tsukumogami/niwa#346 case.

Two steps read it. `verify_board` (`board-record.sh`) reads the body once the
board is green and prints a new verdict, `unevidenced`, for any `malformed`
table; the verified head goes into the holding only at `verified_confirm`,
after a `verified` verdict, so a holding is never recorded on such a claim. An
`absent` table doesn't stop verify, so a pull request can be verified before
its round. `land` (`land-check.sh`) re-reads the body live and refuses anything
but `ok` with at least three seats, all `pass`, at a fresh reviewed head
(Decision 2).

Alternatives considered:

- **A fenced JSON block.** Easier for a script, harder for the reviewer
  reading the body, and the panel's verdicts are read by people as much as by
  the land step. Rejected.
- **GitHub reviews (approvals).** Every seat posts through the worker's own
  account, and GitHub doesn't let an author approve their own pull request.
  Rejected.
- **A check run per seat.** Needs an app identity per reviewer to mean
  anything, which the workspace doesn't have. Rejected.
- **Checking a seat's model against a list.** The sonnet rule is a ruling on
  who launches reviewers, not a merge precondition; the Model column is
  recorded so a merger can see it. Not enforced.

### Decision 2: How far the reviewed head may sit from the head

With reviewed head R, live head H and base branch B (the pull request's
`baseRefName`): if R equals H the evidence is fresh. Otherwise `land-check.sh`
walks H's first-parent chain back toward R, one commit read per step
(`repos/<repo>/commits/<sha>`), and at each commit C:

1. C must be a merge with two parents P1 and P2; a commit with one parent is a
   change nobody reviewed.
2. P2 must already be on B: the comparison of B with P2 reads `behind` or
   `identical`.
3. The files C changed against P1 (the comparison of P1 with C) must be among
   the files B changed between its merge base with P1 and P2 (the comparison of
   P1 with P2, which GitHub computes from the merge base).

Then the walk steps to P1. Reaching R is fresh. Anything else is `stale`: a
step that breaks a rule, more than ten merge-ins, or a comparison whose file
list is at GitHub's limit of 300 files and so can't be read whole.

The file rule catches an edit to a file the base branch never touched riding in
with a merge-in. An edit inside a file the base branch did change, a conflict
resolution included, passes; that residue is the same one the hand rule of
2026-10-01 accepted when it let a main merge-in pass as is.

Alternatives considered:

- **Refuse any difference.** Forces a new three-seat round after every
  merge-in of main, the commonest move after a round and the one the
  2026-10-01 rule let through as is. Rejected.
- **Accept any merge commit.** An edit to a file main never touched can ride
  in with a merge-in. The file rule catches that for four reads per merge-in.
  Rejected.
- **Read the comparison of R with H as one list.** It lists every commit
  reachable from H and not from R, including the base branch's own commits
  brought in by the merge, so it can't tell a merge-in from new work. Rejected
  in favour of the first-parent walk.
- **Review the delta with one seat, as the hand rule does.** The land step
  never runs a panel. It refuses with the reason, and the worker's next round
  covers the delta.

### Decision 3: Which checks are closed, which stay with a seat, and the one judgment left

The land step has two reads, as the repository owner ruled on 2026-10-07: the
worker's seat evidence for correctness and quality, checked deterministically
from the body, and the coordinator's own judgment of goal fit against the brief
(the record, 2026-10-07, the goal-fit ruling).

Closed checks, each a script, run in `land-check.sh` before the posture:

| Check | Source |
|---|---|
| Every job at the head concluded green, read job by job | `verify_board`, unchanged |
| The evidence is present, its seats distinct, at least three, all `pass` | `panel-evidence.sh` |
| The reviewed head is fresh | Decision 2 |
| Conventional Commits title, one separator, non-empty Part 1, no attribution, no heading in Part 1 | `shirabe validate --pr-body`, the repository's rule (`references/pr-body-conformance.md`) |
| The built message is non-empty and carries no attribution or session link | `squash-message.sh` (Decision 4) |

`shirabe validate` is the plugin's own binary, found on PATH as every other
skill that calls it finds it, and declared in the skill's `requires.tsv` so the
load-time preflight names it when it's missing. A failed call is a failed read
(exit 2), whose fallback says to fix the cause and tick again.

Open judgment, which stays with the seats: whether the code is right, whether
Part 1 describes the diff and only the diff, and whether the documents agree
with themselves and with the code. The review-shadow tool grades the second of
these with a model (its criteria rs-007 and rs-008) and is in trial; on
2026-10-01 its tally covered a third of the blocking findings the panels
upheld, so it isn't a seat (the record, 2026-10-01, the directive on cheaper
running).

So the part of the repository owner's 2026-09-28 view that is true today is
taken: a seat's verdict is a closed field, and aggregating three of them is a
script, not a fourth reviewer. No seat's judgment moves to a koto decider in
this feature; a decider is a model too, and the strategy says a decider pass
approves nothing until the trial is ruled on.

The judgment left is goal fit: does the pull request deliver what its unit
asked, in the way intended, without stopping short, drifting, or deciding
what the lane didn't? That question isn't about the code's quality, which the
seats answered, and it needs the brief, which only the coordinator holds. It is
the coordinator's one call at the land step (Decision 7), never a panel.

### Decision 4: The squash message

`squash-message.sh` builds the message from a title and a body: the subject is
the title; the body is Part 1 with markdown removed (heading, blockquote, list
and task-box markers, table rules, bold, italic, code ticks and HTML comments;
a table row's cells joined with commas; a link rewritten as `text (url)`).
These are the rules of the merger's own message script, ported to bash and jq.

`land-check.sh` runs it at the head it checks, so a body whose message can't be
built is `unready` before anyone reaches the merge, and stores the message as
data in a new detail key, `coord/land.json`, for the merge-order table. It is
not part of the sealed token: `permit <pr> <sha>` keeps its three fields,
because `land-merge.sh` and `merge-confirm.sh` both read it that way.

`land-merge.sh` builds the message again from the live title and body,
immediately before the merge, and hands it to `merge-exec.sh` as a file. The
body can change between the check and the merge; the rebuilt message is the
one the person reading the pull request sees at that moment, and the builder's
refusals apply again: a refusal there is `land-merge.sh` refusing (exit 10), so
the coordinator submits `merge: failed` and the run goes to `failure`, as any
refused merge does today. The close-out merges (`land-merge.sh --closeout`, for a
rotation's or a predecessor's record pull request) build theirs the same way:
the record's renderer writes a fixed Part 1 and a single `---`, and those pull
requests carry no panel, since they hold the coordinator's own record, not a
unit's work.

Carrying it needs `merge-exec.sh` to take an optional fourth argument, a
message file, passed as `--subject` and `--body-file` when the method is
`squash` or `merge`; a `rebase` merge has no message of its own, and the file is
ignored. Its header and its test, which pin the exact `gh pr merge` call, change
with it. That script is the execute skill's, outside this feature's directory,
so the implementation asked for the change explicitly, and the process owner
approved it on 2026-10-07 as the one change outside `skills/coordinate/`; it
lands with the land check. Without a message `land-merge.sh` refuses a
permitted merge, close-outs included, rather than let the repository's default
land the whole body.

"Graded against the diff" splits along Decision 3: the mechanical checks are
the land step's, and whether the text describes the diff is a seat's.

Alternatives considered:

- **Seal the message's digest into the token.** It would bind the merge to the
  exact message the check saw, at the cost of a four-field token every reader
  of the land capture would need to change. Rebuilding at merge time gives the
  same refusals on the current text. Rejected.
- **Bind the evidence to a digest of Part 1.** It would make a body edit after
  the round visible to the land step. But fixing a stale Part 1 is expected to
  happen by editing the body, not by pushing a commit. Declined for now; it is
  the next step if a Part 1 edited after its round ever lands wrong.
- **Let the repository default carry it.** The org's repositories use the
  body as the squash message, so the default lands Part 2 with it. Rejected.

### Decision 5: Where "the human merges" lives

It lives where `posture-read.sh` already reads it: the permission rules
(`deny`, `ask`, `allow`, `defaultMode`) and the PreToolUse hooks in
`.claude/settings.json` and `.claude/settings.local.json` at the instance root
and the workspace root, which the workspace manager writes from the workspace's
own configuration. No new setting is added. The land step reads it at the start
and again at `land`, narrowed to the stricter of the two, and `land-merge.sh`
reads it a third time before it calls anything.

| Merge posture at `land` | What the land step does |
|---|---|
| `permit` | goal fit, then `land_merge`: `land-merge.sh` merges at the verified head with the built message |
| `deny` | goal fit, then ready and handed to the person: `surface` with the merge-order table, the message and where the evidence is; the holding parks |
| `confirm` | the same as `deny`: a step behind a person's confirmation is a person's |

An unreadable posture never reaches `land` as such. At the start it sends the
run to `posture_ask`; at `land`, an unread read becomes `confirm` unless the
human's answer permitting the merge is on the record, as `bl_merge_posture`
does today.

The workspace's gate hook denies `gh pr merge` and the API merge endpoints in
every applied instance unless the instance is the one named as exempt (the
record, 2026-09-28, the gate-online hook; the exemption is
tsukumogami/dot-niwa#22). The reader can't evaluate an exemption held in the
environment, and a hook that names the merge command is read as `confirm`, so
every coordinator in this workspace hands a ready pull request to the person
and never merges. The evidence and message checks run before the posture read, so a
`deny` or `confirm` verdict now means the pull request is ready, not just that
its board is green.

Alternatives considered:

- **A `merge_by = "human"` key in the workspace configuration.** A second
  declaration of something the hook already enforces, which could only
  disagree with it. The strategy puts the bound in the posture the workspace
  declares once and hooks enforce. Rejected.
- **Evaluating the hook's exemption.** The reader would need the hook's
  environment and the instance's name and would be modelling the hook's logic
  in a second place. Rejected; reserving is the safe reading.

### Decision 6: Holds as conditions

A hold is a row in a new Holds section of the record:

| Hold | On | Until | Set by | Set | Lifted |
|---|---|---|---|---|---|
| `<short name>` | `owner/repo#n` | `merged owner/repo#m`, `tag owner/repo vX.Y.Z` or `lifted` | who asked for it | time | blank, or who lifted it and when |

The three conditions are the three kinds of hold the coordinators recorded:
merges held until another lane's pull request merged, merges held until a
release was tagged, and a merge held until the human said go (the coordinator
roadmap, Feature 8's amendment of 2026-10-01).

`land-check.sh` reads the holds on the pull request it checks, after the
evidence and before the posture, and evaluates each condition live: `merged`
reads the named pull request's state, `tag` reads the tag, and `lifted` is met
only when the row's Lifted cell names who and when. An unmet hold, or one whose
condition can't be read, gives `held <pr> <sha>`, which routes to `surface` and
sets the holding's Phase to `held`, the word's existing meaning. The coordinator
reports the hold as held because the check just read it, not because it
remembers it. `lifted` rests on a cell the coordinator writes when the person
lifts the hold, the same trust as today's `merge: held`, but now on the record
with who and when.

It's a verdict of `land`'s own check, so it is a gate in the template's sense:
the same sealed capture and the same non-overridable gate every check state
uses. A separate gate on `land` would be a second reader of the same facts.
`land_merge`'s `merge: held` goes in the same pull request that adds the hold
read, never before it; a hold the human directs becomes a Holds row with
`lifted`, written through the record's scripts like any other row.
`record-confirm.sh`, which today sets Phase `held` only for a `surface` entered
from `land_merge` on `merge: held`, takes the new origin, `land` on `held`, in
that same change.

When `merge_confirm` or `merged_facts` confirms a merge, it reads who merged it
(`mergedBy`), and if a hold on that pull request was unmet, the coordinator
writes a Reversals row: the hold, "merged while held", the time, and the merger
as GitHub names it; `record-confirm.sh` expects that row before the loop goes
on. So the record says who merged what it held.

A held pull request goes back through `verify` when the event its hold names
arrives (the merge or tag notification, or the person's word), as a parked one
does today; nothing re-enters `land` on a timer.

The record's container and its stored set of person-owned events are Feature 7
of the coordinator roadmap. The Holds section is defined here because the land
step's read needs a form; it moves with the rest of the record when Feature 7
settles the container.

Alternatives considered:

- **A directive line telling the coordinator to check holds.** Prose is what
  let the hold on the merged pull request fail. Rejected.
- **Holds in a context key.** A check would be reading what the coordinator
  wrote, which the template's rule forbids. Rejected.

### Decision 7: Goal fit, the coordinator's one call

A new state, `goal_fit`, follows `land` on `permit`, `deny` and `confirm`. The
coordinator reads the pull request against the unit's brief and submits `fit:
fits`, `fit: fits_with_follow_ups` or `fit: gap` with a rationale, the three
outcomes of the repository owner's ruling: merge, merge and file the follow-ups,
or correct first. `fits` and `fits_with_follow_ups` go on by the land verdict it
already has: a gate on `goal_fit` re-reads the sealed LAND capture through
`coord-verdict.sh`, the way `reconcile` re-reads the start's posture, and routes
`permit` to `land_merge` and `deny` or `confirm` to `surface`; with follow-ups,
the coordinator files each as an issue where the workspace lets it, or proposes
it in its report up, and names it in the hand-over. `gap` goes to
`rebrief`, whose brief says what to correct or what follow-up to propose.

The question is decider-shaped, so the field is meant to carry a decider in
shadow mode, as `classify_report`'s does: its answer recorded beside the
coordinator's and never acted on. Its inputs would be the pull request's
changed files, message and evidence from `coord/land.json`, which `land-check.sh`
writes, and the brief input the coordinator wrote at dispatch
(`brief_input.json`), acceptable for a decider nothing acts on. It follows the
first implementation, once there are real goal-fit calls to build its fixtures
from. The coordinator's answer routes.

It runs after the closed checks, so the judgment is spent only on a pull
request that is otherwise ready, and before the posture's routes, so a merge
the person makes reaches them already judged.

Alternatives considered:

- **A reviewer seat for goal fit.** A seat doesn't hold the brief or the
  lane's intent, and it's the cost this feature removes. Rejected.
- **Folding it into `land_merge`.** A reserved merge never reaches `land_merge`,
  so the person would get it unjudged. Rejected.

## Decision Outcome

The land step reads the worker's round from the body and never runs one;
`verify_board` refuses a malformed panel claim so no holding records it; the
squash message is built and graded mechanically and carried by the merge; the
coordinator makes one judgment, goal fit; the posture stays the workspace's
permission rules and hooks; and a hold is a record row the check evaluates live.

What the roadmap's Feature 8 asks for that this declines:

- **A seat's id must be an agent or session id.** Broadened to any run
  identifier an auditor can match, a review comment included (`comment-<id>`),
  since a worker can't always publish an agent's internal id, and a comment is
  public and checkable.
- **Refusing a panel claimed in prose.** "Independent panels" in a sentence
  isn't something a script can decide. The table is the only claim the land
  step reads, and a body that claims a panel only in prose has no table, so
  `land` refuses it anyway.
- **A separate refusal in the script that writes a holding.**
  `record-holding.sh` writes rows the coordinator builds; giving it a body read
  would make a write script a check. The refusal at `verify_board` covers the
  only path by which a verified head enters a holding.
- **Grading Part 1 against the diff by a decider.** It stays a seat's until the
  shadow trial is ruled on.
- **The release lane.** A release is only an event a hold names (`tag`); the
  lane stays with the workspace coordinator, as the roadmap says.

## Solution Architecture

### The land check, in order

`land-check.sh` keeps its first steps (the verify capture, the head re-read,
the merge state's `dirty`), then:

1. reads the body, title and base branch at the head (`gh pr view --json
   mergeStateStatus,body,title,baseRefName,files`, the read it already makes,
   widened);
2. `panel-evidence.sh` over the body: not `ok`, fewer than three seats, or a
   `fail` verdict is `unready <pr> <sha>`;
3. freshness (Decision 2): `unready` with reason `stale`;
4. `shirabe validate --pr-body` with the title, then `squash-message.sh`: a
   failure is `unready` with reason `body-checks` or `message`;
5. holds (Decision 6, second implementation pull request): `held <pr> <sha>`;
6. the posture: `permit`, `deny` or `confirm <pr> <sha>`.

It stays read-only on GitHub. `coord/land.json`, a new detail key listed in the
template's key list, carries the reason, the evidence as parsed, the
freshness walk and the message.

`unready` routes to `rebrief`: what's missing is the worker's to fix (run the
round, fill the table, fix Part 1). `report_topic` is still set at `land`,
since only the edges back to `wait` clear it, so the re-brief reaches the
worker whose report was verified.

### The template

```
verify_board --verified--> verified_confirm --> land
verify_board --unevidenced--> rebrief
land --permit|deny|confirm--> goal_fit --fits(+follow-ups),permit--> land_merge
                                      --fits(+follow-ups),deny|confirm--> surface
                                      --gap--> rebrief
land --unready--> rebrief
land --held--> surface
```

The diagram shows only what changes: `land`'s `moved` and `dirty` arms stay.
`land_merge` keeps `attempted`, `failed` and, until the hold read lands,
`held`.

### New verdict words

| Word | State | Code | Route |
|---|---|---|---|
| `unevidenced` | `verify_board` | 79 | `rebrief` |
| `unready` | `land` | 83 | `rebrief` |
| `held` | `land` | 85 | `surface` |

### Files

| File | Change | Pull request |
|---|---|---|
| `skills/coordinate/scripts/panel-evidence.sh` | new: parse the Review panel table | 1 |
| `skills/coordinate/scripts/squash-message.sh` | new: build the message | 1 |
| `skills/coordinate/scripts/board-lib.sh` | new: `bl_reviewed_fresh`, the freshness walk, inside the land check's 24-second read budget | 1 |
| `skills/coordinate/scripts/land-check.sh` | evidence, freshness, message before the posture | 1 |
| `skills/coordinate/scripts/board-record.sh` | `unevidenced` for a malformed table | 1 |
| `skills/coordinate/scripts/land-merge.sh` | rebuild and carry the message, close-outs included | 1 |
| `skills/coordinate/scripts/coord-verdict.sh` and `coord-verdict-table_test.sh` | the new words | 1 |
| `skills/coordinate/koto-templates/coordinate.md` and `coordinate.mermaid.md` | the new arms, `goal_fit`, the land directives | 1 |
| `skills/coordinate/references/verification-checklist.md`, `references/brief-template.md`, `scripts/render-brief.sh` | the merge-order table names the evidence and message; the worker's body carries the table | 1 |
| `skills/coordinate/requires.tsv` | `shirabe validate --pr-body` | 1 |
| `skills/execute/scripts/merge-exec.sh` and its test | an optional message file, approved as the one change outside `skills/coordinate/` | 1 |
| `skills/coordinate/scripts/record-codec.jq`, `record-render.sh`, `record-parse.sh`, `references/record-template.md` | the Holds section | 2 |
| `skills/coordinate/scripts/land-check.sh` | the hold read | 2 |
| `skills/coordinate/scripts/merge-confirm.sh`, `merged-facts.sh`, `record-confirm.sh` | the merger, and the Reversals row for a merge made while held; Phase `held` from `land` | 2 |
| `skills/coordinate/koto-templates/coordinate.md`, `SKILL.md`, `references/loop.md`, `scripts/reconcile-report.sh`, `scripts/testdata/rule-coverage.tsv` | `land_merge`'s `merge: held` goes | 2 |

## Implementation Approach

Two pull requests after this one.

1. **Evidence, freshness, message, posture, goal fit.** Decisions 1 to 5 and 7,
   with unit tests for the parser, the builder and the freshness walk, and
   engine cases in `board-land_engine_test.sh`: evidence at the head merges;
   no evidence, an unidentified seat, a `fail` verdict and a stale reviewed
   head each refuse with their reason; a reviewed head one main merge-in behind
   passes; the message equals the fixture's Part 1; a denied or confirm-only
   posture hands the ready pull request to the person.
2. **Holds.** Decision 6: the record section and its codec, the land read,
   the Reversals write after a merge made while held, and engine cases for each
   condition. It lands after the first, and coordinates with Feature 7's
   schema changes because both touch the record.

Template changes run the evals for every scenario that reaches a changed state.

## Security Considerations

The body is text the worker wrote, so the parser treats every cell as data: it
reads with jq, never evaluates a cell, and refuses a row with control
characters. The worst a forged table can do is claim seats that never ran;
the Run column exists so an auditor can check each one, and that check is a
person's, as it is today. The message goes to GitHub as a file argument, never
on a command line the shell expands. The message builder refuses attribution
and session links, matching the repository's own rule. Nothing here widens
what the coordinator may do: every new verdict narrows the path to a merge.

## Consequences

### Positive

- One panel per head. The merger's three seats go, and with them the larger
  part of the loop's spend.
- A panel claim the land step accepts names its seats.
- The commit message on the default branch is Part 1, every time.
- A reserved merge reaches the person already checked and judged, with its
  message.
- A hold is read, not remembered.

### Negative

- Workers must write the table exactly; a typo is a rebrief.
- The run ids are claims, and nothing on GitHub proves a seat ran.
- A permitted merge depends on a change to the execute skill's merge script,
  the one change outside `skills/coordinate/`.
- An edit inside a file the base branch also changed can ride in with a
  merge-in after the round.

### Mitigations

- The brief template carries the table's exact form, and `unready` says which
  rule broke.
- The ids are there to be audited, and the strategy's sender-identity decision
  already accepts that the harness can't vouch for a session.
- The merge script takes the message in the same pull request as the land
  check, so no permitted merge lands the whole body.
- The merge-in residue is what the hand rule already accepted, and the goal-fit
  read happens on the head being merged.
