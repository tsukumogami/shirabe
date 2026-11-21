---
schema: design/v1
status: Planned
problem: |
  shirabe treats a plan as a working document: the completion cascade flips it
  to Done and removes it with git rm, a single-PR plan is added and removed on
  its own branch so the default branch never sees it, the validator requires
  it gone at merge and bars durable documents from naming it, and no PR or plan
  links the two. A run's step proof and recorded decisions live only in local
  koto sessions. Keeping the plan needs a write-back path, a handful of rule
  changes and one lifecycle stated everywhere.
decision: |
  The plan stays at docs/plans/PLAN-<topic>.md and is marked Done, not moved
  or deleted, in the PR that lands its last work. Each delivery run writes a
  Run Record entry per step or issue (PRs, proof, decisions cited as
  <session>#<seq>) into the plan and the same decisions into its PR body,
  rendered by one new script from the session logs; a second script checks
  plan, PR and session against each other. The plan becomes a durable format,
  a Done plan's roadmap upstream is rewritten to the roadmap's parent, a
  design gains a checked plan: field, and the lifecycle, finalize and resume
  logic expect a Done plan where they expected none.
rationale: |
  Keeping the file in place means every link written while the work ran stays
  valid, and landing Done inside the last reviewed PR is the only route that
  puts a single-PR plan on the default branch without an unreviewed write. Two
  copies of each decision written from one source catch an edited plan, and
  the citation uses what koto already records, so neither koto nor niwa
  changes. The rule changes are the smallest set that makes a kept plan valid
  while keeping the roadmap lifetime guarantee for every other document.
upstream: docs/prds/PRD-kept-plan.md
decision_provenance: inline-resolved
---

# DESIGN: Kept plan

## Status

Planned

Accepted under `/scope`'s non-interactive mode. The security researcher's
findings were folded into Security Considerations, and the architecture,
security and structural-format reviewers then passed it with non-blocking
findings, which are applied.

## Context and Problem Statement

A plan is the document `/plan` writes and `/execute` and `/work-on` carry out:
steps in a plan/v2 step plan, issues or issue outlines in a plan/v1 plan. Five
parts of shirabe assume it disappears once its work is done.

The completion cascade, `skills/work-on/scripts/run-cascade.sh`, runs from
`/execute`'s `plan_completion` state and `/work-on`'s `cascade_run` state. It
calls `shirabe finalize-chain` to transition the design, PRD and brief, then
sets the plan to Done and runs `git rm -f` on it in the same commit.
`verify-cascade-commit.sh` fails a cascade commit that leaves the plan on disk.
On a `single-pr` plan this all happens on the plan's own branch before
`gh pr ready`, so the squash merge carries no plan at all.

The validator agrees. `crates/shirabe-validate/src/formats.rs` gives the Plan
format `Lifetime::Working`; `checks.rs`'s `check_upstream_legality` reports
`R11` when a durable document names a working one in `upstream:`;
`lifecycle.rs` sets the passing state of a plan in every at-merge and
work-completing posture to `Deleted`, so a present Done plan fails `L01`; and
`finalize.rs` reports the plan as a `delete_plan` node. The pipeline
reference states the rule behind all of it: a durable document never names a
working one, because the link would dangle once the cascade ran.

Nothing links a PR to its plan or back. `/execute`'s PR body carries a
per-child outcome table and no plan path; `/work-on`'s carries none either;
only a coordination PR's index names plan paths, and only in a PR body. A
step's proof is the quoted check result in the step's `summary.md` session
key, and each decision a run records is a `decision_recorded` event in the
piece session's log under `koto session dir <name>`. Both are local to the
machine that ran the work.

The PRD (`docs/prds/PRD-kept-plan.md`) asks for the plan to stay at
`docs/plans/PLAN-<topic>.md` at Done (R1, R3), to reach the default branch for
`single-pr` too by becoming Done in the PR that lands its last work (R2), to
carry a `## Run Record` with each step or issue's PRs, proof and decisions in a
fixed line format (R7, R8), written by the delivery run before the PR is
marked ready and repeated in the PR body (R9 to R11), with a check command
that compares the copies (R12) and a rule for private content in public
repositories (R13). It asks the validator to treat a plan as durable (R14),
check a design's `plan:` field (R15), expect a Done plan in each posture
(R16), stop a kept plan from dangling when its roadmap goes (R17), and report
a transition instead of a deletion (R18). It names the references that must
state one lifecycle (R19) and the lookups that must skip a Done plan (R20),
and rules out changes to koto or niwa (R21).

## Decision Drivers

- **No unreviewed write to the default branch.** Anything that keeps or
  records the plan lands inside a PR a person or a review seat reads.
- **Links written while the work runs must stay valid.** A squash commit's
  `Plan:` line can't be edited after merge, so the plan's path can't change.
- **No koto or niwa change** (PRD R21). Citations and copies use what a koto
  session already records: the session name, its log and each event's `seq`.
- **One source for both copies of a decision.** The plan entry and the PR copy
  come from one renderer reading one log, or the check compares two
  hand-written texts and proves nothing.
- **Keep the roadmap guarantee.** A roadmap stays a working document; no
  durable document may end up naming a deleted one.
- **Bash 3.2 and the existing test layout.** Scripts follow the repository's
  bash floor; each script keeps its `_test.sh` beside it.
- **Public repository.** Nothing written into a plan or PR here may name
  private content (PRD R13).
- **Leave room for another record home.** Where a kept plan lives is computed
  in one place, so a later feature can move it without touching every skill.

## Considered Options

### Decision 1: Where a kept plan sits, and whether completion moves, marks or keeps it

The plan must be findable from its topic alone, and every link the run wrote
while the plan was Active must still resolve.

#### Chosen: keep the file where it is and mark it Done

*Provenance: resolved inline under `/scope`, standard tier.*

The plan stays at `docs/plans/PLAN-<topic>.md`. Completion sets its status to
Done in both frontmatter and body and changes nothing else about where it
lives. Status is the only marker. The path is computed in one shell function,
`plan_record_path <topic>` in the new `skills/plan/scripts/plan-record.sh`,
which every writer and reader in this design calls; that function is where a
later feature points a plan at another record home.

#### Alternatives considered

**Move to `docs/plans/done/`.** Rejected: every `Plan:` line already in a
squash commit, and every design's `plan:` field, would point at the old path.
A move would need a repoint pass across the tree and can never repoint a
commit message.

**Delete, and rely on git history.** Rejected: a `single-pr` plan is never in
the default branch's history, so there is nothing to recover, and a reader
would have to know the plan existed to look for it.

**Add an `archived: true` field beside the status.** Rejected: it says what
`status: Done` already says, and two fields that must agree are one more thing
to drift.

### Decision 2: How the way between plan and PR is carried both ways

PRD R7 and R10 fix the observable shapes. The choice here is where each side
lives in the documents and which code writes it when.

#### Chosen: a Run Record section in the plan, a Plan line and a Run record part in the PR

*Provenance: resolved inline under `/scope`, standard tier.*

**Plan to PR.** A `## Run Record` section, appended after the plan's last
required section, holds one `### <entry key>` entry per step or issue in plan
order, then a `### Plan` entry for the owning session. An entry looks like:

```markdown
### Step 2
PRs: tsukumogami/shirabe#1101
Proof: `koto next demo --no-cleanup` prints `"state":"done"` -> {"action":"done","state":"done"}
Decisions:
- execute-kept-plan.o-step-2#41: Read the log path the gate passes -- koto decisions list sees only the current state
```

**PR to plan.** Part 1 of the PR body carries
`Plan: docs/plans/PLAN-<topic>.md (Step 2)`, which `scripts/lib/squash-message.sh`
already copies into the squash commit because it keeps Part 1. Part 2 carries a
`Run record` part with the same `Decisions:` lines, byte for byte.

**Who writes it, and when.** The delivery run writes an entry in the PR whose
diff carried the entry's work, before that PR is marked ready, and rewrites it
in the same commit on every later push:

- `/execute` single-pr: in `plan_completion`, before the cascade, for every
  step, in the one PR.
- `/work-on` multi-pr: in `pr_creation`'s finalization, for the issue that
  run carried, in that issue's PR.
- `/execute` coordinated: in `plan_completion` of the coordination PR, for
  every node, reading the sealed node record for each node PR.

Node PRs in another repository get only the `Plan:` line, in the
`owner/repo:docs/plans/PLAN-<topic>.md` form; their plan entries are written
in the coordination PR, which is in the plan's repository.

#### Alternatives considered

**Lines inside each step block.** Rejected: a plan/v2 outline step is exactly
one line by FC22, a dropped step may still be an outline, and the owner rule
says no worker edits a step's text. A separate section leaves the agreed text
untouched.

**A PR column in the Implementation Issues table.** Rejected: the table's
columns are fixed per profile (`FC05`), single-pr and plan/v2 plans have no
table, and a table cell can't hold a list of decisions.

**Back-fill after merge by searching PRs for the topic.** Rejected: it writes
to the default branch outside any PR, and a search can miss or over-match.

### Decision 3: How proof and recorded decisions reach the plan, checkably

#### Chosen: one renderer reads the session logs, a checker compares the copies

*Provenance: resolved inline under `/scope`, standard tier.*

A new script, `skills/plan/scripts/plan-record.sh`, has four subcommands
(the fourth, `landing`, is Decision 4's gate):

- `path <topic>` prints the plan path (Decision 1's one place).
- `entry --plan <path> --key <entry key> --pr <owner/repo#N>... --session
  <name>... [--none <reason>]` prints one Run Record entry. For each
  `--session` it reads `<koto session dir>/koto-<name>.state.jsonl`, takes
  every `decision_recorded` event in log order, and prints
  `- <name>#<seq>: <choice> -- <reason>` with whitespace collapsed, the same
  extraction `skills/work-on/scripts/decision-reasons.sh` already does. For a
  completed plan/v2 step it reads the step's `**Check**:` line from the plan
  and the first quoted result line from `koto context get <name> summary.md`
  under `## What Was Implemented`, or prints `Proof: not reported.`.
- `pr-part --plan <path> --key <entry key>...` prints the PR's `Run record`
  part from the entries already in the plan, so the PR copy is the plan's
  bytes, not a second rendering.
- `landing --plan <path> --key <entry key>` decides whether this run's PR is
  the landing PR (Decision 4).

A piece session is the `/execute` child session for a step (its name ends
`.o-<step>`) or the `/work-on` session for an issue; a piece retried in a
second session passes both `--session` values in run order (PRD R8). The
owning session's decisions go into `### Plan`.

A second script, `skills/plan/scripts/check-plan-record.sh <plan-path>`,
implements PRD R12: it parses the Run Record, fails a bare `#N`, reads each
named PR body with `gh pr view --json body`, compares the `Run record` part
byte for byte, and for each citation whose session directory exists compares
the event at that `seq`, reporting without failing any decision in that
session the plan doesn't carry (recorded after the last push). A withheld
line is compared by citation only. It also re-runs the visibility and secret
filters over every line, so a hand-edited line present in both copies still
fails. Exit 0 clean, 1 on any mismatch, 2 when `gh` can't read a PR;
`session not retained: <name>` is printed and not counted.

No skill edits a Done plan after its landing PR merges (PRD R4):
`plan-record.sh` refuses to write an entry into a plan whose default-branch
copy is already Done, and the lookups in PRD R20's list never route work
to one.

#### Alternatives considered

**Cite the session only.** Rejected: the session lives in one machine's local
store, so most readers can't check anything.

**Add a decisions export to koto.** Rejected: koto changes are out of scope,
and the log already holds what the copy needs.

**Copy decisions into a PR comment.** Rejected: comments are edited and
deleted freely and aren't part of the squash commit or the plan's history.

### Decision 4: How a single-PR plan reaches the default branch, and where Done lands

#### Chosen: the cascade marks Done and keeps the file, inside the landing PR

*Provenance: resolved inline under `/scope`, standard tier.*

`run-cascade.sh` keeps calling `shirabe transition <plan> Done`, then stages
the plan instead of running `git rm -f`, in the same finalization commit as
the design, PRD and brief transitions. Because `/execute`'s `plan_completion`
runs it before `gh pr ready`, a `single-pr` plan lands at Done with the squash
merge. A Done plan is a no-op for the transition, so a second cascade run
stages nothing and commits nothing.

The landing PR is the one PR (`single-pr`), the coordination PR
(`coordinated`), or for `multi-pr` the PR whose run finds, after merging the
default branch in, that no other piece of work is still open. Today a
`multi-pr` run's `cascade_run` reaches the cascade on every issue and the
cascade's pre-probe skips it while the plan is Active, so nothing ever marks
such a plan Done. `/work-on`'s `cascade_entry` gains one gate,
`plan-record.sh landing --plan <path> --key <key>`, which reads the default
branch's copy of the plan (`git show origin/<default>:<path>`, after the
run's existing catch-up merge) and exits 0 when every entry key other than
this run's own is settled, and only then does `cascade_run` run the cascade.
`### Plan` is never an entry key for this test. A key is settled when the
default branch's copy already has its entry, or when its work is closed
without one: its GitHub issue is closed, or the plan marks the step dropped.
The landing run writes the entries for every key settled the second way:
`PRs: none (dropped)` for a dropped step, `PRs: none (skipped)` or
`PRs: none (no-change)` for an issue closed with that outcome recorded on it,
and, for an issue closed by a PR before this shipped, the in-flight entry
below. A `multi-pr` plan has no owning session, so its landing run writes
`### Plan` with `Decisions: none recorded.`. `landing`
exits 2 when it can't parse the plan or read the default branch's copy, and
`cascade_entry` routes exit 2 to `done_blocked`, never to the cascade.

**A plan already in flight when this ships** (PRD R24). A `multi-pr` plan
Active on the default branch, some of whose issues merged before this
release, has no entries for those issues. `landing` counts a closed issue with
no entry as recorded, and the landing run writes its entry from the issue's
own closing reference (`closedByPullRequestsReferences` from `gh issue view`),
with `Decisions: none recorded.`, since those runs predate the record. This is
the only entry not written by the run that did the work, and its absent
decisions say so.

**What the cascade does, in order.** In `run-cascade.sh`, for a plan whose
Run Record is complete:

1. Read the plan's `upstream:` as it stands, and the roadmap's own
   `upstream:` when one is named.
2. Run `shirabe finalize-chain`. Its `transition_design` node moves the design
   to Current and, in the same Rust code path, writes the design's `plan:`
   field and repoints the plan's `upstream:` design entry to the moved path
   (`transition.rs` already owns repointing references to a moved document).
3. Run `handle_roadmap`, which updates the roadmap's feature entry from the
   original upstream read in step 1, and `handle_roadmap_deletion` as today.
4. Replace the plan's roadmap entry with the parent read in step 1, add the
   `Sequenced in` line, and set the plan to Done.
5. Stage the plan with the other transitioned paths, commit, push, and run
   the post-verify probe, which now expects a Done plan.

A coordinated run reads whether its cascade ran from the plan file today:
`skills/execute/scripts/coord-common.sh` treats a present plan as "the
cascade hasn't run" and re-runs it. That test becomes the run record alone
(`run/cascade` pushed, with a head), and while the plan is present the node
list is still read from it, so a kept Done plan neither re-runs the cascade
nor loses the nodes.

`resolve_anchor` gains a rung that resolves to the kept plan itself, ahead of
its existing rungs for a deleted plan, and the cascade's
`delete_plan` step becomes `keep_plan` in its JSON output.

#### Alternatives considered

**A post-merge commit to the default branch.** Rejected: an unreviewed write
to the default branch, and it needs a trigger shirabe doesn't have (the
cascade has no post-merge hook by design).

**A housekeeping PR per finished plan.** Rejected: one extra PR per feature,
and the plan sits deleted or Active on the default branch until it merges.

### Decision 5: Which pipeline and validator rules change

#### Chosen: plans are durable, with four targeted rule changes

*Provenance: resolved inline under `/scope`, standard tier.*

1. **Lifetime.** `formats.rs` gives the Plan format `Lifetime::Durable`. `R11`
   then never fires on a plan target. The invariant test
   `no_durable_format_declares_a_working_parent` gains one exemption, Plan
   naming Roadmap, and `check_upstream_legality` skips `R11` for that pair
   only while the plan's status is not Done (PRD R14).
2. **Roadmap at Done.** When the cascade sets a plan Done, `run-cascade.sh`
   replaces a roadmap entry in the plan's `upstream:` with the roadmap's own
   `upstream:` entries (the one-hop walk `/brief` already uses) and adds
   `Sequenced in docs/roadmaps/ROADMAP-<name>.md.` to the Status prose, which
   `FC20` tolerates once the roadmap is gone (PRD R17). The roadmap's own
   feature update runs first, reading the original upstream. The parent path
   is accepted only when it is repo-relative under `docs/strategies/` or
   `docs/visions/` with no `..`, or a cross-repo value; anything else drops
   the entry rather than writing it.
3. **A design names its plan.** `design/v1` gains an optional `plan:` field.
   finalize-chain writes it when it moves the design to Current. A new check,
   `R12` (registry id `docs/plan-link`; the validator code, unrelated to the
   PRD's requirement of the same number), confirms the field is a repo-relative
   path under `docs/plans/` with no `..`, names a `PLAN-*.md` file that
   exists, and that the plan's `upstream:` names the design, and reports both
   paths when not (PRD R15).
4. **Lifecycle and finalize.** `lifecycle.rs` sets the plan's passing state to
   `Status("Done")` in the multi-pr work-completing, multi-pr at-merge and
   single-pr at-merge postures, accepts the design at Current or Superseded
   under a Done plan, and keeps today's results for an absent plan and for an
   Active plan at merge (PRD R16's table). `finalize.rs` replaces
   `NodeAction::DeletePlan` with `NodeAction::TransitionPlan` reporting
   `transition_plan` to `Done` (PRD R18); this rename lands with the cascade
   change (build step 4), because `run-cascade.sh` refuses any action it
   doesn't know. A new format check, `FC23` (registry id
   `plan/run-record-shape`), checks the Run Record against PRD R7's grammar.
   On any plan it checks the shape of every line in the section; on a Done
   plan it also checks completeness: one entry per entry key in plan order,
   then the `### Plan` entry.

#### Alternatives considered

**Keep Plan as Working and special-case `R11` for plan targets.** Rejected:
the pipeline reference would still say plans are deleted, which is the
contradiction this feature exists to remove.

**Keep roadmaps too.** Rejected as out of scope; it would also change what
the roadmap's own readers expect.

**A prose link from the design.** Rejected: prose can't be checked against
the plan's `upstream:`, so a design could name the wrong plan silently.

## Decision Outcome

A plan now ends where it was written. While its work runs it is Active, as
today. Each delivery run records what it did for its step or issue in the
plan's `## Run Record` and in its own PR, from the same session logs, before
the PR is ready. The PR that lands the last piece of work also runs the
cascade, which marks the plan Done, points its `upstream:` past a roadmap,
writes `plan:` into the design as it moves to Current, and keeps the file. A
`single-pr` plan reaches the default branch this way with no extra step.

The validator follows: a plan is durable, a Done plan is the expected state
at merge, a design's `plan:` is checked both ways, and a Done plan's Run
Record is checked for shape. `check-plan-record.sh` lets any later reader
confirm the plan's decisions against the PR and, where the session is still
retained, against the session itself.

The five decisions fit together on one point: the plan file never moves and
is only ever edited inside a reviewed PR. That is what keeps the `Plan:` lines
in squash commits valid, what makes the design's `plan:` field checkable, and
what lets the checker trust the plan's bytes as the thing to compare.

**Open question for the owner of the toolkit's planning record.** Outside this
repository, the toolkit's planning record also classes the plan as a working
document. This design changes shirabe's own classification and depends on
nothing else; whether that outside classification should change to match, or
already admits a kept plan, is its owner's call.

## Solution Architecture

### Components

| Component | Change |
|-----------|--------|
| `skills/plan/scripts/plan-record.sh` (new) | `path`, `entry`, `pr-part`, `landing` subcommands; the one place the kept-plan path and the entry grammar live |
| `skills/plan/scripts/check-plan-record.sh` (new) | Reader-side check (PRD R12) |
| `skills/work-on/scripts/run-cascade.sh` | Done and keep instead of `git rm`; roadmap upstream rewrite; design `plan:` write via finalize-chain |
| `skills/work-on/scripts/verify-cascade-commit.sh` | Passes on a kept Done plan, fails on a deleted one |
| `skills/execute/koto-templates/execute.md` | `plan_completion` writes every entry before the cascade; `pr_finalization` adds the `Plan:` line and the `Run record` part; node PR bodies get the `owner/repo:` `Plan:` line |
| `skills/work-on/koto-templates/work-on.md` | Multi-pr finalization writes its entry and PR parts; `cascade_entry` runs `plan-record.sh landing` |
| `crates/shirabe-validate` | Lifetime, `R11` exemption, `R12`, `FC23`, lifecycle passing states, `TransitionPlan` |
| Lookups (`find-anchor-plan.sh`, `drift-facts.sh`, `execute-open.sh`, `resume-probe.sh`, `deliver-probe.sh`) | Skip Done plans; Done means executed |
| References and skills prose | One lifecycle sentence everywhere (PRD R19) |

### Where the lifecycle is stated, and what each place will say

Every place below carries the sentence "A plan stays at
`docs/plans/PLAN-<topic>.md`, at Done, once its work is done; nothing deletes
it." (PRD R19), and loses what it says today.

| Place | Says today | Will say |
|-------|-----------|----------|
| `skills/plan/references/plan-format.md` (Lifecycle) | stays in `docs/plans/` through every state; cascade walks the chain | the same, plus the Run Record section, its grammar, who writes it, and that the cascade writes the design's `plan:` |
| `skills/plan/SKILL.md` | Draft, Active, Done, DELETED; "Deleted by: the work-on cascade"; the plan carries the roadmap because it is deleted first | Draft, Active, Done, kept; a Done plan names the roadmap's parent, not the roadmap |
| `skills/plan/references/quality/plan-doc-structure.md` | plans are ephemeral; Done bridges to deletion | plans are the durable record of the agreement and what happened to it |
| `skills/plan/references/phases/phase-7-creation.md` | the plan records the roadmap because the cascade deletes it first | the plan records the roadmap while Active; the cascade moves it to the roadmap's parent at Done |
| `skills/execute/SKILL.md` and `execute.md` `plan_completion` | the cascade deletes the plan in the finalization commit | the cascade marks it Done and keeps it after the run writes every Run Record entry |
| `skills/work-on/SKILL.md` and `work-on.md` | multi-pr cascade per issue | each issue run writes its entry; only the landing run cascades |
| `references/pipeline-model.md` (Lifetime, Where the chains meet, completion cascade) | Roadmaps and Plans are working artifacts; the crossing is safe because the plan goes first | Roadmaps are working, plans durable; an Active plan may name its roadmap, a Done plan names the roadmap's parent; a design may name its plan in `plan:` |
| `references/coordination-strategy.md` | the cascade deletes the plan in the coordination PR | the coordination PR writes every node's entry and marks the plan Done |
| `references/jev-criteria.md` | plans are deleted when their work lands | plans stay at Done with their Run Record |
| `skills/scope/SKILL.md`, `phase-0-setup.md`, `phase-resume.md`, `scope.md` | the implementation cascade deletes the plan later; no plan plus a current design means executed | a Done plan, or no plan plus a current design, means executed |
| `skills/roadmap/SKILL.md` | single-pr at-merge: plan deleted | single-pr at-merge: plan at Done |
| `README.md` | a plan is `git rm`'d before its work merges | a plan stays at Done on the default branch |
| `docs/guides/lifecycle-posture.md`, `docs/guides/doc-validation.md` | at-merge means the plan is absent; durable documents never name a plan | at-merge means the plan is at Done; a design names its plan in `plan:` |
| `skills/design/references/design-format.md` | a design may reference the plan's table by path | adds the `plan:` field and who writes it |
| Validator (`formats.rs`, `lifecycle.rs`, `finalize.rs`, `transition.rs`) | Plan is Working; Done is terminal and the file is deleted | Plan is Durable; Done is terminal and the file stays |

### How a later reader checks two departures

A reader opens the kept plan, picks two lines under any entry's `Decisions:`,
say `- execute-kept-plan.o-step-2#41: ...` and `- work-on-kept-plan-7#18:
...`, and does two things. First, they open the PR named on that entry's
`PRs:` line and find the same lines, byte for byte, in its `Run record` part:
the PR copy was written from the session at the push the PR merged at, so a
plan edited afterwards no longer matches. Second, where the session is still
in their koto store, or can be brought in with `koto session import`, they
read the event at that `seq` in `koto session dir <session>`'s log and find
the same choice and reason. `check-plan-record.sh <plan>` does both for every
decision at once and names any line that differs.

Each step's proof is kept the same way: the `Proof:` line holds the step's
`**Check**:` and the result line the step's report quoted, copied from the
step session's `summary.md` into the plan before the PR was ready.

### Data flow

```
piece session log --(plan-record.sh entry)--> plan ## Run Record entry
                                                   |
                                 (plan-record.sh pr-part, same bytes)
                                                   v
                                         PR Part 2 "Run record"
PR Part 1 "Plan:" line --(squash-message.sh)--> squash commit message

landing PR: run-cascade.sh -> plan Done (kept), roadmap upstream rewritten,
            design -> Current with plan: field

later reader: check-plan-record.sh plan --> gh pr view (PR copy)
                                        --> koto session dir (when retained)
```

### Interfaces

- **Entry grammar** (PRD R7): `### <entry key>`, then `PRs: owner/repo#N[,
  owner/repo#N...]` or `PRs: none (dropped|skipped|no-change)`, then for a
  completed plan/v2 step `Proof: <check> -> <result line>` or
  `Proof: not reported.`, then `Decisions:` with `- <session>#<seq>: <choice>
  -- <reason>` lines or `Decisions: none recorded.`. A line that trips the
  visibility or secret filter keeps its label and loses its text: a decision
  becomes `- <session>#<seq>: withheld (private content)`, a PR reference in
  a `PRs:` line becomes `withheld (private content)`, and a proof becomes
  `Proof: withheld (private content)` (PRD R13; the filters, input patterns
  and caps are in Security Considerations).
- **`plan-record.sh landing`** exits 0 when every entry key other than the
  named one is settled in the default branch's copy of the plan, as Decision
  4 defines it (`### Plan` never counts), 1 otherwise, 2 on a parse failure
  or an unreadable copy.
- **`check-plan-record.sh`** exits 0, 1 or 2 as Decision 3 says.
- **Design `plan:`**: one repo-relative path, scalar.
- **finalize-chain JSON**: the plan node's `action` becomes `transition_plan`
  with `to: "Done"`.

## Implementation Approach

The work is one plan, built in this order so each step leaves the tree
passing:

1. **Validator accepts a kept plan.** Lifetime, `R11` exemption, lifecycle
   passing states, `transition.rs` wording, `R12` and its listing in
   `validate.rs`'s emitted codes, rule registry, and their Rust tests.
   Nothing writes a kept plan yet, so the change is invisible, and a chain
   whose plan was deleted still passes. finalize-chain's `TransitionPlan`
   and `FC23` wait for step 4: the first because `run-cascade.sh` only knows
   `delete_plan`, the second because until then a Done plan has no Run
   Record.
2. **Lookups and resume.** The five lookups skip Done plans; `/scope` and
   `/deliver` route a Done plan to executed. Safe ahead of the cascade change,
   since no Done plan exists on any branch yet.
3. **The record is written.** `plan-record.sh`, the `/execute` and `/work-on`
   template changes, the PR body parts, and the landing gate. Entries are
   written into the plan and the PR even though the cascade still deletes the
   plan at this point, which the next step ends.
4. **The cascade keeps the plan.** `run-cascade.sh`,
   `verify-cascade-commit.sh`, finalize-chain's `TransitionPlan`, `plan:`
   write and repoint, the roadmap rewrite, `coord-common.sh`'s cascade test,
   `FC23` and its listing in `validate.rs`, and in the same change every test
   and eval that asserted deletion, so nothing on the tree expects both
   behaviours.
5. **Readers can check it.** `check-plan-record.sh` and its test.
6. **References agree.** Every document PRD R19 lists, the design format's
   `plan:` field, and a dated note on `DESIGN-completion-cascade.md`.

### Files the execution changes

Validator and binary:

- `crates/shirabe-validate/src/formats.rs`
- `crates/shirabe-validate/src/checks.rs`
- `crates/shirabe-validate/src/lifecycle.rs`
- `crates/shirabe-validate/src/finalize.rs`
- `crates/shirabe-validate/src/transition.rs`
- `crates/shirabe-validate/src/validate.rs`
- `crates/shirabe/src/main.rs`
- `crates/shirabe/tests/lifecycle_posture.rs`
- `crates/shirabe/tests/plan_v2_lifecycle.rs`
- `references/rule-registry.json`

Cascade, record and lookups:

- `skills/work-on/scripts/run-cascade.sh`
- `skills/work-on/scripts/run-cascade_test.sh`
- `skills/work-on/scripts/verify-cascade-commit.sh`
- `skills/work-on/scripts/verify-cascade-commit_test.sh`
- `skills/work-on/scripts/find-anchor-plan.sh`
- `skills/work-on/scripts/find-anchor-plan_test.sh`
- `skills/work-on/koto-templates/work-on.md`
- `skills/work-on/references/phases/phase-6-pr.md`
- `skills/plan/scripts/plan-record.sh` (new)
- `skills/plan/scripts/plan-record_test.sh` (new)
- `skills/plan/scripts/check-plan-record.sh` (new)
- `skills/plan/scripts/check-plan-record_test.sh` (new)
- `skills/execute/koto-templates/execute.md`
- `skills/execute/scripts/drift-facts.sh`
- `skills/execute/scripts/drift-facts_test.sh`
- `skills/execute/scripts/execute-open.sh`
- `skills/execute/scripts/execute-open_test.sh`
- `skills/execute/scripts/coord-common.sh`
- `skills/execute/scripts/coordinated-next_test.sh`
- `skills/execute/scripts/execute-coordinated-engine_test.sh`
- `skills/execute/scripts/coordinated-home-outside_test.sh`
- `skills/execute/scripts/node-push_test.sh`
- `skills/execute/scripts/coordination-verdict_test.sh`
- `skills/execute/scripts/execute-output-gates-routing_test.sh`
- `skills/execute/evals/evals.json`
- `skills/execute/evals/fixtures/plans/` (the `PLAN-cascade-test-*.md`
  fixtures that assert deletion)
- `skills/scope/evals/evals.json`
- `skills/scope/scripts/resume-probe.sh`
- `skills/scope/scripts/resume-probe_test.sh`
- `skills/scope/scripts/record-executed-report.sh` (an executed topic may now
  have its plan at Done)
- `skills/scope/koto-templates/scope.md`
- `skills/deliver/scripts/deliver-probe.sh`
- `skills/deliver/scripts/deliver-probe_test.sh`
- `skills/deliver/koto-templates/deliver.md`

References and skill prose:

- `README.md`
- `references/pipeline-model.md`
- `references/coordination-strategy.md`
- `references/jev-criteria.md`
- `skills/plan/SKILL.md`
- `skills/plan/references/plan-format.md`
- `skills/plan/references/quality/plan-doc-structure.md`
- `skills/plan/references/phases/phase-7-creation.md`
- `skills/execute/SKILL.md`
- `skills/work-on/SKILL.md`
- `skills/scope/SKILL.md`
- `skills/scope/references/phases/phase-0-setup.md`
- `skills/scope/references/phases/phase-resume.md`
- `skills/roadmap/SKILL.md`
- `skills/design/references/design-format.md`
- `docs/guides/lifecycle-posture.md`
- `docs/guides/doc-validation.md`
- `docs/designs/current/DESIGN-completion-cascade.md` (a dated note that the
  cascade now keeps the plan, pointing here)
- `.github/workflows/lifecycle.yml` (comment only)

Four more scope and deliver scripts test whether the plan file exists:
`skills/scope/scripts/check-hop-document.sh`, `publish-scoping-pr.sh`,
`hop-complete.sh` and `skills/deliver/scripts/deliver-execute-leg.sh`. Each
runs only after `resume-probe.sh` has routed the topic, and a Done plan
routes to the executed report before any of them is reached, so they are not
on the list; the execution confirms that against their tests and adds any
that a Done plan does reach.

Nothing under `skills/coordinate/` changes (the coordinated-run changes above
are all in `skills/execute/scripts/`). The coordinator already depends on
the plan being on the default branch after scoping, which this only makes
stronger, and none of its scripts assert that a plan is deleted.

## Security Considerations

The design adds no dependency and no new write path to the default branch:
every write happens inside the delivery run's own PR, before ready, under the
same review and CI as the work. What it does add is a path from text agents
wrote into local session logs to permanent files in a public repository, and
a reader that trusts that text. Each risk below has its mitigation in the
interfaces above.

**Agent text becoming public.** Decision choices and reasons, `Proof:` lines,
and PR references are all copied out of local state. `plan-record.sh` runs
every line it renders, not only decision lines, through two filters before
the line is written anywhere: `shirabe validate --visibility=Public` for
private repositories, paths and issues, and a fixed scan for secret-shaped
and machine-local text (token prefixes such as `ghp_`, `gho_`,
`github_pat_`, `xox`, `sk-`, `AKIA`; three-part base64url tokens shaped like
JWTs; `-----BEGIN` key blocks; `Bearer ` headers; home paths `/Users/` and
`/home/`; email addresses; IPv4 and IPv6 addresses). The filters run on the
full text before the length cap, so truncation can't cut a match in half.
A line that trips either keeps its label and loses its text, in the forms
the Interfaces list gives. The filter fails closed: when the validator is missing or errors,
or the repository's visibility can't be read, every free-text line is
withheld. It runs when the entry is first rendered, which is before the
run's first push of it, so nothing unfiltered reaches a remote branch.

**Inputs that reach paths and commands.** Session names come from koto's own
child list or the run's own session, never from document text, and must
match `^[a-z0-9][a-z0-9.-]*$` with no `..`; `seq` must match `^[1-9][0-9]*$`;
entry keys must match `^(Step [1-9][0-9]{0,2}|Issue [1-9][0-9]*|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*|Plan)$`;
PR references must match `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[1-9][0-9]*$`
and are taken from the run's own record of the PRs it opened, not from plan
text. Both scripts refuse anything else before a koto, git or gh call, pass
`--` before operands, compare with fixed strings (`grep -F`), and write PR
bodies only through `mktemp` files given to `gh pr edit --body-file`.

**Persisted text read by later sessions.** A kept plan is read by later agent
sessions, so its Run Record is a place an injected instruction could wait.
`plan-record.sh` caps each copied field at 500 characters, strips control
characters, Unicode bidirectional and zero-width characters, HTML tags,
markdown links, bare URLs, images and `@` mentions, and `FC23` rejects any
line in `## Run Record` outside the entry grammar, on an Active plan as well
as a Done one, so a `multi-pr` PR that lands one entry is checked too. The
section can only ever hold citations, references and short flattened text. The
plan format reference states that Run Record text is data: no skill reads it
as an instruction, and the lookups that scan `docs/plans/` read only
frontmatter status and entry keys.

**What the two-copy check proves.** `check-plan-record.sh` shows that the
plan's decisions match the PR copy written at the run's last push, so it
catches a plan edited after that push. It does not prove the run recorded
the truth, and its session comparison is advisory: `session not retained`
means that half was not checked, and the output says so in those words
rather than reporting a pass. The checker prints the differing line's
citation and entry key, never the PR body text around it, so a CI log of a
failed check doesn't echo PR content.

**Residual risks, accepted.** Two remain after these mitigations. A secret
the filters miss is permanent once the landing PR merges, because the default
branch's history keeps it; the response is to rotate the credential, not to
rewrite history. And plain-text instructions survive sanitising: "Run Record
text is data" is a stated rule every skill follows, not a boundary the tools
enforce. Neither is new in kind, since PR bodies and plan text already carry
agent-written prose into later sessions, but the kept plan makes that text
last longer.

## Consequences

### Positive

- A merged feature's plan, its PRs, its proof and its recorded decisions are
  on the default branch, reachable from the squash commit and back.
- `single-pr`, `multi-pr` and `coordinated` plans end the same way.
- The references and the validator stop contradicting each other about a
  plan's lifecycle.
- A design names the plan that implemented it, and the link is checked.

### Negative

- `docs/plans/` grows with every finished feature.
- A finished topic keeps its name; follow-up work needs a new topic slug.
- Two copies of each decision lengthen PR bodies.
- Two hand-worked `multi-pr` PRs open at once can conflict in `## Run Record`.

### Mitigations

- Done plans are skipped by every lookup that resolves work, so growth costs
  disk, not correctness.
- `/scope` and `/deliver` say plainly that the topic is executed and needs a
  new name, instead of failing obscurely.
- The PR copy sits in Part 2, which the squash commit drops.
- Delivery runs carry out one `multi-pr` issue at a time; the second of two
  hand-worked PRs resolves the conflict when it merges the default branch in,
  which `plan-record.sh landing` already requires.
