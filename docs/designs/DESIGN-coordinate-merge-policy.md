---
schema: design/v1
status: Accepted
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
  a table whose seats can't be told apart, so no verified head is recorded on
  a panel claim without seat identities. `land` re-reads the body live and
  refuses, with a reason, a head that has no table, fewer than three distinct
  seats, any verdict but pass, or a reviewed head that differs from the head
  by more than merge-ins of the base branch. It never runs a panel. The same
  check builds the squash message from the title and Part 1, runs the
  repository's mechanical body checks over it, and stores it; a merge the
  workspace permits carries exactly that message, and a merge it reserves
  goes to the person with it. The posture stays what `posture-read.sh` reads
  from the workspace's permission rules and hooks. A hold becomes a Holds row
  in the record with a condition `land-check.sh` evaluates live, and a merge
  that happens while a hold is unmet is written to the record with who made
  it.
rationale: |
  Reading evidence that already exists is the cheapest way to stop paying
  for a second panel, and a table is the one form both a reviewer and a
  bash 3.2 parser read without help. Seat verdicts are closed (pass or
  fail), so aggregating them moves into the script; the seats' judgment of
  the code and of Part 1 against the diff stays open and stays with sonnet
  seats, because the decider that would replace them hasn't earned trust in
  its shadow trial. Allowing base-branch merge-ins between the reviewed head
  and the head keeps the commonest move after a round (merging main in) from
  costing a new round, while a check on the files each merge-in changed
  stops an edit from hiding inside one. The posture is already read from the
  hooks that enforce it, so a second setting could only disagree with them.
---

# DESIGN: coordinate-merge-policy

## Status

Accepted

## Context and Problem Statement

The `coordinate` skill drives a roadmap or a discipline rotation by handing
units of work to worker sessions and landing what they push. Its land step is
three states in `skills/coordinate/koto-templates/coordinate.md`: `land`, whose
check `land-check.sh` re-reads the head against the one `verify_board`
verified, reads the merge state and reads the merge posture; `land_merge`,
where the coordinator runs `land-merge.sh`, which calls the execute skill's
`merge-exec.sh` with `--match-head-commit`; and `merge_confirm`, which reads
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
output: an agent or session id, or the id of a review comment the seat's
verdict was posted as; `Verdict` is `pass` or `fail`; `Reviewed head` the full
sha the seat read. Only the first such table in Part 2 is read. Part 1 is never
searched, since it becomes the commit message.

`panel-evidence.sh` parses a body into JSON: `absent` (no heading),
`malformed` (a heading with a table that breaks a rule below), or `ok` with the
seats. The rules: every row has five non-empty cells; a Run matches
`^[A-Za-z0-9][A-Za-z0-9._:/#-]{3,}$`; no two rows share a Run; Verdict is
`pass` or `fail`; every Reviewed head is a full lowercase sha and all rows name
the same one. A table with a repeated or missing Run is a panel claim without
seat identities, the tsukumogami/niwa#346 case, and it is `malformed`.

Two steps read it. `verify_board` (`board-record.sh`) reads the body once the
board is green and prints a new verdict, `unevidenced`, for a `malformed`
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

With reviewed head R and live head H: if R equals H the evidence is fresh.
Otherwise `land-check.sh` reads the comparison of R with H and passes only when
R is an ancestor of H and every commit after R is a merge whose second parent
is already on the base branch, and the files each merge changed against its
first parent are among the files the base branch changed since the merge base.
Anything else is `stale`.

Alternatives considered:

- **Refuse any difference.** Forces a new three-seat round after every
  merge-in of main, the commonest move after a round and the one the
  2026-10-01 rule let through as is. Rejected.
- **Accept any merge commit.** A conflict resolution can carry an edit of its
  own, and an edit to a file main never touched can hide in one. The file-set
  check catches the second case for one API read per merge. Rejected.
- **Review the delta with one seat, as the hand rule does.** The land step
  never runs a panel. It refuses with the reason, and the worker's next round
  covers the delta.

### Decision 3: Which checks are closed and which stay with a seat

Closed checks, each a script, run in `land-check.sh` before the posture:

| Check | Source |
|---|---|
| Every job at the head concluded green, read job by job | `verify_board`, unchanged |
| The evidence is present, its seats distinct, at least three, all `pass` | `panel-evidence.sh` |
| The reviewed head is fresh | Decision 2 |
| Conventional Commits title, one separator, non-empty Part 1, no attribution, no heading in Part 1 | `shirabe validate --pr-body`, the repository's rule (`references/pr-body-conformance.md`) |
| The built message is non-empty and carries no attribution or session link | the message builder (Decision 4) |

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
this feature. A decider is a model too, and the strategy says a decider pass
approves nothing until the trial is ruled on.

### Decision 4: The squash message

`land-check.sh` builds the message from the pull request at the head it
checks: the subject is the title; the body is Part 1, everything above the
first top-level `---` outside a code fence, with markdown removed (headings,
emphasis, code ticks, list markers, table pipes, links rewritten as `text
(url)`). These are the rules of the merger's own message script, ported to
bash and jq. The message is stored as data in the check's detail key,
`coord/land.json`, and its sha256 is part of the sealed token, so the merge
carries exactly the message the check built.

Under a permitting posture `land-merge.sh` hands the message to
`merge-exec.sh`, which passes it as `--subject` and `--body-file`. That needs
`merge-exec.sh` to take an optional message file; it is the execute skill's
script, so the change is a small one outside this feature's directory and the
implementation asks for it explicitly. Until it lands, `land-merge.sh` refuses
a permitted merge rather than let the repository's default land the whole body.
Under a reserving posture the message goes to the person with the merge-order
table.

"Graded against the diff" splits along Decision 3: the mechanical checks are
the land step's, and whether the text describes the diff is a seat's.

Alternatives considered:

- **Bind the evidence to a digest of Part 1.** It would make a body edit after
  the round visible to the land step. But fixing a stale Part 1 is expected to
  happen by editing the body, not by pushing a commit, and the merger reads Part
  1 at merge time. Declined for now; it is the obvious next step if a Part 1
  edited after its round ever lands wrong.
- **Let the repository default carry it.** The org's repositories use the
  body as the squash message, so the default lands Part 2 with it. Rejected.

### Decision 5: Where "the human merges" lives

It lives where `posture-read.sh` already reads it: the permission rules
(`deny`, `ask`, `allow`, `defaultMode`) and the PreToolUse hooks in
`.claude/settings.json` and `.claude/settings.local.json` at the instance root
and the workspace root, which the workspace manager writes from the workspace's
own configuration. No new setting is added. The land step reads it twice, at
the start and again at `land`, narrowed to the stricter of the two, and
`land-merge.sh` reads it a third time before it calls anything.

| Merge posture | What the land step does |
|---|---|
| `permit` | `land_merge`: the coordinator runs `land-merge.sh`, which merges at the verified head with the built message |
| `deny` | ready and held: `surface` with the merge-order table, the message and where the evidence is; the holding parks |
| `confirm` | the same as `deny`: a step behind a person's confirmation is a person's |
| `unread` | at the start, `posture_ask`; every step stays reserved until the human's answer is on the record |

The workspace's gate hook denies `gh pr merge` and the API merge endpoints in
every applied instance unless the instance is the one named as exempt (the
record, 2026-09-28, the gate-online hook; the exemption is
tsukumogami/dot-niwa#22). The reader can't evaluate an exemption held in the
environment, and a hook that names the merge command is read as `confirm`, so
every coordinator in this workspace reports a ready pull request as held and
never merges. The evidence and message checks run before the posture read, so a
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

`land-check.sh` reads the holds on the pull request it checks, after the
evidence and before the posture, and evaluates each condition live:
`merged` reads the named pull request's state, `tag` reads the tag, and
`lifted` is met only when the row's Lifted cell names who and when. An unmet
hold gives `held <pr> <sha>`, which routes to `surface`; the coordinator reports
the hold as held because the check just read it, not because it remembers it.

It's a verdict of `land`'s own check, so it is a gate in the template's sense:
the same sealed capture and the same non-overridable gate every check state
uses. A separate gate on `land` would be a second reader of the same facts.
`land_merge`'s `merge: held` goes; a hold the human directs becomes a Holds row
with `lifted`, written through the record's scripts like any other row.

When `merge_confirm` or `merged_facts` confirms a merge, it reads who merged
it, and if a hold on that pull request was unmet, the coordinator writes a
Reversals row: the hold, "merged while held", the time, and the merger as
GitHub names it. So the record says who merged what it held.

The record's container and its stored set of person-owned events are Feature 7
of the coordinator roadmap. The Holds section is defined here because the land
step's read needs a form; it moves with the rest of the record when Feature 7
settles the container.

Alternatives considered:

- **A directive line telling the coordinator to check holds.** Prose is what
  let the hold on the merged pull request fail. Rejected.
- **Holds in a context key.** A check would be reading what the coordinator
  wrote, which the template's rule forbids. Rejected.

## Decision Outcome

The land step reads the worker's round from the body and never runs one;
`verify_board` refuses an unidentified panel claim so no holding records it; the
squash message is built and graded mechanically by the check and carried by the
merge; the posture stays the workspace's permission rules and hooks; and a hold
is a record row the check evaluates live.

What the roadmap's Feature 8 asks for that this declines:

- **A seat's id must be an agent or session id.** Broadened to any run
  identifier an auditor can match, a review comment's id included, since a
  worker can't always publish an agent's internal id, and a comment's id is
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
the merge state) and adds four before the posture:

1. Read the body and title at the head (`gh pr view --json body,title,headRefOid,baseRefName`).
2. `panel-evidence.sh` over the body. Not `ok`, fewer than three seats, or a
   `fail` verdict: `unready <pr> <sha>` with the reason in `coord/land.json`.
3. Freshness (Decision 2): `unready` with reason `stale` when it fails.
4. The message: `shirabe validate --pr-body` with the title, then the builder.
   A failure is `unready` with reason `message`.
5. Holds (Decision 6, second implementation pull request): `held <pr> <sha>`.
6. The posture: `permit <pr> <sha> <message-sha256>`, `deny <pr> <sha>` or
   `confirm <pr> <sha>`.

`unready` routes to `rebrief`: what's missing is the worker's to fix (run the
round, fill the table, fix Part 1), and the coordinator tells it so.
`coord/land.json` carries the reason, the evidence as parsed, the message and
its sha256.

### The merge

`land-merge.sh` reads the sealed `permit` token, re-reads the posture, takes the
message from `coord/land.json` only if its sha256 matches the token, writes it
to a file, and calls `merge-exec.sh <repo> <pr> <sha> <message-file>`.

### New verdict words

| Word | State | Code | Route |
|---|---|---|---|
| `unevidenced` | `verify_board` | 79 | `rebrief` |
| `unready` | `land` | 83 | `rebrief` |
| `held` | `land` | 85 | `surface` |

### Files

| File | Change |
|---|---|
| `skills/coordinate/scripts/panel-evidence.sh` | new: parse the Review panel table |
| `skills/coordinate/scripts/squash-message.sh` | new: build the message from title and body |
| `skills/coordinate/scripts/land-check.sh` | evidence, freshness, message, holds before the posture |
| `skills/coordinate/scripts/board-record.sh` | `unevidenced` for a malformed table |
| `skills/coordinate/scripts/land-merge.sh` | carry the message |
| `skills/coordinate/scripts/coord-verdict.sh` | the new words |
| `skills/coordinate/koto-templates/coordinate.md` | the new arms and the land directives |
| `skills/coordinate/references/verification-checklist.md` | the merge-order table names the evidence and the message |
| `skills/coordinate/references/brief-template.md` | the worker's body carries the table |
| `skills/execute/scripts/merge-exec.sh` | an optional message file (asked for separately) |

## Implementation Approach

Two pull requests after this one.

1. **Evidence, freshness, message, posture.** Decisions 1 to 5, with unit
   tests for the parser, the builder and the freshness rule, and engine cases
   in `board-land_engine_test.sh`: evidence at the head merges; no evidence,
   an unidentified seat, a `fail` verdict and a stale reviewed head each
   refuse with their reason; a reviewed head one main merge-in behind passes;
   the message equals the fixture's Part 1; a denied or confirm-only posture
   reports ready and held.
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
- A reserved merge reaches the person already checked, with its message.
- A hold is read, not remembered.

### Negative

- Workers must write the table exactly; a typo is a rebrief.
- The run ids are claims, and nothing on GitHub proves a seat ran.
- A permitted merge depends on a change to the execute skill's merge script.

### Mitigations

- The brief template carries the table's exact form, and `unready` says which
  rule broke.
- The ids are there to be audited, and the strategy's sender-identity decision
  already accepts that the harness can't vouch for a session.
- Until the merge script takes a message, a permitted merge refuses rather than
  land the whole body; no workspace loses a correct merge, it gets a hand-over.
