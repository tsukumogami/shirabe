---
schema: design/v1
status: Planned
problem: |
  A caller can't launch one session that scopes a feature and drives it to
  merged code. The PLAN's mode is chosen inside /plan from inputs the caller
  can't reach, and /plan never emits coordinated at all. /scope never pushes
  or opens the PR /execute expects to adopt. Nothing in the chain merges.
  And nothing is allowed to sequence two parent skills.
decision: |
  /plan owns --intent and the coordination flags, which /scope forwards; on a
  split it resolves coordinated or multi-pr by precedence. Coordinated works
  in one repository, with a branch and PR per PR node. /scope publishes one
  PR through gated publish states before cleanup. /execute gains an opt-in
  --merge through new koto states, a script-recorded verdict and a fixed-flag
  merge script. /deliver is a koto template that opens a koto request per
  run; /scope and /execute attach to its legs and report through declared
  terminal results, with koto extended to carry them.
rationale: |
  Each piece puts a decision where the evidence for it already lives, and
  koto enforces sequencing, resume and outcome mapping wherever a template
  can. The split reason stays in /plan, and mode follows it. Publishing sits
  between the recorded exit and cleanup. Merging is gated by a live GitHub
  read. Every forward step re-checks the PLAN and PRs. Alternatives either
  had a parent rewrite or invoke another skill, trusted agent evidence for
  irreversible steps, forked the coordinated path, or left outcomes in prose
  that no gate could check.
upstream: docs/prds/PRD-scope-then-execute.md
user_visible_surface: true
---

# DESIGN: scope-then-execute

## Status

Planned

This design was revised after its PLAN was written. The revision makes
`/deliver` a koto workflow and has `/scope` and `/execute` report their
outcomes to it through koto instead of printed lines, which takes six new
koto features (Decisions 4 and 6). The PLAN is being rebuilt as a coordinated
effort across koto and shirabe.

## Context and Problem Statement

A caller can't launch one session that scopes a feature and then drives it to
merged code, because four pieces of the chain don't line up.

First, the execution mode is decided inside `/plan`'s decomposition step
(step 3.6), from the repository's Delivery Preference and the split reasons it
records in `split_rationale`. `/scope` hands `/plan` only the DESIGN path (plus
`--upstream`), so nothing the caller says at launch can influence which
multi-PR mode a split resolves to. `coordinated` is only reachable through
`/scope`'s `--coordinated` flag or CLAUDE.md headers, which create a
coordination PR up front, before any hop runs, and assume more than one
repository.

Second, `/scope` never pushes and never opens a PR in single-repo mode.
`/execute`'s single-pr path adopts an open PR on the current branch as its
home PR; finding none, it cuts `impl/<slug>` instead. So the PLAN and the code
reach one PR only by accident of branching.

Third, nothing merges. `/execute`'s single-pr koto template ends at `done`
after `plan_completion` marks the PR ready and `ci_monitor` sees green CI.
Its coordinated loop advances only when predecessors merge, and nothing in the
loop merges them. `gh pr merge` is outside `/execute`'s declared write-target
set, and the draft/ready design records "the agent marks ready; the human
merges". Yet `/execute`'s description and `full-run` exit say "merged".

Fourth, there's no place for "scope, then execute" to live. Parent skills
today hand off by naming the next command; none invokes another. The
parent-skill pattern names a parent-of-the-parent slot but nothing fills it.

The PRD resolves the product questions. This design has to settle how each
requirement is met inside the existing skills:

- **Intent (R1-R3).** `/scope` accepts `--intent=continue|stop`, rejects bad
  or repeated values before writing state, records `intent: continue|stop|none`
  in its state file, and prints `intent=<value>` at exit. No intent means
  today's behavior (R2).
- **Split resolution (R4-R8).** `/plan` keeps its split rules and records the
  same split reason whatever the intent. When the work splits, the mode follows
  the precedence explicit `--coordinated`/`--no-coordinated` > `--intent` >
  CLAUDE.md coordination headers > default `multi-pr`; `continue` resolves to
  `coordinated`, `stop` or none to `multi-pr`. `/plan` gains its own `--intent`
  flag, which `/scope` forwards (R5). A coordinated PLAN may live in one
  repository, one PR group per split unit, each with its own branch and PR
  (R6), and a *continue* split files per-PR issues, with `/plan`'s filing
  approval resolved by its decision protocol under `--auto` (R7). Existing
  multi-repo coordination keeps working (R8).
- **`/scope` exit (R9-R13).** With `--intent`, `/scope` pushes its branch to
  `origin` and opens exactly one PR whose title contains the topic slug: a
  draft home PR for `single-pr`, a draft coordination PR for `coordinated`
  (opened at exit; intent runs never create one up front), a ready PR for
  `multi-pr`,
  and a draft on `re-evaluation` or `abandonment-forced`. Every `full-run`
  exit prints `next=` for the mode and `outcome=scoped` or
  `outcome=handed-off-multi-pr`, the latter listing the dependency-free issues.
  Push or PR failure ends `outcome=error` naming `scope:push` or
  `scope:pr-create`. `/scope` never invokes `/execute` (R13).
- **The driver (R14-R18, R29).** A new `/deliver <topic>` koto workflow runs
  `/scope --intent=continue` then `/execute --merge` (unless `--no-merge`) in
  one session, resolves interactive vs `--auto` once and passes it down, asks
  one confirmation before `/execute` when interactive, stops at
  `handed-off-multi-pr` for a `multi-pr` PLAN, resumes from the checked-out
  branch (refusing an intent mismatch), and ends in a named final state.
- **Merging (R19-R22).** `/execute --merge` merges only a ready PR at the
  commit this run pushed, whose every check (and every required one) has
  passed, whose merge state is clean, whose base branch actually requires
  checks or reviews, and which has an approving review where the rules require
  one or where it edits workflow files. It never uses an admin or bypass
  option, and picks the repository's single allowed method, else squash, else
  a merge commit.
  A failing check, a check-wait timeout, or an un-draftable PR is an `error`;
  an unclean merge state or a failed merge call ends `ready-awaiting-merge`.
  Coordinated merges follow the merge order with the coordination PR last,
  and a run blocked on merges ends `paused-awaiting-merges` with the
  coordination PR left open and resumable.
- **Truthful routing (R23-R25).** Next-step advice routes `single-pr` and
  `coordinated` to `/execute` and `multi-pr` to `/work-on`; "merged" in
  `/execute`'s and `/work-on`'s text means only the `merged` state; the state
  schema accepts `coordinated`.
- **Verification (R26-R28).** Every requirement has an eval scenario that names
  it, GitHub state comes from the `gh` shim, splits are forced by fixture
  design, and each new scenario passes 3 of 3 runs. Skills that gain writes
  declare them.

## Decision Drivers

- **D1. Parents stay peers.** No parent skill invokes another; the
  parent-of-the-parent slot is where chaining lives. `/scope` must not call
  `/execute` (R13), and a child's input surface may only grow through flags the
  child itself owns and documents for direct use, the rule the parent-skill
  pattern states for `--upstream`.
- **D2. No-intent runs are byte-for-byte today's behavior** apart from the exit
  summary (R2, R27). Existing evals only change where they assert text this
  feature deliberately changes.
- **D3. Merging must be impossible to over-claim.** A run reports `merged` only
  after GitHub says the PR merged; the merge never bypasses protection; and
  direct `/execute` without `--merge` never merges (R19, R20).
- **D4. Everything observable must be testable through the `gh` shim.** The
  mergeability signals, PR creation, pushes, and merges have to be `gh` or
  `git` calls the eval shim can serve and log (R26).
- **D5. Reuse the coordinated machinery rather than fork it.** Single-repo
  coordinated should run through the same loop, body template, validator, and
  merge-order DAG as multi-repo coordinated (R6, R21, R22).
- **D6. Resume from durable state.** Resume paths read the pushed PR or the
  coordination PR, not only local `wip/` state, wherever the requirement allows
  it (R17, R22).
- **D7. Declared write sets stay closed.** Every new push, PR, and merge is
  added to the owning skill's write-target declaration in the same change
  (R28).
- **D8. Keep the driver thin in behavior.** `/deliver` is a koto template,
  but all it does is sequence two parents and map their outcome tokens. It
  shouldn't re-implement resume ladders, state schemas, or merge logic that
  `/scope` and `/execute` already own.
- **D9. Prefer koto workflows.** Sequencing, resume, and outcome mapping that
  a template's gates and transitions can enforce live there, not in skill
  prose; where koto lacks the feature, extend koto.

## Considered Options

### Decision 1: How intent reaches `/plan` and resolves a split

`/plan` decides a PLAN's mode at step 3.6 of its decomposition phase, and today
that step has only two outcomes, `single-pr` and `multi-pr`. Tracing the code
shows `/plan` never writes `execution_mode: coordinated` at all: it doesn't
parse `--coordinated`/`--no-coordinated`, doesn't read the CLAUDE.md
coordination headers, and its creation phase has no coordinated branch, even
though `plan-to-tasks.sh`, the PLAN format, and `/scope`'s state enum all
consume the value. `/scope` hands the `/plan` hop only the DESIGN path and
`--upstream`. So neither intent nor the existing coordination flags reach the
mode today. The parent-skill rule allows a parent to pass a child only flags
the child itself documents for direct use (as `--upstream` already is), or the
uniform `parent_orchestration:` sentinel.

Key assumptions:

- The header values that mean "coordinated by default" can be pinned once, in
  `references/coordination-strategy.md`, and read by both `/scope` and `/plan`.
- Multi-pr issue filing under `--auto` already proceeds without a blocking
  prompt; only the new coordinated filing path needs an explicit approval step.

#### Chosen: `/plan` owns `--intent` and the coordination flags; `/scope` forwards them

`/plan` gains `--intent=continue|stop`, `--coordinated`, and `--no-coordinated`
as flags it documents for direct use, and reads the coordination headers
itself. Step 3.6 becomes two questions in order. The first is unchanged: does
the work split, and on which branch (recorded in `split_branch` and
`split_rationale` exactly as today). Only when it splits does a new step 5a
pick the mode by precedence: explicit coordination flag, then intent, then a
coordinated-by-default header, then `multi-pr`, recording
`split_mode_source: flag|intent|header|default`. Because the split question is
answered before intent is consulted, the split reason can't vary with intent
(R4). `/scope` forwards its own `--intent`, the coordination flags exactly as
the caller passed them (never a header-derived `--coordinated`, which would
outrank `--intent`), and `--auto` when intent is set. A no-intent hop sends
the same argument string as today (D2). A new coordinated branch in `/plan`'s
creation phase reuses `create-issues-batch.sh`, with an explicit filing
approval that asks interactively and resolves by the decision protocol under
`--auto` (R7).

This also makes `/scope --coordinated` produce a coordinated PLAN for the first
time.

#### Alternatives Considered

**`/scope` rewrites `execution_mode` after `/plan` returns.** `/plan` would
stay untouched and `/scope` would edit the PLAN to `coordinated` and add group
rows. Rejected: the parent may read only a child artifact's status and hash,
not rewrite it (D1); it comes too late, because `/plan` has already filed
multi-pr issues without group rows; and direct `/plan --intent` couldn't
exist, which the PRD requires.

**Carry intent in the `parent_orchestration:` sentinel.** No new flag, and it
follows the precedent for suppressing status prompts. Rejected: the sentinel
is defined as one uniform signal every child reads the same way, so a field
only `/plan` consumes is the per-parent API the rule forbids, and it doesn't
exist on a direct `/plan` run.

**`/plan` gets only the coordination flags; `/scope` translates intent into
them.** Smaller surface on `/plan`. Rejected: it merges two precedence levels,
so `/scope` would have to resolve flag-versus-intent conflicts and read the
headers itself, and an intent-derived `--coordinated` becomes
indistinguishable from an explicit one in the PLAN's record.

**Ambient intent (a CLAUDE.md header, or `/plan` reading `/scope`'s state).**
Rejected: intent is a per-run choice, and a child reading a parent's state
couples it to one parent's schema.

### Decision 2: How a coordinated PLAN runs in one repository

Most of the coordinated machinery is already indifferent to repository count.
`plan-to-tasks.sh` keys PR nodes on `(repo, pr_group)`, so two groups in one
repo are two nodes, and contraction, ordering, and split-at-seam work
unchanged. The Rust validator (`crates/shirabe-validate/src/coordination.rs`
and `merge_gate.rs`) never counts repositories, and its declaration check
matches only the fixed prefix "This is a **coordination PR**", so a
single-repo body already validates. The gaps are prose that says
"multi-repo", `/plan` never emitting group rows, and `/execute`'s coordinated
loop cutting one branch per repository, which would make two groups in one
repo share a branch.

Key assumptions:

- `/work-on`'s `SHARED_BRANCH` contract (commit to the given branch; the
  orchestrator owns the PR) is stable enough to reuse per group.
- The eval `gh` shim can serve several PRs in one repo, keyed by branch.

#### Chosen: a branch per PR node on the existing coordinated path

The unit of branching becomes the PR node, not the repository. `/plan` tags
every issue of a coordinated split with the current repository and a per-unit
group slug. `plan-to-tasks.sh` adds `REPO`, `PR_GROUP`, and `ISSUES` to each
node entry so `/execute` doesn't re-parse the PLAN. `/execute` cuts
`impl/<slug>-<node-id>` from the default branch in its own worktree for each
unblocked node, dispatches the node's issues to `work-on.md` with that branch
as `SHARED_BRANCH`, then pushes and opens one draft PR per node and marks it
ready once its CI is green. Nodes are never cut from the coordination branch,
so no group PR carries the PLAN to main ahead of the coordination PR. On
resume, each node without an indexed PR is adopted through
`gh pr list --head impl/<slug>-<node-id>`. The strategy reference says "one or
more repositories", the body template drops "multi-repo" after the unchanged
prefix, and the validator gains single-repo tests. `lifecycle.yml` drops any
PR-index entry pointing at the coordination PR's own number, which would
otherwise make the merge gate wait on itself. Multi-repo PLANs with
`Group: default` keep one node per repo, so they behave as today.

#### Alternatives Considered

**A single-pr koto session per group, wrapped by a coordination PR.** Reuses
the most code on paper. Rejected: single-repo would run on N koto sessions
while multi-repo runs the durable-state loop, which D5 rules out; the
single-pr path would adopt the coordination PR as its home PR, session names
would collide across groups, and its completion step deletes the PLAN before
the coordination PR merges last.

**Every issue is its own PR node.** Drops groups for single-repo. Rejected:
R6 defines one PR per split unit, so a unit with several issues would become
several PRs, contradicting the recorded split reason and adding merge nodes
for nothing. With one issue per unit, the chosen option already produces this
shape.

**Stacked branches.** Each group branches from its predecessor. Rejected:
squash-merging the base orphans the stack and forces rebase steps the shim
would have to simulate, and R21 only opens a PR after its predecessors merge,
so stacking buys nothing.

### Decision 3: Where `/execute`'s opt-in merge lives

The single-pr koto template ends `plan_completion -> ci_monitor -> done`, the
coordinated loop waits for merges it never performs, and `gh pr merge` is
outside `/execute`'s write set. No CI wait limit exists anywhere, and koto's
polling timeout can't supply one because it fires no transition. shirabe's
default-action policy bars irreversible external calls like `gh pr merge`
from running as an automatic action. An existing eval pins the route
`ci_monitor -> escalate_dirty_merge_state -> done_blocked`, and `ci_monitor`'s
`failing_fixed` edge currently reaches `done` with no gate at all.

Key assumptions:

- `gh pr merge --match-head-commit` refuses when the head moved; a merge queue
  that accepts without merging is caught by the confirm read.
- A 30-minute CI wait per head commit is an acceptable default.
- A merge state of `HAS_HOOKS` is treated as not clean.

#### Chosen: new koto states after `ci_monitor`, backed by a read-only verdict script and a fixed-flag merge script

The verdict also requires the PR head to equal the commit the run pushed, a
protected base branch, at least one reported check, and no outstanding review;
merge intent is checked per invocation; and every PR lookup is
ownership-filtered (see Solution Architecture).

Single-pr gains `merge_readiness -> merge_route -> merge_attempt ->
merge_confirm` with two new terminals, `merged` and `ready_awaiting_merge`.
`merge_readiness` runs `merge-verdict.sh`, which reads one snapshot, applies
the decision table in Solution Architecture, owns the CI deadline, and writes
a verdict to koto context. `merge_route` routes on that verdict.
`merge_attempt` is agent-run (never a default action) and runs exactly
`merge-exec.sh <repo> <pr> <expected-head>`, the only `gh pr merge` call
site in the repository, which recomputes the verdict itself and accepts no
pass-through flags (see Key Interfaces > Script interfaces). `merge_confirm` re-reads
the PR and reaches `merged` only if GitHub reports `MERGED`. Merge intent is a
template variable set at `koto init` from `--merge`, never agent evidence, so a
run without `--merge` can't merge. `ci_monitor`'s gates and DIRTY route stay
as they are; its `passing` and `failing_fixed` edges retarget to
`merge_readiness`, which closes the ungated shortcut. The coordinated loop
calls the same two scripts per node in merge order and on the coordination PR
last. Decision 6 takes the verdict write out of the agent's hands: a default
action on `merge_readiness` records it.

#### Alternatives Considered

**Fold the merge into `ci_monitor`.** Fewer states. Rejected: koto's polling
ends early only when every gate passes, and `merge_state_clean` never passes
on a blocked PR, so the wait limit would fall back to agent prose the shim
can't check (D4); it would also take merge intent as agent evidence.

**A post-workflow merge script at the SKILL layer.** koto ends green and
SKILL.md runs one script that decides and merges. Rejected: the session's own
record says "done" before any merge, and one script that both reads and
writes leaves no check able to disagree with the action (D3). Its
shell-testable, fixed-flag script survives inside the chosen option.

**Merge outside `/execute`** (in `/work-on` children, or in `/deliver` after
`/execute` returns). Rejected: single-pr has no child PR to merge; adding a
merge flag to children breaks the parent-child rule (D1); and driver-side
merging contradicts the PRD's placement of `--merge` on `/execute`, removes
merging for direct `/execute` users, and puts a merge-and-rerun loop in the
driver (D8).

### Decision 4: The shape of `/deliver` and how its children report

`/scope` and `/execute` are both koto-backed parents with their own state
files, sessions, and resume ladders. Under D9 the driver that sequences them
should be a koto workflow too, and the children's outcomes should reach it
through koto rather than through printed lines the agent relays. The
child-inspection reference lists a child's state file as internals a caller
must not read, so any koto channel has to carry a result the child declares
itself. CI requires every skill to ship `requires.tsv` and
`evals/evals.json`; the plugin manifest discovers skills by directory.

Measurements on koto 0.12.2 set the constraints:

- **Parents link to children by name only.** `koto session cleanup <parent>`
  doesn't cascade, and a new parent initialized under the same name inherits
  the old run's live children. A leftover child that finishes writes its
  completion into the new parent's log. Composing child names as
  `<parent>.scope` doesn't close that hole.
- **A `--parent` child can't both keep its record and report it.** It either
  deletes itself at its terminal or, with `--no-cleanup`, emits no result at
  all (koto#240).
- **koto's request store already separates retention from the result.** A
  root session attached to a request leg sends its result to the leg on its
  terminal tick even under `--no-cleanup`, and keeps its session. Once a
  request is abandoned, a late result from it is refused. What's missing:
  only dispatch children can bind to a leg, and no gate type reads one.
- **`koto init` checks variables but can't express shirabe's rules.** It
  refuses a missing, unknown, or duplicate `--var` with exit 2 and no session,
  but has no enum or pattern constraint, can't rebind a live session's
  variables, and says "already exists" for a live session and a retained
  terminal one alike.
- **Two features the templates already assume don't run.** Transition
  `context_assignments` are dropped silently by the compiler (koto#204), and
  terminals declare no result.

On the shirabe side, not every `/scope` path opens a session. Its refusals
happen before `koto init`, and its planned `--intent` shortcuts (PLAN exists:
re-publish; PLAN executed: report the PR) open none. `/scope` also retains its
terminal session but never checks `is_terminal` on reattach, so a re-run
ticks a finished session into nothing.

Key assumptions:

- koto ships the required changes K1-K6 (Solution Architecture > koto
  changes) in one release before shirabe's dependent changes merge, and
  shirabe raises its koto floor for `/scope`, `/execute`, and `/deliver`. If
  the leg gate (K6) slips, `deliver.md` routes through a command gate over
  `koto request get` instead, which works on 0.12.2 and is weaker on D9 but
  functional.
- koto's maintainers accept admitting root sessions to a leg. koto's
  request-lifecycle design gets an amendment saying why its epoch fence isn't
  needed for roots: roots are never redelegated, and their results arrive by
  promotion, not through the fenced verbs. If the carve-out is rejected, the
  fallback is both children as `--parent` children with a parent-side fence,
  which needs koto#240.
- The request store's limits are acceptable for v1: it's unix only, isn't
  replicated under koto's cloud backend, and has no prune yet.
- The two-driver race is accepted, as it is in every option (see Security
  Considerations).
- `/scope`'s clean cancel maps to `scope-ended-early` naming `cancelled`.

#### Chosen: stable-named root children attached to per-run koto request legs

Both children keep one session per topic, `scope-<topic>` and
`execute-<topic>`, whoever launched it: a direct run, a `/deliver` run, or a
direct run that `/deliver` later picks up. Both stay root sessions that
retain their record (`--no-cleanup` on every tick) and carry no `--parent`
link. Each `/deliver` invocation opens a fresh `deliver-<topic>` session. Its
`open_request` state abandons any request still open under that coordinator
and creates one request with two legs, `scope` and `execute`. The children
join through a flag each owns and documents for use with any koto
coordinator, `--koto-leg=<request-id>:<leg>` (D1), and report through a
declared `result:` map on every terminal, which koto promotes to the leg
(K1). `/deliver` reads each leg through a `request-leg` gate (K6) and routes
on the child's `outcome`. It never parses a printed line.

Every `/scope` path reaches a koto record, and the agent composes none of
them:

- **Static argument checks run inside `koto init`.** `scope.md` declares its
  inputs as constrained variables (K3). `scope-open.sh` passes the
  invocation's raw tokens through `koto init --vars-file` (K4), so a repeated
  or invalid `--intent` is a koto refusal with exit 2, no session, and no
  state file (R1). Under `--koto-leg`, koto records the refusal on the leg
  itself.
- **Attach-time checks run inside koto too.** `--attach-live` refuses an
  explicit variable that differs from a live session's recorded one, so
  `--intent=continue` against a live `intent=stop` run is `var-mismatch:INTENT`,
  recorded on the leg with the session untouched. It also rebinds the
  variables marked `rebind: true` (`MERGE`, `PLUGIN_ROOT`). `--replace-terminal`
  gives a finished topic a fresh session, which fixes the retained-terminal
  bug.
- **Checks that need a session and the working tree run in two new template
  states**, `intake` and `resume_route`. Every outcome is a terminal with a
  result: `done_refused`, `done_error`, `done_republished`, and
  `done_executed` join the existing ones.

The request id is the stale-run fence. A run reads only its own request's
legs, and older requests are abandoned before the new one is created, so a
late result from an old run is refused at promotion. A leftover terminal
session is replaced at init and never read. A standalone run has no leg and
touches nothing in the request store; when `/deliver` later picks the topic
up, attach binds the same session.

A child's word never moves the run forward on its own. Every progress arm
requires a promoted result, and each is re-checked against durable state
before the next step: `scoped_check` verifies the PLAN is tracked and the
owned PR records `intent=continue`, `mode_route` reads the PLAN's mode,
`executed_check` re-reads the owned PR, and `merged_check` re-reads GitHub.
Two cases can't produce a koto record: a `--koto-leg` naming no open leg, and
a `/scope` too old to know the flag. The agent reports that the Skill
returned, and `/deliver` resolves the still-open leg as
`deliver:child-absent`, an arm that can only reach an error.

#### Alternatives Considered

**A stateless SKILL.md that sequences two Skill calls (the previous
choice).** `/deliver` would have no template, would parse the children's exit
lines, re-read the PLAN's mode, and relay the result. Rejected under D9:
sequencing, the confirmation, and outcome mapping would all be prose, and
`merged` would rest on a printed token. The driver also couldn't tell
`/execute`'s review pause from a failed batch, or a CI timeout from an
awaiting merge, without re-implementing `/execute`'s merge rows, because
only `/execute`'s own session holds that difference. Its
enter-through-`/scope` resume model survives inside the chosen option.

**`/scope` inline, `/execute` as a `--parent` child.** `/deliver` is a koto
workflow; `/execute` joins through a `--koto-parent` flag and reports through
a child-state gate, while `/scope` stays a plain call gated on durable files.
The author overruled the asymmetry, and it costs more than it looks.
`/scope`'s stop outcomes would still arrive as agent evidence, and there'd be
two observation mechanisms to document. `/execute` would lose "always a
root" and need role-routed retention until koto#240 lands. A parent linking
by name still leaks stale children. And an interrupted direct `/execute` run
couldn't be adopted, so it would end as a new `deliver:child-detached` error.
Its durable re-checks (`scoped_check` with the recorded-intent check,
`executed_check`, `merged_check`) are kept.

**Both children as `--parent` children with a parent-side fence.** Keeps
koto's hierarchy and stamps the parent's session id on each child's
completion. Rejected as the channel. It needs a parent session id in child
headers, adoption events for a live direct run, a refusal event distinct from
a completion (so batch views don't count it), and a child-state gate with a
latest-event-wins rule: three to five new mechanisms where the chosen option
needs one verb and one gate. It still can't let a child keep its record
without koto#240. Its `koto init` surface (variable constraints,
`--vars-file`, `--replace-terminal`, `--attach-live`, rebind) is adopted, and
it remains the fallback if koto rejects the root carve-out.

**Composed per-parent child names (`deliver-<topic>.scope`) with init-first
intake.** Rejected. Composed names don't close the stale-child hole, which
the option's own advocate measured. Two namespaces for one topic would need a
live direct run migrated. Children still couldn't retain `/scope`'s per-hop
record. And intake refusals would open a session, against R1's wording. Its
in-session intake is adopted for the checks that genuinely need a session:
the upstream battery, the recorded intent of an unfinished run, and the
resume ladder.

### Decision 5: Where `/scope` publishes under `--intent`

`/scope`'s koto template runs `finalize -> exit_* -> cleanup_* -> done_*`.
Cleanup deletes the state file, which R12 needs after a failure and which
holds the durable record Phase 3 says belongs in "the run's pull-request
body", a PR that doesn't exist today. `/execute` adopts a home PR by head
branch (`gh pr list --head <branch>`), not by title. A branch can also carry
tracked `wip/` from an upstream workflow such as `/explore`. A publish can
fail after the PLAN is written, and a later run has to retry it.

Key assumptions:

- koto accepts a transition condition that combines two gates with an
  evidence field; if not, exits always route through the publish state and a
  no-intent run passes straight through it with a `not-requested` value.
- `INTENT` is a constrained koto variable defaulting to `unset`, and `intake`
  resolves the effective intent, `RUN_INTENT`, from it and the recorded value
  (Decision 4).

#### Chosen: dedicated publish states backed by `publish-scoping-pr.sh`

Three states, `publish_full_run`, `publish_re_evaluation`, and
`publish_abandonment`, sit between each exit state and its cleanup. A new gate
on the exit states, `intent_declared` (`test "{{RUN_INTENT}}" != none`), sends
no-intent runs through today's states with no `gh` call (D2). Each publish
state's `published` gate runs the script's `--verify` mode, which checks that
the remote branch equals `HEAD` and exactly one PR exists on it, so a run
can't claim a PR it didn't open (D4).

A failed publish records `publish_error:` in the state file and ends the run
at `done_error` with `step=scope:push` or `scope:pr-create`, so a parent
reading the leg gets the error the PRD's Final States require. Cleanup hasn't
run on that path, so the state file survives. The retry is the next
invocation: its fresh session's `resume_route` sees `exit:` together with
`publish_error:` and routes straight back to the matching publish state,
which is idempotent (D6).

The two `--intent` shortcuts in `/scope`'s resume ladder run as template
states rather than prose. When a PLAN already exists, `republish` re-runs the
publish script, which rewrites the PR body's `intent=` field, verifies it,
and ends at `done_republished`. When the PLAN was executed and removed,
`executed_report` reads the owned PR and ends at `done_executed` with its
`pr_state`.

#### Alternatives Considered

**Publish inside the exit states.** Rejected: a failed push would either block
the exit from being recorded (breaking R12) or need error arms on every exit
state, and the exit states are re-entered from several places.

**Publish inside cleanup.** Rejected: cleanup deletes the state file R12 needs,
accepts only `done`, and deleting files from disk doesn't untrack committed
`wip/`.

**A script with no workflow state.** Rejected: nothing would check that the
publish happened, so an intent run could finish with no PR, and nothing would
record which exit a retry has to publish. The script survives inside the
chosen option.

**One shared publish state for all exits.** Rejected: the agent would re-state
which exit it took, and no gate could check it.

**Park a failed publish in the publish state (the previous choice).** The
session would hold there, and re-running `/scope <topic>` would reattach and
retry. Rejected: a parked session leaves a parent waiting on an open leg with
no outcome to print, while the PRD requires `error step=scope:push`. It's the
non-terminal path Decision 4 removes. And the retry needs no live session,
because the state file's `exit:` plus `publish_error:` routes the next
invocation back to the publish state.

### Decision 6: Which prose-carried pieces move into koto

Setting `/deliver` aside, the design left six pieces to skill prose or to
values the agent writes: the merge values that routing depends on, the
exit-line outcomes, the `/plan` hop's flag forwarding, the coordinated loop,
`/scope`'s `--intent` parsing and mismatch refusal, and whether `/plan`
itself should get a template. Each was weighed under D9 on what koto
enforcement adds and what it costs.

One finding changed the picture. koto has no working transition-level
`context_assignments`: the compiler's transition type deserializes only
`target` and `when`, and nothing rejects unknown fields. All 60
`context_assignments:` blocks in shirabe's templates are silently dropped,
including every `failure_reason` write in `execute.md` and `scope.md`, which
koto's own batch view reads for failed children. The PLAN already depended on
a koto feature that doesn't exist.

Other koto facts that bound the answer: a `default_action` can capture stdout
and call `koto context add`, but it runs under a 30-second limit, runs again
on every entry, and can't set evidence. `when` does strict equality only. One
tick that revisits a state raises `CycleDetected`. `materialize_children`
releases a dependent on terminal success, never on a merge, and a child's
context is deleted at its terminal unless it retains.

Key assumptions:

- `merge-verdict.sh` finishes one snapshot read inside koto's 30-second
  default-action limit on a normal network. If it doesn't, `merge_readiness`
  stays agent-run and only the wrapper script moves.
- shirabe CI runs a koto at or above the new floor.
- A multi-repo coordinated run can't satisfy koto's rule that children tick
  at or below the parent's anchor unless the anchor is the workspace root.
  This hasn't been verified, and it's one reason a full coordinated template
  waits.

#### Chosen: enforcement moves now; structural rewrites wait

- **Merge values.** The agent no longer writes the verdict. `merge_readiness`
  gains a default action running `record-merge-verdict.sh`, which reads
  `merge_requested` and `expected_head` from koto context, computes the AND
  with `MERGE` in code, resolves the PR through the owned-PR script, runs the
  unchanged `merge-verdict.sh`, and writes the verdict line with
  `koto context add`. `merge_route` keys on anchored `context-matches` gates
  over that line, and the `pending:` loop back to readiness passes through an
  agent-evidence hop (`recheck: waited`) so one tick never revisits a state.
  `expected_head` is written by the push itself: `run-cascade.sh --push` and
  a new `push-and-record.sh` record `git rev-parse HEAD` after a successful
  push, and a gate on `plan_completion` makes a missing record visible.
  Coordinated `head=` fields are written only by `node-push.sh`, which
  validates the new coordination body before editing it. `merge_requested`
  stays the one agent-written merge value. It's the skill's parse of this
  invocation's flags, which no action can see, and it can only narrow `MERGE`.
- **Outcomes.** Every edge into a terminal assigns `outcome`, `step`, and
  `reason` through `context_assignments` (K2), and every terminal declares a
  `result:` map built from them (K1). The outcome-versus-exit table moves out
  of SKILL.md prose into template edges, where the engine-backed retention
  tests walk it. Scripts render the printed exit block from the terminal
  result (`print-scope-exit.sh`, `/execute`'s `print-exit.sh`, and
  `deliver-report.sh`); the agent never composes it. The printed lines stay
  the human-facing contract. Parents read the leg.
- **The `/plan` hop.** koto can't see a Skill call, but it can check what the
  call produced. `scope.md` gains a `COORDINATION` variable, and `hop_plan`'s
  `landed` edge requires a `plan_mode_consistent` gate. Its script,
  `check-plan-mode.sh`, exits 0 at once when the effective intent is `none`
  (D2). Otherwise it re-runs `/plan`'s `resolve-split-mode.sh` over the
  PLAN's split record, the forwarded intent and coordination flag, and the
  CLAUDE.md headers, and compares. A mismatch routes to `bail`, so a hop that
  dropped or invented a flag is caught before publish. `publish-scoping-pr.sh`
  reads the mode from the PLAN's frontmatter rather than from evidence.
- **`--intent` parsing and mismatch refusal.** These move into koto through
  Decision 4's constrained variables and init flags (K3, K4), with the two
  checks that need the working tree in `intake`.
- **The coordinated loop.** Its decision logic moves into a stateless
  `coordinated-next.sh`. It reads the PLAN's nodes, the coordination PR's
  index through the ownership filter, and live `gh`, and prints exactly one
  next action: `dispatch:<node>`, `evaluate:<node>`, `merge:<node>`,
  `cascade`, `evaluate-coordination`, `merge-coordination`, `pause`,
  `done:<outcome>`, or `error:<step>`. Node mechanics move into `node-cut.sh`
  and `node-push.sh`. A thin koto envelope, `execute-coordinated.md`, wraps
  the loop so the coordinated path ends in the same result-declaring
  terminals as single-pr, which Decision 4 needs. A full coordinated template
  with per-action states and per-node children waits for its own design.
- **`/plan`.** No template. The one decision this feature changes is already
  deterministic in `resolve-split-mode.sh`, and the hop gate checks its
  result from `/scope`'s side.

#### Alternatives Considered

**Move everything now, including a full coordinated template and a `/plan`
template.** Rejected for those two pieces. Per-node children can't express
"wait until merged": `waits_on` releases on terminal success, child context
is deleted at the terminal, and a pause lasts as long as a human review. The
coordination PR, not a machine-local session, is the durable resume record D6
asks for. The multi-repo anchor question is unverified. A `/plan` template is
a design of its own. The script-driven loop makes a later coordinated
template a thin wrapper.

**Keep the prose and file follow-ups.** Rejected: agent-written values would
keep feeding a merge decision, outcome mapping would stay in prose against
D9, and `/execute`'s step records would never be written, because koto drops
the assignments that carry them.

**Coordinated first.** Rewrite the coordinated loop as a template now and
defer the smaller moves. Rejected: it pays the largest cost where the
unknowns are (the multi-repo anchor, durable resume from the coordination
PR), and it leaves the cheap trust fixes undone.

## Decision Outcome

The six decisions fit together as one pipeline, and koto carries its
sequencing. At launch, `/deliver` opens a fresh `deliver-<topic>` koto
session, abandons any earlier request for the topic, and creates a request
with a `scope` leg and an `execute` leg. It runs
`/scope --intent=continue --koto-leg=<req>:scope`. koto checks `/scope`'s
arguments at `koto init` and attaches its session to the leg. `intake`
resolves the effective intent, and `resume_route` decides where the topic
stopped. On a fresh topic, `/scope` forwards intent to `/plan`, which settles
whether the work splits exactly as it does today and then, only on a split,
picks `coordinated` or `multi-pr` by the precedence rule. It can now emit
`coordinated` for one repository or many, with one PR group per split unit. A
gate on the hop checks the PLAN's mode against what was forwarded. `/scope`
publishes one PR on the pushed branch after the exit is recorded and before
cleanup, and ends at a terminal whose result koto promotes to the leg.

`/deliver`'s `scope_run` state routes on that result through the leg gate.
It re-checks the PLAN and the owned PR, reads the mode, asks one confirmation
when interactive, and runs `/execute --koto-leg=<req>:execute` with `--merge`
unless `--no-merge`. `/execute` adopts the PR, runs its existing children,
and, with `--merge`, merges through a script-recorded verdict and one
fixed-flag merge script. Single-pr does it through four new koto states;
coordinated does it node by node in merge order with the coordination PR
last, driven by `coordinated-next.sh` inside a thin envelope template. The
terminal result reaches the execute leg, and `/deliver` re-reads GitHub
before it reports `merged`. Every printed exit block is rendered from a
terminal result.

Cross-validation found no conflicting assumptions that needed a decision to be
re-run, and settled these seams:

- **Who opens coordinated node PRs.** Decision 3 assumed `/work-on` children
  open them; Decision 2 has `/execute` open one PR per node on a shared
  branch. Decision 2's shape stands, and Decision 3's scripts run on those PRs
  unchanged.
- **Intent mismatch.** A live session with a different recorded intent is
  refused by koto at attach (`var-mismatch:INTENT`); an unfinished run whose
  session is gone is refused by `intake` (`intent-mismatch`). `/deliver` maps
  both to `deliver:intent-mismatch`. A finished run whose PR records
  `intent=stop` isn't a mismatch: the re-run republishes and rewrites the
  PR's `intent=` field.
- **Finished single-pr topics.** After a single-pr run the cascade deletes the
  PLAN. `/scope`'s `executed_report` state reads the branch's owned PR and
  ends at `done_executed`; `/deliver`'s `executed_check` re-reads it and
  reports `merged` or `ready-awaiting-merge`. `/deliver` always enters
  through `/scope`, so a publish that failed after the PLAN was written is
  retried before `/execute` runs.
- **Error line spelling.** Every skill prints `outcome=error` followed by
  `step=<step>`.
- **koto change numbering.** Decision 6 was drafted with its own working
  numbers. This document uses Decision 4's K1-K10 everywhere:
  `context_assignments` is K2 and the terminal result map is K1.
- **Terminal results.** Decision 6 first deferred a koto terminal result to
  the `/deliver` redesign. Decision 4 needs it, so K1 is required, and the
  exit-render scripts read the result rather than falling back to state names
  on an older koto, which the floor rules out.
- **Variable constraints.** Decision 6 first kept `--intent` parsing in
  Phase 0 because an older koto rejects constraint fields. The koto floor
  removes that obstacle, and Decision 4 makes the constraints required (K3).
- **Effective intent.** `intent_declared` and `check-plan-mode.sh` key on
  `RUN_INTENT`, not the raw `INTENT`, which can now be `unset` on a bare
  re-invocation.
- **Coordinated envelope.** Decision 6 defers a coordinated template, while
  Decision 4 needs coordinated terminals with results. The envelope is three
  states around the script-driven loop; the full template stays deferred.
- **The intermediate `/deliver` revision is superseded.** It had `/scope`
  inline and `/execute` as a `--parent` child. Its `--koto-parent` flag,
  role-routed retention for `/execute`, child-state gate, and the
  `execute:session-root` and `deliver:child-detached` steps are dropped. Its
  durable re-checks stay.
- **Delivery shape.** Decision 6 expected shirabe to stay one PR with one
  small koto prerequisite. With six required koto changes, the work is a
  coordinated effort across both repositories (Implementation Approach).

The PRD's Final States, R17, and R19 were clarified to match: the added
`execute:*` and `deliver:child-outcome` steps, the merge-method rule for
repositories that allow merge and rebase but not squash, the 30-minute CI wait
limit, the declined-confirmation outcome, and the executed-topic resume row.
This revision adds `cancelled` under `scope-ended-early`, the steps
`scope:refused`, `execute:refused`, `deliver:child-absent`, and
`scope:intake`, and R1's refusal recorded on the leg under `/deliver`.

## Solution Architecture

### Overview

Four existing skills change, one is added, and koto gains six required
features. The shared contracts (coordination strategy, state schema,
draft/ready discipline, parent-skill pattern) change first among the shirabe
pieces because every skill reads them. The data that crosses skill
boundaries is small and explicit: the `--intent`, coordination, `--auto`,
`--merge`, and `--koto-leg` flags going down, and the PLAN's
`execution_mode`, the pushed PR, and each child's terminal result on its
request leg coming back up. Printed `key=value` exit lines remain for people
and evals.

```
/deliver <topic> [--auto|--interactive] [--no-merge] [scope flags]
   |  deliver-open.sh -> koto init deliver-<topic> --vars-file
   |  preflight -> open_request: abandon old requests, create REQ {scope, execute}
   |  scope_run: Skill /scope <topic> --intent=continue --koto-leg=REQ:scope ...
   |        scope-open.sh -> koto init scope-<topic> --vars-file --attach-live
   |                         --replace-terminal --koto-leg (refusals land on the leg)
   |        intake -> branch_check -> resume_route -> setup ... hop_plan
   |        /plan hop: <design> --intent=continue [--coordinated|--no-coordinated] [--auto]
   |             step 3.6: split? (unchanged) -> step 5a: coordinated | multi-pr
   |        exit_* -> publish_* (intent only) -> cleanup_* -> done_* {result}
   |        or republish -> done_republished; executed_report -> done_executed
   |  scope_leg gate -> scoped_check -> mode_route -> confirm (interactive)
   |  execute_run: Skill /execute docs/plans/PLAN-<topic>.md [--merge] --koto-leg=REQ:execute
   |        single-pr: ... ci_monitor -> merge_readiness -> merge_route
   |                   -> merge_attempt -> merge_confirm -> merged | ready_awaiting_merge
   |        coordinated: coord_setup -> coord_loop (coordinated-next.sh) -> coord_verdict
   |  exec_leg gate -> merged_check (on merged) -> done | done_stopped | done_error
   `- deliver-report.sh prints the terminal result
```

### Components

**koto changes** (in `tsukumogami/koto`). K1-K6 are required and ship in one
release; K7-K10 are off the critical path.

- **K1. Declared terminal `result:` map (required).**
  - Terminal states gain an optional `result:` whose values are literals,
    `{{VAR}}`, or `${context.<key>}`. Keys match `^[a-z_]+$`, with at most 16
    keys and 4 KiB per value. A missing key resolves empty and is listed in
    `missing`.
  - On the terminal tick the map is written to the workflow result's
    exports. It rides the request-store result, the leg promotion, the
    parent's child-completed event, the terminal `koto next` response, and
    `koto status` for a retained terminal.
  - Code: `SourceState` in `src/template/compile.rs`, `TemplateState` in
    `src/template/types.rs`, `synthesize_workflow_result` and
    `finish_terminal_tick` in `src/cli/mod.rs`, and the response types in
    `src/cli/next_types.rs`.
- **K2. Transition `context_assignments` (koto#204, required).**
  - Values are literals, `{{VAR}}`, `${evidence.<field>}`, and
    `${gates.<g>.<field>}`, including `${gates.<g>.exports.<k>}` for the leg
    gate. They're written atomically with the transition event.
    `${evidence.<field>}` must name a declared `accepts` field, and unknown
    transition fields fail compilation instead of being dropped.
  - Code: `SourceTransition` in `compile.rs`, `Transition` in `types.rs`,
    the advance loop in `src/engine/advance.rs`, and the W5 lint, which
    credits assignments that write `failure_reason`.
  - It makes shirabe's 60 existing assignment blocks run.
- **K3. Variable constraints and rebinding (required).**
  - `values:`, `pattern:`, and `rebind: true` on variable declarations
    (`VariableDecl` in `types.rs`, `SourceVariable` in `compile.rs`), with the
    default validated at compile time.
  - `resolve_variables` in `src/cli/mod.rs` returns typed errors
    (`invalid_var`, `duplicate_var`, `unknown_var`, naming the variable,
    value, and constraint).
  - A new verb, `koto session rebind <session> --vars-file <file>`, accepts
    only `rebind: true` keys and refuses a terminal session. It appends a
    `VariablesRebound` event, which `bindings_from_events` in
    `src/engine/substitute.rs` folds.
- **K4. `koto init` entry flags (required).**
  - `--vars-file <path>`: a JSON array of `[key, value]` pairs, so duplicate
    keys survive to be refused. Variable validation moves ahead of the name
    and "already exists" checks.
  - `--replace-terminal`: replaces only a terminal session and returns its
    old result; a live session is refused.
  - `--attach-live`: on a live session, compares the given non-rebind
    variables with the recorded ones (`var_mismatch` names the variable, the
    recorded value, and the requested one), then rebinds the `rebind` keys.
  - `--koto-leg <req>:<leg>`: after create or attach, performs K5's attach.
    On any refusal (a bad, duplicate, or mismatched variable, a name error,
    or an attach refusal), koto resolves the unbound leg itself with
    `source: refused` and exports `{outcome: refused, reason, var, recorded,
    requested}`. Exit codes don't change.
  - Code: `handle_init` in `src/cli/mod.rs` and `init_child.rs`.
- **K5. `koto request attach <req> <leg> --session <s>` (required).**
  - Admits root sessions as well as the existing dispatch children, refuses
    a terminal session, and checks the leg's declared inputs against the
    session's non-rebind variables.
  - Idempotent for the same session. It re-points a session only when its
    current pointer names an abandoned leg or a closed request.
  - Writes the leg-bound event (`attach: self`, dispatch epoch 0) before the
    pointer sidecar, and adds `result_source: refused` to the leg view.
  - Amends koto's request-lifecycle design (its Decision 3 and Security
    Considerations) and the `child_not_fenceable` message with the root
    carve-out.
  - Code: `src/cli/request.rs` and `src/engine/request_store/`, reusing
    `bind`.
- **K6. `request-leg` gate type (required).**
  - Fields: `request`, `leg`, and an optional `expect: {key: [values]}`.
  - Output: `found`, `disposition` (open, resolved, abandoned, missing),
    `bound`, `source` (promoted, explicit, refused), `status`,
    `final_state`, `outcome`, `step`, `reason`, `valid`, `exports`, and
    `error`. An open leg is a temporal block.
  - Override default: `{disposition: resolved, source: explicit, valid:
    false}`, so a forced gate can only reach an error arm.
  - Code: the gate schema and default beside `gate_type_schema` in
    `types.rs`; evaluation in `src/gate.rs` over the request store's read
    view.
- **K7. Retention separate from result emission (koto#240, recommended).**
  It serves `/work-on`'s batch children, which stay `--parent` children, and
  would retire their role routing.
- **K8. `overridable: false` on gates (recommended).** Refuses
  `koto overrides record` for `merged_check`, `scoped_check`, and
  `/execute`'s `merge_confirm`.
- **K9. Request prune and listing by coordinator (recommended).** Listing
  exists; prune doesn't.
- **K10. The `children-complete` `name_filter` fix for cleaned-up
  non-composed children (optional).** Independent, and not used here.

**Shared references.**

- `references/coordination-strategy.md`:
  - "one or more repositories"
  - the four-level mode precedence
  - the single definition of which `## PR Grouping Policy:` /
    `## Reviewability Ceiling:` values mean coordinated by default (pinned to
    what `/scope` Phase 0 resolves today)
  - a Branches paragraph (one branch per PR node, cut from the default
    branch)
  - the merge step and the `paused-awaiting-merges` pause in the lifecycle
  - template blockquote without "multi-repo" after the unchanged prefix
- `references/parent-skill-state-schema.md`: `plan_execution_mode` gains
  `coordinated`, plus a note that a parent may declare an always-present
  invocation-intent field. `intent` gains `unset` at the koto variable level
  only; the state file still records `continue|stop|none`.
- `docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md`: an
  "Opt-in agent merge" paragraph, and the coordination-PR exception amended so
  `/execute` marks it ready once every indexed PR has merged.
- `references/parent-skill-pattern.md`: `--koto-leg` as the pattern-level
  child flag, and a "Parent-of-the-Parent Binding" subsection for a
  koto-backed driver (a template, a request per run, children as
  leg-attached roots).
- `references/parent-skill-child-inspection.md`: a row for a leg-attached
  child, whose observable surface is its leg's promoted result exports, read
  only through the `request-leg` gate.
- `references/koto-session-retention.md`: `/scope` retains on every tick; a
  leg-attached root reports by promotion, which `--no-cleanup` doesn't
  suppress; `--replace-terminal` replaces the "read, then clean up" recovery.
  `/execute` stays always-root.
- `references/default-action-conversion.md`: `merge_readiness`,
  `republish_record`, and the request-store actions (`open_request`,
  `scope_absent`, `execute_absent`) join the converted states.

**`/plan`.**

- `SKILL.md`: the three flags, with rejection of bad or repeated values
  before any `wip/` write; a "Split mode" rule; "Coordinated Mode" without
  "(multi-repo)".
- `phase-3-decomposition.md`: step 5a and the `split_mode_source` field. Step
  5a calls a deterministic `scripts/resolve-split-mode.sh` (split verdict,
  flags, intent, CLAUDE.md headers in; `execution_mode` and
  `split_mode_source` out) rather than resolving the precedence in prose, so
  the one decision this feature turns on is table-tested, not model judgment. On a
  `coordinated` outcome, every issue gets `_Repo: <owner/repo> | Group:
  <unit-slug>_`.
- `phase-4-agent-generation.md`: coordinated gets full issue bodies.
- `phase-7-creation.md`: a coordinated branch reusing `create-issues-batch.sh`,
  with the explicit filing approval; single-pr and coordinated next-step
  advice names `/execute` (R23).
- `scripts/plan-to-tasks.sh`: `REPO`, `PR_GROUP`, and `ISSUES` node vars, and
  refusal text saying "atomicity across PR groups".
- Step 5a also runs on `/plan`'s interactive override path and on direct
  roadmap input, whose split branch is Incremental Value; both then resolve
  the mode by the same precedence.
- A `gh` shim under `skills/plan/evals/fixtures/bin/` that logs `issue create`
  calls (new).

**`/scope`.**

- Constrained variables in `scope.md` (K3):
  - `TOPIC`: pattern `^[a-z0-9-]+$`;
  - `PLUGIN_ROOT`: `rebind: true`;
  - `INTENT`: `continue|stop|none|unset`, default `unset`;
  - `COORDINATION`: `none|coordinated|no-coordinated`, default `none`;
  - `EXEC_MODE`: `auto|interactive|default`;
  - `MAX_ROUNDS`: 1 to 50, or empty;
  - `UPSTREAM`: a repository-relative `docs/roadmaps/ROADMAP-*.md` path or an
    `owner/repo:path`, or empty.
- Phase 0 keeps only tokenizing and the residue rule. The agent writes the
  invocation's tokens to a nonce-named args file with the Write tool.
  `scripts/scope-open.sh`, a thin wrapper over the shared
  `scripts/koto-open.sh`, maps each flag occurrence to one pair and runs
  `koto init --vars-file --attach-live --replace-terminal`, adding
  `--koto-leg` when given, then deletes the args file. A repeated `--intent`,
  both mode flags, or both coordination flags becomes a duplicate key koto
  refuses. `scope-open.sh` renders koto's structured errors in today's exact
  wording (D2), for example "Topic slug `Foo` does not match the required
  pattern `^[a-z0-9-]+$`." and `intent-mismatch recorded=<x> requested=<y>`.
  The cold-start prompt stays before init on a standalone run. The probe,
  reattach, and origin prose move into the script and into koto.
- `--koto-leg=<request-id>:<leg>`, checked against koto's request-id pattern
  and a closed leg-name set. It changes nothing but where the result goes, so
  a direct user can pass it with any koto coordinator.
- Retention: `--no-cleanup` on every tick, unconditionally.
- `initial_state` moves to `intake`. Its read-only default action runs
  `resolve-intent.sh` and captures `RUN_INTENT` (`unset` becomes the recorded
  value or `none`). Two gates run local checks only: `check-upstream.sh` (the
  `--upstream` filesystem battery) and `check-recorded-intent.sh` (an
  unfinished run with no live session whose state file records a different
  intent). Failures route to `done_refused` with a reason or `done_error`
  with `scope:intake`.
- `branch_check`'s setup target becomes `resume_route`. Its single gate runs
  `resume-probe.sh`, the whole resume ladder as one table-tested probe. The
  probe reads only the artifact tree, `/scope`'s own state file, the child
  partials, and the handoff; keeps the documented first-match order; and
  exits with a row code that gate-only transitions route (see Key
  Interfaces). `phase-resume.md` stays the normative spec, with each row
  naming its exit code and target state. The ladder's prompts become states
  (`resume_stale`, `resume_malformed`, `resume_exit_set`, `resume_draft`,
  `resume_boundary`) with identical wording and choices.
- Shortcut states under intent:
  - `republish` is agent-run, because it pushes and may open a PR. It runs
    `publish-scoping-pr.sh`, which rewrites the PR body's `intent=` field,
    and its gate runs `--verify --expect-intent`. `republish_record`, a
    default action running `record-scope-exit.sh`, then records the outcome
    keys from the PLAN's frontmatter and the owned PR, and the run ends at
    `done_republished`.
  - `executed_report` is gate-only. It runs `owned-pr.sh --state all` and
    ends at `done_executed` with `pr` and `pr_state`, or at `done_error` with
    `scope:pr-create` when there's no single owned PR.
  - An Active PLAN with no intent still refuses, with `next=` by mode (R23).
- `/plan` hop forwarding in `phase-2-chain-orchestration.md` and the template:
  `--intent`, the coordination flags exactly as passed, and `/scope`'s own
  resolved mode flag (`--auto` or `--interactive`) when intent is set, so the
  hop runs in the same mode as its parent rather than being forced into
  auto.
- `hop_plan`'s `landed` edge requires the `plan_mode_consistent` gate
  (`check-plan-mode.sh`), with a mismatch edge to `bail`.
- Coordination Intent: with `--intent` set, `/scope` never creates a
  coordination PR up front; the publish step opens it at exit once the PLAN's
  mode is known, so a header-coordinated run that doesn't split never carries
  a coordination PR, and abandonment has no pre-existing PR to close. Without
  intent, today's up-front behavior is untouched (D2).
- Three publish states, plus the `intent_declared` gate on the exit states,
  keyed on `RUN_INTENT`. A publish failure records `publish_error:` and ends
  at `done_error`; the next invocation's `resume_route` routes back to the
  publish state.
- Terminals with result maps (K1): `done_full_run`, `done_republished`,
  `done_executed`, `done_re_evaluation`, `done_abandonment`,
  `done_cancelled`, `done_refused` (failure), and `done_error` (failure). The
  edges into them assign `outcome`, `step`, `reason`, and
  `plan_execution_mode` (K2).
- New scripts, each with a `_test.sh`:
  - `scripts/publish-scoping-pr.sh`, with the `intent=` body field and
    `--expect-intent`
  - `scripts/startable-issues.sh`, which wraps `plan-to-tasks.sh`, keeps roots
    in PLAN order, and reads titles from the issue cells without calling `gh`
  - `scripts/scope-open.sh`, `resolve-intent.sh`, `check-upstream.sh`,
    `check-recorded-intent.sh`, `resume-probe.sh`, `record-scope-exit.sh`,
    and `check-plan-mode.sh`
  - `scripts/owned-pr.sh`, shared with `/execute`
  - `scripts/print-scope-exit.sh`
- The exit-summary block in `phase-4-cleanup.md`, rendered by
  `print-scope-exit.sh` from the terminal result.
- The resume redirect for an Active PLAN routes by mode (R23), and the
  PLAN-status table reflects what `/plan` writes (R25). The phase-2 state-file
  enum re-validation accepts `coordinated` and rejects unknown values (R25's
  testable surface; `shirabe validate` doesn't read state files).
- A `gh` shim under `skills/scope/evals/fixtures/bin/` with a call log (new;
  `/scope` evals have none today).
- State-schema fields `intent:`, `published_pr:`, `publish_error:`.
- A Publish group in Security Considerations, restated in Phases 3 and 4.
- `requires.tsv` gains `gh - - mode:intent` and the koto minimum.

**`/execute`.**

- `--merge` parsed and passed as `MERGE`, which is now `rebind: true` along
  with `PLUGIN_ROOT`, so a resumed run takes this invocation's setting (R17).
- `--koto-leg`, entering through `koto-open.sh` with `--attach-live
  --replace-terminal`, which replaces the read-then-clean recovery of a
  retained terminal. The session stays a root with `--no-cleanup` on every
  tick.
- New scripts, each with a `_test.sh`:
  - `scripts/merge-verdict.sh` (read-only)
  - `scripts/merge-exec.sh` (the only `gh pr merge` line)
  - `scripts/record-merge-verdict.sh`, the `merge_readiness` default action
  - `scripts/push-and-record.sh`, which records `expected_head` after a
    push; `run-cascade.sh --push` does the same
  - `scripts/print-exit.sh`, which renders the exit block from the terminal
    result
  - `scripts/coordinated-next.sh`, `node-cut.sh`, `node-push.sh`, and
    `coordination-verdict.sh`, wired into the execute scripts' CI check
- Four koto states and two terminals, with the `ci_monitor` edge retargets,
  and the regenerated mermaid file. `merge_route` keys on `context-matches`
  gates over `merge_verdict`, and the `pending:` loop takes a
  `recheck: waited` evidence hop. `plan_completion` gains an
  `expected_head_recorded` gate.
- A `result:` map on every terminal, including a `refused` outcome for
  init-time refusals. Record states capture `home_pr` after the
  ownership-filtered adopt and `repos` at start. The edges into
  `done_blocked` write `outcome` and `step`; the pinned DIRTY edge writes
  `outcome=ready-awaiting-merge` and `reason=merge-state:DIRTY`.
- The coordinated loop rewritten as refresh, dispatch, evaluate, merge, and
  pause, with per-node branches and worktrees, driven by
  `coordinated-next.sh` inside a new `koto-templates/execute-coordinated.md`
  envelope under the same session name:
  - `coord_setup` (agent-run) records the write set;
  - `coord_loop` (agent-run) runs `coordinated-next.sh` and the action it
    names until it prints `done:`, `pause`, or `error:`, with evidence
    `loop_status: settled|blocked` carrying a step enum;
  - `coord_verdict` (gate-only) runs `coordination-verdict.sh` over the
    coordination index, the merge-order block, and live node PRs, and
    routes to `merged`, `ready_awaiting_merge`, `paused_awaiting_merges`
    (with `resume=`), or `done_blocked`, each with a result.
  Each node PR is titled `feat(<slug>): <node-id>` with a fixed body template
  (node id, issue numbers, coordination PR link); before `gh pr ready` its
  branch runs the same `wip/` sweep single-pr's finalization runs. The
  chain-finalization cascade runs once, on the coordination branch, after
  every node PR has merged and before the coordination PR is marked ready.
- The ownership filter applied at every existing PR lookup: the four
  `gh pr list --head ... .[0]` sites in `execute.md` and the resume ladder's
  title search, which becomes a head-branch lookup.
- `ci_monitor`'s `failing_unresolvable` edge maps to `outcome=error
  step=execute:ci`.
- An exit summary that always prints `outcome=`.
- The write-set additions, and `requires.tsv` gains the koto minimum.
- R24 wording, enforced by a new `scripts/check-merged-wording.sh` with an
  allowlist.

**`/work-on`.** R24 wording only.

**Validator and CI.**

- Single-repo tests in `crates/shirabe-validate/src/coordination.rs`,
  `merge_gate.rs`, and `crates/shirabe/tests/coordination_body.rs`.
- `.github/workflows/lifecycle.yml` drops a self-referencing PR-index entry.
- CI's koto pin moves to the release that carries K1-K6.

**`/deliver` (new).**

- `skills/deliver/SKILL.md`, with no phase files. It writes the args file,
  runs `deliver-open.sh`, runs the tick loop with `--no-cleanup`, prints the
  terminal result through `deliver-report.sh`, and closes the request on the
  way out.
- `skills/deliver/koto-templates/deliver.md` and its mermaid, with variables
  `TOPIC` (slug pattern), `PLUGIN_ROOT`, `MODE` (`auto|interactive`), `MERGE`
  (`true|false`), and `COORDINATION`, `UPSTREAM`, and `MAX_ROUNDS` under the
  same constraints as `scope.md`.
- Scripts under `skills/deliver/scripts/`, each with a `_test.sh`:
  - `deliver-open.sh`: if a `deliver-<topic>` session exists, checks its
    origin record (worktree and store; a mismatch is a collision and a stop)
    and cleans it, then runs `koto init deliver-<topic> --vars-file`, whose
    refusals it prints;
  - `deliver-preflight.sh`: the visibility check (R29);
  - `deliver-open-request.sh`: abandons open requests for the coordinator,
    creates the new one, prints its id;
  - `deliver-probe.sh`: the `scoped` and `executed` re-checks;
  - `deliver-report.sh`: prints the exit lines from the terminal result.
- A shared `scripts/plan-mode.sh` that maps a PLAN's mode to an exit code.
- `requires.tsv` with the koto minimum and read-only `gh` and `git` (the
  probes and the merge confirm read).
- `evals/` with a `gh` shim, a real koto, and fixtures.
- A row in `README.md`.

### Key Interfaces

**Flags.**

| Skill | Flag | Notes |
|-------|------|-------|
| `/scope` | `--intent=continue\|stop` | A constrained koto variable: invalid or repeated values are refused at `koto init` with no session. On a live session, a differing explicit value is refused as a variable mismatch. |
| `/scope`, `/execute` | `--koto-leg=<request-id>:<leg>` | Child-owned; attaches the session to a koto request leg so the terminal result reaches it. Output is otherwise identical to a direct run. |
| `/plan` | `--intent=continue\|stop`, `--coordinated`, `--no-coordinated` | Child-owned, usable directly. `/scope` forwards only what the caller passed. |
| `/execute` | `--merge` | Becomes the koto var `MERGE`, rebound on every invocation. Never remembered across runs. |
| `/deliver` | `--auto`/`--interactive`, `--no-merge`, forwarded `--upstream`, `--max-rounds`, `--coordinated`, `--no-coordinated` | Mode is resolved once and passed to both children. |

**koto entry.** Every koto-backed skill in this chain enters through
`koto-open.sh`, which runs
`koto init <session> --vars-file <file> [--attach-live] [--replace-terminal]
[--koto-leg <req>:<leg>]`. There are four outcomes:

- a new session;
- an attached live session, when the non-rebind variables match, with the
  `rebind` variables re-applied;
- a fresh session replacing a retained terminal one, whose old result the
  skill may print;
- a refusal with exit 2 and a typed error, rendered in today's wording and,
  under `--koto-leg`, recorded on the leg by koto.

**Requests and legs.** `open_request` creates one request per `/deliver`
invocation with two legs, `scope` (inputs `TOPIC`, `INTENT: continue`) and
`execute` (input `TOPIC`), and captures the id as `REQ`. A leg leaves the
open state in one of four ways:

- **promoted**: the child reached a terminal and koto copied its result;
- **refused**: koto refused the child's arguments or attach and recorded
  `{outcome: refused, reason}`;
- **explicit**: `/deliver`'s absent state resolved it with the fixed
  `deliver:child-absent` error;
- **abandoned**: a newer `/deliver` run superseded the request.

A leg holds one result per run; a retry is always a new `/deliver`
invocation with a new request. Only a promoted, valid result can move
`/deliver` forward.

**Terminal results.** The keys each skill's terminals declare, and so what a
leg carries:

| Skill | `outcome` values | Other keys |
|-------|------------------|------------|
| `/scope` | `scoped`, `handed-off-multi-pr`, `executed` (progress); `re-evaluation`, `abandonment`, `cancelled` (stops); `refused`, `error` | `exit`, `intent`, `next`, `pr`, `pr_state`, `plan_path`, `plan_execution_mode`, `wip_paths`, `startable`, `boundary`, `via`, `reason`, `recorded`, `requested`, `step` |
| `/execute` | `merged`, `ready-awaiting-merge`, `paused-for-review`, `paused-awaiting-merges`, `refused`, `error` | `pr`, `repos`, `resume`, `waiting`, `reason`, `step` |
| `/deliver` | the PRD's Final States for `/deliver` | `step`, `reason`, `pr`, `pr_state`, `repos`, `resume`, `waiting`, `next`, `startable`, `wip_paths` |

`/scope`'s `reason` is one of `invalid-var:<V>`, `duplicate-var:<V>`, or
`var-mismatch:<V>` (from koto), `intent-mismatch`, `upstream-wip`,
`upstream-untracked`, `upstream-outside`, `upstream-basename`,
`plan-active`, or `plan-done`. Its `step` is one of `scope:push`,
`scope:pr-create`, `scope:intake`, or `scope:resume-probe`.

**Exit lines.** One `key=value` per line, rendered from the terminal result by
`print-scope-exit.sh`, `/execute`'s `print-exit.sh`, and `deliver-report.sh`,
and asserted by evals. They're the human-facing contract; no skill parses
another's. `/scope`'s block:

```
/scope finished: exit=<exit>; artifact=<path>
intent=<continue|stop|none>
outcome=<scoped|handed-off-multi-pr|executed|error>   # full-run, executed-topic resume, or publish failure
step=<scope:push|scope:pr-create>            # error only
next=<command>                               # full-run only
pr=<url>                                     # intent runs only
pr_state=<merged|open>                       # executed only
wip_paths=<comma-separated paths>            # intent runs with wip/ in unpushed history
#<N> <title>                                 # multi-pr startable issues, then one closing line
```

Re-evaluation, abandonment, and cancelled runs print today's exit record with
no `outcome=` line, and refusals print today's refusal text.

`/execute` prints `outcome=<token>`, `step=<step>` on error, `repos=<comma-
separated owner/repo list>` (its write set, fixed at start), and for each
unmerged PR `pr=<url> waiting=human|predecessor reason=<condition>`. For a
pause it adds the resume command.

**Script interfaces.** Both merge scripts take everything they decide on as
arguments, and neither reads koto context or state files:

- `merge-verdict.sh --repo <owner/repo> --pr <n> --merge <true|false>
  --expected-head <sha|none> [--confirm]` prints one verdict line and exits 0,
  or exits non-zero on a usage error. `--merge` is true only when both the
  session's `MERGE` variable and this invocation's `merge_requested` are
  true; `record-merge-verdict.sh` computes that and passes it. `--expected-head
  none` makes row 8 fire.
- `merge-exec.sh <owner/repo> <pr> <expected-head>` runs
  `merge-verdict.sh --merge true --expected-head <expected-head>` itself,
  refuses unless the fresh verdict is `mergeable:<method>:<expected-head>`,
  then makes the single fixed-text merge call with that method and sha, and
  prints `merge-called:<method>:<sha>` or `merge-refused:<verdict>`. The
  caller confirms with `merge-verdict.sh --confirm`; `merge-called` is never
  read as merged.
- The expected head always comes from the durable record below, never from
  the live PR. The check guards against pushes the run didn't make; it is not
  a defense against a compromised agent, which the repository's own
  protection covers.

**Merge decision table** (`merge-verdict.sh`, first match wins; the caller has
already run `gh pr ready`):

| # | Live snapshot | Verdict | Outcome |
|---|---------------|---------|---------|
| 1 | `state == MERGED` | `merged` | `merged` |
| 2 | `state == CLOSED` | `error:execute:pr-closed` | `error` |
| 3 | `isDraft` | `error:execute:ready` | `error` |
| 4 | `mergeStateStatus == DIRTY` | `awaiting:merge-state:DIRTY` | `ready-awaiting-merge` |
| 5 | any check failed or cancelled | `error:execute:ci` | `error` |
| 6 | any check pending, a required check (from the base's rules) not yet reported, or no checks yet within a 120 s grace window | `pending:checks` | wait; past the per-head-commit deadline (1800 s, `EXECUTE_CI_WAIT_LIMIT_SECS`, bounded integer), `error:execute:ci-timeout` |
| 7 | merge not requested for this invocation | `awaiting:merge-not-requested` | `ready-awaiting-merge` (no protection or method reads happen on this path) |
| 8 | `headRefOid` differs from the commit this run recorded as pushed, or no pushed commit is recorded | `awaiting:head-moved` | `ready-awaiting-merge` |
| 9 | no checks reported after the grace window | `awaiting:no-checks` | `ready-awaiting-merge` |
| 10 | `mergeStateStatus == UNKNOWN` | `pending:merge-state` | wait; past the deadline, `ready-awaiting-merge` |
| 11 | `BLOCKED`, `BEHIND`, `UNSTABLE`, `HAS_HOOKS`, or `reviewDecision` is `REVIEW_REQUIRED` or `CHANGES_REQUESTED` | `awaiting:merge-state:<S>[:review=<decision>]` | `ready-awaiting-merge` |
| 12 | the base's effective requirements, read from the branch's `protected` flag (`repos/<repo>/branches/<base>`) and its active rules (`repos/<repo>/rules/branches/<base>`), both visible to read access, include neither a non-empty set of required status checks nor a required approving review; an unreadable read counts as unprotected | `awaiting:base-unprotected` | `ready-awaiting-merge` |
| 13 | the rules require a review and `reviewDecision` isn't `APPROVED` | `awaiting:review` | `ready-awaiting-merge` |
| 14 | the PR changes `.github/workflows/`, `.github/actions/`, or a CODEOWNERS file and `reviewDecision` isn't `APPROVED` | `awaiting:workflow-change` | `ready-awaiting-merge` |
| 15 | requested, no allowed method readable | `awaiting:merge-method-unresolved` | `ready-awaiting-merge` |
| 16 | `CLEAN`, requested | `mergeable:<method>:<headRefOid>` | run `merge-exec.sh` |
| 17 | after 16, confirm read `MERGED` | `merged` | `merged` |
| 18 | after 16, merge call failed, or the fresh verdict `merge-exec.sh` computes differs | `not-merged:merge-call-failed` | `ready-awaiting-merge` |
| 19 | after 16, not `MERGED` within 20 s | `not-merged:merge-not-observed` | `ready-awaiting-merge`; the report says the PR may still be queued |

Rows 12 to 14 check the requirements themselves rather than trusting
`mergeStateStatus`, so a token that could bypass protection (an administrator
where admins aren't enforced, or a ruleset bypass actor) still can't merge
anything the rules wouldn't let an ordinary contributor merge.

A persistent `gh` read failure is `error:execute:status-read`. Method: the
single allowed one; squash when several are allowed including squash;
otherwise `--merge`. The merge call is fixed text:
`gh pr merge <pr> --repo <repo> --<method> --match-head-commit <sha>`.
`merge-exec.sh` never trusts a stored verdict, which the agent's shell could
write: it recomputes the verdict immediately before the merge call (Script
interfaces above), and validates the PR number (`^[1-9][0-9]*$`), method, sha,
and repository against closed patterns.

**Merge intent per invocation.** Merging needs two things: the session's
`MERGE` template variable and a `merge_requested` context value `/execute`
writes at the start of every invocation from that invocation's own flags,
defaulting to false. `MERGE` is set at `koto init` from `--merge` and, being
`rebind: true`, is re-applied from this invocation's flags whenever a live
session is attached, so it's never agent evidence and never inherited from an
earlier run. `merge_requested` is the one agent-written merge value, and it
can only narrow `MERGE`. `record-merge-verdict.sh` computes the AND in code,
so a session resumed without `--merge` doesn't merge and one resumed with it
does (R17).

**Expected-head record.** Row 8 compares the PR head with the commit
`/execute` expects, recorded durably by the push itself, never by the agent:

- Single-pr: `run-cascade.sh --push` and `push-and-record.sh` record
  `git rev-parse HEAD` in the koto session's context after a successful push
  (the session is retained across a resume). `plan_completion`'s
  `expected_head_recorded` gate makes a missing record visible.
- Coordinated node PRs: `node-push.sh` pushes and writes a `head=<sha>`
  field on the node's line in the coordination PR's index, validating the
  new body before editing it, so a resume in any working copy reads it back.
- The coordination PR: the head `/execute` pushes when it runs the
  finalization cascade on the coordination branch, recorded the same way.
- A PR `/execute` adopted but never pushed to has no record, so row 8 fires
  and the run ends `ready-awaiting-merge` naming `head-moved`; `/execute`
  pushes the finalization commit before evaluating, so this only happens when
  something outside the run moved the branch.

**PR ownership.** Every lookup by head branch (the home PR, node PRs, the
publish `--verify` check, `owned-pr.sh` in `/scope` and in `/deliver`'s
probes) and every PR number read from the coordination PR's index keeps only
PRs whose head is in the same repository (`isCrossRepository` false), whose
author is the authenticated user, whose base is the expected branch, and, for
index entries, whose head branch is the one the node's id determines. Zero or
several matches after that filter is an error (`execute:pr-adopt`,
`scope:pr-create`, or `deliver:child-outcome`), never a pick. `/execute` fixes
the set of repositories it may write to when it starts and rejects PR-index or
`_Repo:` entries outside it.

**Outcome versus exit.** Encoded on `/execute`'s template edges through
`context_assignments` and carried by the terminal results:

| Stop point | `exit:` | `outcome=` |
|------------|---------|------------|
| `merged` terminal | `full-run` | `merged` |
| `ready_awaiting_merge` terminal (or legacy `done`) | `full-run` | `ready-awaiting-merge` |
| `paused_for_review` | unset (suspension) | `paused-for-review` |
| `done_blocked` via DIRTY | `abandonment-forced` | `ready-awaiting-merge` |
| `done_blocked` via a verdict error or any other blocker | `abandonment-forced` | `error` with the step |
| `re-evaluation` | `re-evaluation` | `error`, `execute:re-evaluation` |
| coordinated, coordination PR merged | `full-run` | `merged` |
| coordinated, nothing left to start, something unmerged | `full-run` | `ready-awaiting-merge` |
| coordinated, a node waits on an unmerged predecessor | unset (`paused_awaiting_merges: true`) | `paused-awaiting-merges` |

**`/scope` resume routing.** `resume-probe.sh`'s exit codes and the states
`resume_route` sends them to:

| Exit | Ladder row | Target |
|------|------------|--------|
| 10, 11 | nothing on disk (on a topic branch or not) | `setup` |
| 12 | `/explore` handoff | `setup` (recorded there, consumed in discovery) |
| 20/21/22 | fresh state file, no session, pointer at phase 1/2/3 | `discovery` / `hop_select` / `finalize` |
| 24 | stale state file (7 days or more) | `resume_stale` (`--auto` takes Resume, announced) |
| 25 | malformed state file | `resume_malformed` |
| 26 | exit set, no publish pending | `resume_exit_set` |
| 27/28/29 | exit set, `publish_error:` recorded, intent set | `publish_full_run` / `publish_re_evaluation` / `publish_abandonment` |
| 40 | a PLAN exists (Active or Draft), intent set | `republish` |
| 41 | PLAN Active, no intent | `done_refused` (`plan-active`, `next=` by mode) |
| 42 | PLAN Done | `done_refused` (`plan-done`, `next=/release <topic>`) |
| 43/46/48/50 | a draft artifact | `resume_draft` |
| 44 | executed: PLAN absent, DESIGN under `current/`, intent set | `executed_report` |
| 45/47 | a settled boundary (or an executed topic with no intent) | `resume_boundary` |
| 49 | BRIEF Accepted | `setup` |
| 60-63 | a plan, design, PRD, or brief partial | `setup`, then `hop_select` routes to that hop |
| 2 | cannot tell | `done_error` (`scope:resume-probe`) |

### Data Flow

1. **`/deliver` opens.** `deliver-open.sh` starts a fresh `deliver-<topic>`
   session. `preflight` refuses a private repository, and `open_request`
   abandons earlier requests and creates `REQ`.
2. **`/scope` entry.** The Skill call carries `--koto-leg=REQ:scope`.
   `scope-open.sh` passes the raw tokens to `koto init`, which validates
   them, creates or attaches `scope-<topic>`, and binds it to the leg, or
   records a refusal there. `intake` resolves `RUN_INTENT` and writes
   `intent:` to the state file.
3. **The `/plan` hop.** It receives the forwarded flags. `/plan` records
   `split_branch`, `split_rationale`, `execution_mode`, and
   `split_mode_source` in the PLAN. For a coordinated PLAN it also files the
   issues with Repo and Group rows. `plan_mode_consistent` checks the result.
4. **Exit and publish.** `/scope` records the exit, then, on intent runs:
   - untracks its own topic `wip/`;
   - pushes;
   - reuses or creates one PR;
   - verifies it through the `published` gate;
   - cleans up, reaches a terminal, and koto promotes its result to the leg.
5. **`/deliver` hand-off.** `scope_run` routes on the leg. `scoped_check`
   re-verifies the PLAN and the owned PR, and `mode_route` reads the PLAN's
   `execution_mode`.
6. **`/execute`.** Entered with `--koto-leg=REQ:execute`, it adopts the PR by
   head branch through the ownership filter. Each merge decision reads live
   GitHub state through `merge-verdict.sh`, recorded by a default action;
   `merge-exec.sh` recomputes it before merging. The CI deadline and the
   no-checks grace window are anchored on the head commit's `committedDate`
   from the same PR snapshot, so the scripts keep no bookkeeping and a
   resumed run measures the same deadline. Its terminal result is promoted to
   the execute leg.
7. **`/deliver` closes.** `merged_check` re-reads GitHub on a `merged`
   result, and `deliver-report.sh` prints the terminal result.
8. **Coordinated resume.** Resume state lives on the coordination PR (its PR
   index and merge-order block) and in the node branches' PRs.

### `/deliver` template states

`deliver.md` always enters through `/scope`, which owns every "where did this
topic stop" question through `resume_route`. No state pushes, merges, or
writes to GitHub as a default action; the default actions touch only koto's
request store, and every read is a gate.

| State | Kind | Gate | Transitions |
|-------|------|------|-------------|
| `preflight` | gate-only | `deliver-preflight.sh` (R29) | Public goes to `open_request`; private or unknown goes to `done_refused` (`private-repo`) |
| `open_request` | default action (koto request store only; safe to re-run) | `deliver-open-request.sh` abandons open requests for this coordinator, creates `REQ` with legs `scope` and `execute` | `scope_run` |
| `scope_run` | agent-run: `Skill /scope <topic> --intent=continue --<mode> --koto-leg=REQ:scope` plus forwarded flags | `scope_leg`: `request-leg` on `scope`, with the scope outcome set as `expect` | An open leg waits. Promoted and valid: `scoped` or `handed-off-multi-pr` go to `scoped_check`; `executed` to `executed_check`; `re-evaluation`, `abandonment`, `cancelled` to `done_stopped` (`scope-ended-early`); `error` to `done_error` with the step. Refused with `intent-mismatch` or `var-mismatch:INTENT` goes to `done_error` (`deliver:intent-mismatch`); other refusals to `done_error` (`scope:refused`). Invalid goes to `deliver:child-outcome`; explicit to `deliver:child-absent`. Evidence `child_returned: yes` on an open, unbound leg goes to `scope_absent` |
| `scope_absent` | default action: resolve the `scope` leg with the fixed `{outcome: error, step: deliver:child-absent}` | none | back to `scope_run`; if the leg was bound meanwhile, the resolve is refused and `scope_run` keeps waiting |
| `scoped_check` | gate-only | `deliver-probe.sh scoped`: PLAN tracked and unchanged at HEAD, and `publish-scoping-pr.sh --verify --expect-intent continue` | pass goes to `mode_route`; fail to `done_error` (`deliver:child-outcome`) |
| `mode_route` | gate-only | `plan-mode.sh` (0 single-pr, 10 coordinated, 20 multi-pr, 4 invalid) | 0 and 10 go to `confirm`; 20 to `done_stopped` (`handed-off-multi-pr`, `startable` copied from the leg); 4 to `deliver:child-outcome` |
| `confirm` | gate plus agent | `test '<MODE>' = auto` | auto goes to `execute_run`, ignoring stray evidence; otherwise `decision: proceed` goes to `execute_run` and `decision: stop` to `done_stopped` (`scoped`, `next=/deliver <topic>`) |
| `execute_run` | agent-run: `Skill /execute docs/plans/PLAN-<topic>.md --<mode> [--merge] --koto-leg=REQ:execute` | `exec_leg`: `request-leg` on `execute` | Promoted and valid: `merged` goes to `merged_check`; `ready-awaiting-merge` to `done`; the two pauses to `done_stopped`; `error` to `done_error` with the step. Refused goes to `done_error` (`execute:refused`). Invalid, explicit, and absent arms as in `scope_run`, through `execute_absent`. Every arm copies `pr`, `repos`, `resume`, and `waiting` from the leg's exports |
| `executed_check` | gate-only | `deliver-probe.sh executed`: PLAN absent, DESIGN under `current/`, owned PR read through `owned-pr.sh` | merged goes to `done` (`merged`); open to `done` (`ready-awaiting-merge`); anything else to `deliver:child-outcome` |
| `merged_check` | gate-only (non-overridable once K8 ships) | `merge-verdict.sh --confirm` on the owned PR or the coordination PR | `merged` goes to `done`; anything else can only downgrade, to `done` with `ready-awaiting-merge` |
| `done`, `done_stopped`, `done_error` (failure), `done_refused` (failure) | terminal | none | a result with `outcome`, `step`, `reason`, `pr`, `pr_state`, `repos`, `resume`, `waiting`, `next`, `startable`, and `wip_paths`, all assigned on the edges |

Because a topic with a PLAN still passes through `/scope`, a run whose
publish failed after the PLAN was written gets its PR opened on the retry
before `/execute` starts (R17). Because every `/deliver` invocation is a fresh
session with a fresh request, `--merge` and the mode are per invocation, and
every progress step is re-derived from durable state.

## Implementation Approach

The work spans two repositories and ships as a coordinated effort. koto's
changes land first, as their own PRs in `tsukumogami/koto`, and are released.
shirabe then raises its koto floor to that release and lands its phases. The
earlier expectation of a single shirabe PR no longer holds: nothing in
shirabe that uses the new koto features can merge before the release exists
and CI pins it. Within shirabe, the phases stay ordered provider-first, so
none leaves `main` with a half-wired flag if it lands alone, and the choice
between one shirabe PR and several stays with `/plan`'s split step under the
repository's Delivery Preference.

The critical path runs through variable constraints and root attach, then
the init flags, the koto release, shirabe's koto floor, `/scope`, `/deliver`,
and the guides. The `/execute` track runs in parallel once the result map,
`context_assignments`, variable constraints, and the koto floor are in.

### Phase 1: koto features (`tsukumogami/koto`)

| Item | Change | Needs |
|------|--------|-------|
| KA | K2, transition `context_assignments` | none |
| KB | K1, terminal `result:` map, including its `koto status` and `koto next` exposure and export onto leg results | none |
| KC | K3, variable `values:`, `pattern:`, and `rebind:`, plus `koto session rebind` | none |
| KD | K5, `koto request attach` for roots, with the request-lifecycle design amendment | none |
| KE | K4, `koto init --vars-file`, `--replace-terminal`, `--attach-live`, and `--koto-leg` with refusal recording | KC, KD |
| KF | K6, the `request-leg` gate | KB (it reads `exports`, which KA also reads) |
| KR | a release, with shirabe's `koto-version` pin bumped | KA-KF |

K7 (koto#240), K8 (`overridable: false`), K9 (request prune), and K10 (the
`name_filter` fix) are recommended or optional and off the critical path.

Deliverables:

- koto source changes with engine and compile tests
- the custom-skill-authoring guide updated for result maps, assignments,
  constraints, init flags, and the leg gate
- the request-lifecycle design amendment
- the release

### Phase 2: shirabe koto floor

Depends on KR.

- The koto minimum raised in `requires.tsv` for `/scope`, `/execute`, and
  `/deliver`, with preflight naming the minimum when it's older.
- CI's koto pin moved to KR.
- The shared `scripts/koto-open.sh`: args-file transport, `--attach-live`,
  `--replace-terminal`, `--koto-leg`, and rendering koto's errors in today's
  wording, with a `_test.sh`.

### Phase 3: Shared contracts

The references every skill reads.

- `coordination-strategy.md`: repository count, precedence, header definition,
  Branches, merge and pause.
- `parent-skill-state-schema.md`: the `coordinated` enum value, the intent
  field note, and `unset` at the variable level.
- The draft/ready design amendment.
- `parent-skill-pattern.md` (`--koto-leg` and the koto-backed binding) and
  `parent-skill-child-inspection.md` (the leg-result row).
- `koto-session-retention.md` and `default-action-conversion.md`.

Deliverables: the edited reference files. They can land with the code.

### Phase 4: `/plan` emits both multi-PR modes

Depends on Phase 3's precedence and header definition.

- The flags and their rejection rules.
- Step 5a and group rows.
- The coordinated creation branch with filing approval.
- The `plan-to-tasks.sh` node vars and a single-repo test.
- Next-step advice routing (R23).
- The "(multi-repo)" eval assertion updated.

Deliverables:

- `skills/plan/SKILL.md` and phases 3, 4, and 7
- `plan-to-tasks.sh` and its test
- the plan-to-tasks contract doc
- plan evals

### Phase 5a: `/execute` merge step (single-pr)

Depends on Phase 2, Phase 3's draft/ready amendment, and KA, KB, and KC.

- `merge-verdict.sh` and `merge-exec.sh` with table-driven tests.
- The four koto states and terminals, the `ci_monitor` retargets, the
  `failing_unresolvable` mapping, and the regenerated mermaid.
- `record-merge-verdict.sh` as `merge_readiness`'s default action, the
  `context-matches` routing, and the `recheck` hop.
- `push-and-record.sh`, the cascade push record, and the
  `expected_head_recorded` gate.
- `result:` maps on every terminal, `context_assignments` for outcome, step,
  and reason, the `home_pr` and `repos` record states, and `print-exit.sh`.
- `MERGE` and `PLUGIN_ROOT` as `rebind: true`, and `--koto-leg` through
  `koto-open.sh`, with always-root retention.
- The ownership filter at every existing lookup.
- The write-set additions.
- R24 wording, `check-merged-wording.sh`, and `/work-on` wording.

Deliverables:

- `skills/execute/*` (single-pr path), scripts, and template
- `skills/work-on/SKILL.md`
- `scripts/check-merged-wording.sh`
- the execute `gh` shim with a call log and per-scenario fixtures
- execute evals for the Merging criteria, including retention cases that
  assert the result keys

### Phase 5b: `/execute` coordinated path in one repository

Depends on Phase 4's node vars, Phase 5a's scripts, and KA and KB.

- `coordinated-next.sh`, `node-cut.sh`, `node-push.sh`, and
  `coordination-verdict.sh`, each table-tested.
- Per-node branches, worktrees, PR titles and bodies, and the `wip/` sweep.
- The `execute-coordinated.md` envelope with result maps and the same
  `--koto-leg` entry.
- The coordinated merge, pause, and resume loop, with `head=` index fields
  written only by `node-push.sh` and the cascade push.
- The cascade on the coordination branch before it is marked ready.
- The Rust single-repo tests and the `lifecycle.yml` self-reference filter.

Deliverables:

- `skills/execute/SKILL.md` coordinated section, the envelope template, and
  its mermaid
- validator tests and `lifecycle.yml`
- coordinated execute evals

### Phase 6: `/scope` intent, intake, resume, and publish

Depends on Phase 2, Phase 4 (forwarding targets real flags), Phase 3
(schema), and KA, KB, KC, and KE.

- The constrained variables, Phase 0 reduced to tokenizing and
  `scope-open.sh`, and `--koto-leg`.
- `intake` with `resolve-intent.sh`, `check-upstream.sh`, and
  `check-recorded-intent.sh`.
- `resume_route` with `resume-probe.sh` and the prompt states.
- Hop forwarding, `check-plan-mode.sh`, and the `plan_mode_consistent` gate.
- Coordination-intent precedence.
- Publish states and `publish-scoping-pr.sh`, failing to `done_error`.
- `republish`, `republish_record`, `executed_report`, `record-scope-exit.sh`,
  and `owned-pr.sh`.
- `startable-issues.sh`.
- The terminals with results, and the exit summary through
  `print-scope-exit.sh`.
- Retention on every tick.
- The resume redirect and status table (R23, R25).
- State-schema fields.
- Security Considerations and its restatements.
- `requires.tsv`.

Deliverables:

- `skills/scope/*`, templates, the regenerated mermaid, and scripts
- scope evals, including the "no `gh` call on a no-intent run" assertion,
  R1 refusals with koto's exit 2 and today's wording, and both mismatch cases

### Phase 7: `/deliver`

Depends on Phases 5a, 5b, and 6, and on KD, KE, KF, and KR.

Deliverables:

- `skills/deliver/SKILL.md`, `koto-templates/deliver.md` and its mermaid,
  scripts, `requires.tsv`, `evals/`, and fixtures
- `scripts/plan-mode.sh`
- `README.md` row
- `docs/guides/coordinated-multi-repo.md`: a single-repo section, the intent
  route into coordinated mode, and `/execute` (not `/work-on`) as its driver
- `docs/guides/execute-friction.md`: a section on `/deliver`, `/scope
  --intent`, and `/execute --merge`, replacing the advice that assumes
  `/scope` leaves an open PR, plus `/deliver`'s resume model (a request per
  run), `--koto-leg`, and the koto floor

### Eval coverage

Each phase ships its own eval scenarios, naming the requirement IDs they
cover, so the "every R1-R25 covered, 3 of 3 runs" criterion (R26) can be
checked phase by phase:

- GitHub state comes from the per-skill `gh` shims.
- Forced-split fixtures carry a hard constraint in the DESIGN; no-split
  fixtures are designs too small to split.
- `/deliver`'s scenarios run a real koto and cover the stale-run fence (an
  old request with a live mid-hop `/scope` session is abandoned and the
  session re-pointed and resumed, with no second `scope-*` session), a late
  result from a superseded run being refused, a live `intent=stop` run
  refused as `deliver:intent-mismatch` with the working tree unchanged, the
  republish and executed shortcuts, a publish failure and its retry, a
  `/scope` that returns without attaching, a forced override on the leg gate
  that can't reach `scoped_check`, and a `merged` result that the confirm
  read downgrades.
- `/execute` resumed with `--merge` after an interrupted run without it
  merges; the reverse doesn't.

## Security Considerations

This design gives an agent new powers on the operator's GitHub credentials.
On intent runs, `/scope` pushes and opens a PR. `/execute` opens one PR per
coordinated node and readies it. `/execute --merge`, on by default under
`/deliver`, merges to the default branch. Until now the human merge was the
last review gate. The rules below keep the agent's merge from becoming a way
around review. They also keep it off PRs it doesn't own, and keep material
off remotes it shouldn't reach.

**The repository gates the merge, and the repository must have a gate.**
`merge-verdict.sh` returns a mergeable verdict only when all of these hold:

- the PR is open and not draft;
- its merge state is `CLEAN`;
- every reported check succeeded, and at least one check reported;
- the review decision is neither `REVIEW_REQUIRED` nor `CHANGES_REQUESTED`;
- its head commit equals the commit the run itself pushed.

If the base branch requires neither status checks nor reviews, the verdict is
`awaiting:base-unprotected`. A clean merge state on an unprotected branch
proves nothing, so v1 has no override. The agent never approves a PR:
`gh pr review` is outside every write set. GitHub doesn't let the operator
approve their own PR, so where review is required a human still decides.
A repository whose default branch is a distribution channel (plugins, skills,
recipes) should require an approving review before `--merge` is used there.

**One merge call site, fixed text, checked against its own verdict.**
`merge-exec.sh` is the only place `gh pr merge` appears, and a shell test
enforces that by grep. The call is
`gh pr merge <pr> --repo <repo> --<method> --match-head-commit <sha>` with no
`--admin`, no `--auto`, and no pass-through flags. The script recomputes the
verdict itself immediately before merging rather than trusting a stored one,
and validates every value against a closed pattern. `--match-head-commit` closes
the window between verdict and merge. `merged` is reported only after a live
read says `MERGED`. A merge queue that accepts a PR without merging it is
reported as `merge-not-observed`, and the report says the PR may still merge
later.

**Merge intent is per invocation, and only owned PRs are touched.** Both
mechanisms are specified under Key Interfaces. A resumed session never
inherits an earlier run's merge setting: `MERGE` is rebound from each
invocation's flags, and merge intent never comes from agent evidence. A fork
PR named after a predictable `impl/<slug>-<node-id>` branch can't be adopted,
edited, readied, closed, or merged, because every head-branch lookup filters
on same repository, the authenticated author, and the expected base, and
treats zero or several matches as an error.

**No default action writes to GitHub.** The verdict, the expected head, and
`/scope`'s exit record are written by scripts, not the agent, but none of
those scripts pushes, opens a PR, or merges. `merge_attempt`, `republish`,
and the publish states stay agent-run. `/deliver`'s default actions touch only
koto's local request store.

**Pushes never touch the default branch and never force.** The publish script
and every node push refuse a detached HEAD or the remote's default branch.
They push with an explicit `HEAD:refs/heads/<branch>` refspec and never pass
a force option. Branch names are built only from the validated topic slug and
node id.

**Published content is bounded.** PR bodies come from a fixed template over
validated fields and are passed with `--body-file`. The fields are the slug,
exit, outcome, intent, mode, `docs/` artifact paths, and issue numbers.
Free-text state fields are left out. The coordination PR's rule against
embedding private-repository content applies to every PR these skills open.
Pushing a branch publishes its whole history. In this workspace, `wip/`
artifacts are committed to feature branches by design, and they fall under
the same public-content rules as the documents they feed. So the publish
script lists any `wip/` paths in unpushed history on a `wip_paths=` exit line
rather than blocking. The check that matters in this workspace,
private-repository content in research notes, runs as the public-content
visibility check over those files, and a hit stops the push with
`scope:push`.

**Inputs from GitHub and from files are data.** Parents parse `gh` JSON for
enumerated fields only, and never read child PR bodies, CI logs, or comments.
Issue titles printed as startable issues are opaque data. `/deliver` parses
no printed line: it reads leg results only through the `request-leg` gate,
checked against a closed `expect` set. User tokens never pass through a
shell: each skill writes them to an args file and koto reads them through
`--vars-file`. `--upstream` must match a repository-relative `docs/` path
pattern and `--max-rounds` a bounded integer, both enforced by koto at init
before any gate command sees them. `EXECUTE_CI_WAIT_LIMIT_SECS` must be a
bounded integer, or the default applies. The existing slug and enum
re-validation rules apply unchanged.

**The koto request store is local state, and it grows.** Requests live under
`~/.koto/requests/`. The store is unix only and isn't replicated under koto's
cloud backend, so a `/deliver` run is a single-machine flow. Records hold
topic slugs, leg inputs, and results (outcome tokens, step names, PR URLs),
never credentials, and they accumulate until koto ships a prune verb (K9).
Progress never rests on a request record alone: every forward step re-checks
the PLAN, the owned PR, or GitHub.

**Leg attach and refusal are koto's, not the agent's.** Attach refuses a
terminal session, checks the leg's inputs against the session's non-rebind
variables, and re-points a session only away from an abandoned leg or a
closed request, so one run can't take over another live run's leg. Admitting
root sessions carves an exception into koto's epoch fence, argued in koto's
request-lifecycle design: roots are never redelegated, and their results
arrive only by promotion. koto records every argument and attach refusal on
the leg itself. The only result `/deliver` writes is the absent record, a
fixed JSON value that can reach only an error arm, and koto rejects it if the
child bound in the meantime.

**Gate overrides are logged and can't manufacture progress.** koto today lets
`koto overrides record` force any gate, and it logs the override. The
`request-leg` gate's override default is an explicit, invalid result, so a
forced leg gate reaches only an error. A false `merged` would need two logged
overrides, one on `/execute`'s `merge_confirm` and one on `/deliver`'s
`merged_check`, which re-reads GitHub. K8 (recommended) makes `merged_check`,
`scoped_check`, and `merge_confirm` refuse overrides; until it ships, the
design claims no more than a logged override.

**Two drivers on one topic.** If an agent from an older `/deliver` keeps
ticking a child session after a newer run re-points it, nothing detects it:
koto can't know whether an agent is alive. Abandoning the old request gives
that agent koto's stop notice before the re-point. The merge protections
above hold either way, since a merge still needs a fresh verdict at a head
commit the run itself recorded.

**Unattended runs are bounded.** `/deliver --auto` asks nothing and merges by
default. With the gates above, an unattended run can merge only where the
repository's own rules would let an ordinary contributor merge. Its final
report (R18) names every PR it merged or left waiting and every repository in
the run's write set, and relays `/scope`'s list of `wip/` paths published with
the branch.

**PRs that change their own gate.** On a base that requires checks but no
review, a PR could edit the workflows that produce those checks. The verdict
refuses to merge a PR touching `.github/workflows/`, `.github/actions/`, or a
CODEOWNERS file unless a review approved it.

**Residual risk.** These are skill-level controls around an agent that has a
shell and the operator's token. A token that can bypass protection (an
administrator where admins aren't enforced, or a ruleset bypass actor) could
merge through the API directly. The skills never do: the verdict checks the
rules' requirements itself instead of trusting GitHub's merge state, and the
merge call carries no bypass option. Repository-side controls (enforced
protection for admins, required reviews, and push protection for secrets) are
what an agent can't get past, and the skills refuse to merge where the first
two are absent.

## Consequences

### Positive

- One launch command can take a feature from scoping to merged code wherever
  the session may merge, and ends in a named, resumable state everywhere else.
- `coordinated` becomes reachable at all (today nothing emits it), including
  from `/scope --coordinated`, and works in one repository.
- Merging is impossible to over-claim: the `merged` outcome requires a live
  GitHub read (twice under `/deliver`), the merge call is fixed text with no
  bypass flags, and an invocation without `--merge` can't merge.
- Every `/scope` path ends in a koto record: a promoted terminal, a
  koto-refused leg, or `/deliver`'s absent record. Outcome mapping lives on
  template edges that engine-backed tests walk, not in prose.
- The 60 `context_assignments` blocks koto silently dropped start working,
  including the `failure_reason` writes koto's batch view reads.
- `/scope`'s retained-terminal bug is fixed: a re-run on a finished topic
  gets a fresh session that walks the resume ladder instead of ticking a dead
  one.
- Direct `/execute` users resume with `--merge` correctly, because `MERGE`
  is rebound per invocation.
- CI waiting gets a real, testable limit, and `ci_monitor`'s ungated
  `failing_fixed -> done` shortcut is closed.
- The next-step advice and "merged" wording become accurate, and Phase 3's
  promised PR body becomes real on intent runs.
- The parent-of-the-parent slot gets a concrete koto binding. A future driver
  can nest `/deliver` by attaching it to a leg the same way.

### Negative

- Every `/scope` and `/execute` run, including a plain no-intent `/scope`,
  now needs a koto at or above the new floor. That's the one exception to D2.
- Delivery is coupled across repositories: shirabe can't ship until a koto
  release carries six features, and koto's request-lifecycle reasoning
  carries a root exception.
- `scope.md` grows by about 12 states, and `/execute`'s template grows by
  four states, two terminals, and record states, plus a coordinated envelope
  template.
- `/scope` gains its first push and non-hop commit, and `/plan` gains three
  flags and a third creation branch with an approval step multi-pr doesn't
  have.
- Request records accumulate under `~/.koto/requests/` until a prune verb
  ships, and `/deliver` is a single-machine flow.
- `/deliver` makes read-only `gh` calls through its probes, and one of its
  arms still takes agent evidence (`child_returned`), though it can only
  lead to an error.
- `outcome=` and `exit:` aren't one-to-one (a DIRTY PR is
  `abandonment-forced` with `outcome=ready-awaiting-merge`).
- A single-pr run that ends `ready-awaiting-merge` can't be re-merged by
  `/execute` later, because the cascade has already deleted the PLAN.
- Merge-queue repositories report `ready-awaiting-merge merge-not-observed`
  rather than `merged`.
- Tracked `wip/` left on a branch by an upstream workflow still reaches a
  ready `multi-pr` PR and fails its CI.

### Mitigations

- Preflight names the koto minimum when an older koto is installed, and
  `scope-open.sh` renders koto's errors in today's wording, so the floor is
  the only visible change to a plain `/scope`. A no-intent run still makes no
  `gh` call, which an eval asserts through the shim's call log.
- koto lands and releases first, with its own tests. If the leg gate slips,
  `deliver.md` routes through a command gate over `koto request get`. If the
  root carve-out is rejected, both children fall back to `--parent` children
  with a parent-side fence.
- The new states and scripts are covered by table-driven shell tests and
  mermaid regeneration; `resume-probe_test.sh` covers every ladder row and
  the first-match order. The pinned DIRTY route is untouched, and the two
  retargeted `ci_monitor` edges only add a verdict step before a terminal, so
  existing evals hold apart from R24 wording and deliberate exit-summary
  changes.
- K9 (request prune) is recommended to koto, and progress never depends on
  an old request record.
- The coordinated approval step is documented as existing only to satisfy
  interactive filing approval without changing no-intent multi-pr runs.
- The outcome-to-exit mapping lives on template edges and in one table in
  `/execute`'s SKILL.md.
- `/scope`'s `executed_report` lets `/deliver` report a single-pr PR's state;
  a future PR-number input mode for `/execute` is the path to re-merging it.
- `merge-not-observed` is a safe under-claim, named in the report so the
  author knows to check the queue.
- `publish-scoping-pr.sh` names any foreign tracked `wip/` path in its report,
  so the author sees why the PR's CI will fail.
- Evals pin every exit line and every result key `/deliver` routes on.
