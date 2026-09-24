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

The existing PLAN still describes the previous `/deliver`, a stateless
SKILL.md that parsed its children's printed lines. It is being rebuilt as a
coordinated effort across koto and shirabe, and nobody should run `/execute`
on the current PLAN file. This design makes `/deliver` a koto workflow and
has `/scope` and `/execute` report their outcomes to it through koto, which
takes seven required koto features (Decisions 4 and 6).

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

The PRD resolves the product questions; this design settles how each group
of requirements is met inside the existing skills:

- **Intent (R1-R3):** `/scope` takes `--intent`, and no intent is today's
  behavior.
- **Split resolution (R4-R8):** `/plan` resolves a split's mode by
  precedence, including coordinated in one repository.
- **`/scope` exit (R9-R13):** intent runs push and open one PR, and `/scope`
  never invokes `/execute`.
- **The driver (R14-R18, R29):** `/deliver` sequences `/scope` then
  `/execute` and ends in a named final state.
- **Merging (R19-R22):** `/execute --merge` merges only what the
  repository's own rules allow.
- **Truthful routing (R23-R25):** next-step advice, "merged" wording, and the
  state schema match what the skills do.
- **Verification (R26-R28):** eval coverage through the `gh` shim, and
  declared write targets.
- **koto enforcement (R30-R32):** `/deliver`'s sequencing and outcome mapping
  live in a koto workflow, every `/scope` and `/execute` run ends in a
  result-declaring terminal, and the koto features ship in a release first.

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
  prose; where koto lacks the feature, extend koto (R30, R32).

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
`split_mode_source: flag|intent|header|default`. When the work doesn't
split, `split_mode_source` is `none`, the value `resolve-split-mode.sh`
prints for a no-split outcome. Because the split question is
answered before intent is consulted, the split reason can't vary with intent
(R4). `/scope` forwards its own `--intent`, the coordination flags exactly as
the caller passed them (never a header-derived `--coordinated`, which would
outrank `--intent`), and `--auto` when intent is set. A no-intent hop sends
the same argument string as today (D2). A coordinated PLAN follows the
resolved tracking level the way `multi-pr` does, defaulting to `none`: its
work items are outlines with local IDs, each carrying `**Repo**:` and
`**Group**:` fields, and nothing is filed (R7). Only when the repository's
tracking level asks for issues does the new coordinated branch in `/plan`'s
creation phase file them through `create-issues-batch.sh`, behind an explicit
filing approval that asks interactively and resolves by the decision
protocol under `--auto`.

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
every work item of a coordinated split, an outline by default or an issue when
the tracking level files them (R7), with the current repository and a
per-unit group slug. `plan-to-tasks.sh` adds `REPO`, `PR_GROUP`, and `ISSUES`
(outline IDs or issue numbers) to each node entry so `/execute` doesn't
re-parse the PLAN. `/execute` cuts
`impl/<slug>-<node-id>` from the default branch in its own worktree for each
unblocked node, dispatches the node's work items to `work-on.md` with that branch
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

Single-pr gains `merge_readiness -> merge_route -> merge_attempt ->
merge_confirm` with two new terminals, `merged` and `ready_awaiting_merge`.
`merge_readiness` runs `merge-verdict.sh`, which reads one snapshot, applies
the decision table in Solution Architecture, owns the CI deadline, and writes
a verdict to koto context. `merge_route` routes on that verdict.
`merge_attempt` is agent-run (never a default action) and runs
`merge-exec.sh`, the only `gh pr merge` call site in the repository, which
recomputes the verdict itself (Key Interfaces). `merge_confirm` re-reads
the PR and reaches `merged` only if GitHub reports `MERGED`; every route into
`merged` passes it. Merge intent is the template variable `MERGE`, set from
each invocation's own `--merge`, never agent evidence, so an invocation
without `--merge` can't merge. `merge_attempt` re-checks it with a
non-overridable `test "{{MERGE}}" = true` gate, so a run stopped at
`merge_attempt` and resumed without `--merge` ends
`ready-awaiting-merge` (`merge-not-requested`) instead of merging on an
earlier invocation's verdict. `ci_monitor`'s gates and DIRTY route stay
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
  terminals declare no result. A workflow result today is `{status, summary,
  payload}`, with `payload` built from the terminal state's evidence.
- **A leg declaration is `{role, template, inputs}`.** The template names
  what the leg expects to run, but binding doesn't check it today.
- **Overrides aren't bounded by the gate.** `koto overrides record
  --with-data` replaces a gate's override default and isn't checked against
  the gate's output schema, so one override can drive any arm.

On the shirabe side, not every `/scope` path opens a session. Its refusals
happen before `koto init`, and its planned `--intent` shortcuts (PLAN exists:
re-publish; PLAN executed: report the PR) open none. `/scope` also retains its
terminal session but never checks `is_terminal` on reattach, so a re-run
ticks a finished session into nothing.

Key assumptions:

- koto ships the required changes K1-K6 and K8 (Solution Architecture > koto
  changes) in one release before shirabe's dependent changes merge, and
  shirabe raises its koto floor for `/scope`, `/execute`, and `/deliver`
  (R32). If the leg gate (K6) slips, each `*_run` state instead gets a
  default action that runs a small script over `koto request get` and
  captures its output into context, and the arms route on those context
  keys. A command gate wouldn't do: it yields only an exit code, so the arms
  that copy the leg's values couldn't work. The fallback is weaker on D9.
- koto's maintainers accept admitting root sessions to a leg. koto's
  request-lifecycle design gets an amendment: roots are never redelegated and
  their results arrive only by promotion, so the fenced verbs (`progress`,
  `resolve`, leg-scoped `abandon`) are refused outright on a self-attached
  leg rather than fenced at a known epoch. If the carve-out is rejected, the
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
and creates one request with two legs, `scope` and `execute`, each declaring
its role and the template it accepts. The children join through a flag each
owns and documents for use with any koto coordinator,
`--koto-leg=<request-id>:<leg>` (D1), and report through a declared
`result:` map on every terminal, which koto writes into the result's
`payload` and promotes to the leg (K1, R31). `/deliver` reads each leg
through a `request-leg` gate (K6) and routes on the child's `outcome`. It
never parses a printed line (R30).

Every `/scope` path reaches a koto record, and the agent composes none of
them. Static argument checks run inside `koto init` over constrained
variables (K3, K4), so a repeated or invalid `--intent` is a koto refusal
with exit 2, no session, and no state file (R1), recorded on the leg under
`--koto-leg`. The caller can pass only `continue` or `stop`. The flag
reaches koto as its own variable, `INTENT_FLAG` (pattern
`^(continue|stop)?$`, default empty), which `scope-open.sh` passes through
unmodified and leaves out when the flag is missing, so koto itself refuses
`--intent=none`, `--intent=unset`, or any other token, with the same
wording as any other invalid value, and records that refusal on the leg. No caller sets the
effective intent directly: `intake` derives it. Attach-time checks run inside koto too: `--attach-live` refuses
a session from another template, worktree, or store, and a differing
non-rebind variable, so `--intent=continue` against a live `intent=stop` run
is `var-mismatch:INTENT_FLAG` with the session untouched. `--replace-terminal`
gives a finished topic a fresh session, which fixes the retained-terminal
bug (R31). Checks that need the working tree run in two new template
states, `intake` and `resume_route`, and every outcome is a terminal with a
result.

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
`merged_check` and `executed_check` find the PR themselves through the
ownership filter; neither trusts a `pr` value from a leg. Two cases can't
produce a koto record: a `--koto-leg` naming no open leg, and a `/scope` too
old to know the flag. The agent reports that the Skill returned, and
`/deliver` resolves the still-open leg as `deliver:child-absent`, an arm that
can only reach an error.

#### Alternatives Considered

**A stateless SKILL.md that sequences two Skill calls.** `/deliver` would
have no template, would parse the children's exit lines, re-read the PLAN's
mode, and relay the result. Rejected under D9:
sequencing, the confirmation, and outcome mapping would all be prose, and
`merged` would rest on a printed token. The driver also couldn't tell
`/execute`'s review pause from a failed batch, or a CI timeout from an
awaiting merge, without re-implementing `/execute`'s merge rows, because
only `/execute`'s own session holds that difference. Its
enter-through-`/scope` resume model survives inside the chosen option.

**`/scope` inline, `/execute` as a `--parent` child.** `/deliver` is a koto
workflow; `/execute` joins through a `--koto-parent` flag and reports through
a child-state gate, while `/scope` stays a plain call gated on durable files.
Rejected: the asymmetry costs more than it looks. `/scope`'s stop outcomes
would still arrive as agent evidence, and there'd be two observation
mechanisms to document. `/execute` would lose "always a
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
intake.** Rejected. Composed names don't close the stale-child hole (the
koto 0.12.2 measurement above). Two namespaces for one topic would need a
live direct run migrated. Children still couldn't retain `/scope`'s per-hop
record. And intake refusals would open a session, against R1's wording. Its
in-session intake is adopted for the checks that genuinely need a session:
the upstream battery, the recorded intent of an unfinished run, and the
resume ladder.

### Decision 5: Where `/scope` publishes under `--intent`

`/scope`'s koto template runs `finalize -> exit_* -> cleanup_* -> done_*`.
Cleanup deletes the state file, which R12 needs after a failure and which
holds the durable record `/scope`'s exit-finalization phase says belongs in
"the run's pull-request body", a PR that doesn't exist today. `/execute`
adopts a home PR by head branch (`gh pr list --head <branch>`), not by
title. A branch can also carry
tracked `wip/` from an upstream workflow such as `/explore`. A publish can
fail after the PLAN is written, and a later run has to retry it.

Key assumptions:

- koto accepts a transition condition that combines two gates with an
  evidence field; if not, exits always route through the publish state and a
  no-intent run passes straight through it with a `not-requested` value.
- `INTENT_FLAG` is a constrained koto variable (pattern
  `^(continue|stop)?$`) defaulting to empty, and `intake` resolves the
  effective intent, `RUN_INTENT` (`continue|stop|none`), from it and the
  recorded value (Decision 4): `INTENT_FLAG` when non-empty, else the state
  file's `intent:`, else `none`. `scope-open.sh` passes the caller's token
  through unmodified and leaves the variable out when `--intent` wasn't
  given, so `--intent=none` fails koto's constraint like any other invalid
  token. The empty value exists only on the variable and never appears in a
  state file.

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
`executed_report`'s default action reads the owned PR, writes its URL and
state to koto context, and the state ends at `done_executed` with that
`pr` and `pr_state`.

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

**Park a failed publish in the publish state.** The session would hold
there, and re-running `/scope <topic>` would reattach and retry. Rejected:
a parked session leaves a parent waiting on an open leg with no outcome to
print, while the PRD requires `error step=scope:push`. It's the
non-terminal path Decision 4 removes. And the retry needs no live session,
because the state file's `exit:` plus `publish_error:` routes the next
invocation back to the publish state.

### Decision 6: Which prose-carried pieces move into koto

Setting `/deliver` aside, five pieces could live in skill prose or in values
the agent writes: the merge values that routing depends on, the exit-line
outcomes, the `/plan` hop's flag forwarding, the coordinated loop, and
`/scope`'s `--intent` parsing and mismatch refusal. A sixth question is
whether `/plan` itself should get a template. Each was weighed under D9 on
what koto enforcement adds and what it costs.

koto has no working transition-level `context_assignments`: the compiler's
transition type deserializes only `target` and `when`, and nothing rejects
unknown fields. All 58 `context_assignments:` blocks in shirabe's templates
(38 in `work-on.md`, 10 each in `scope.md` and `execute.md`) are silently
dropped, including every `failure_reason` write, which koto's own batch view
reads for failed children.

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

- **Merge values.** The agent writes none of them. Merge intent is the
  session's `MERGE` variable, rebound from each invocation's own `--merge`
  (K3, K4). `merge_readiness` gains a default action running
  `record-merge-verdict.sh`, which clears any earlier `merge_verdict`,
  `home_pr`, `reason`, and `step`, reads `MERGE` and `expected_head`,
  resolves the PR through the owned-PR script (`--state all`) and records it
  as `home_pr`, runs the unchanged `merge-verdict.sh`, and writes the verdict
  line, plus its condition as `reason` or its step as `step`, with
  `koto context add`. `home_pr` is written only by scripts from the owned-PR
  script's output, never from agent evidence. `merge_route` keys on anchored,
  non-overridable `context-matches` gates over that line, and the `pending:`
  loop back to readiness passes through an agent-evidence hop
  (`recheck: waited`) so one tick never revisits a state. `merge_confirm`
  runs the confirm read the same way, as a default action that re-resolves
  the owned PR and records the confirm line as `confirm_verdict`, because
  `merge-verdict.sh --confirm` exits 0 on both outcomes and a command gate
  over it would always pass.
  `expected_head` is written by the push itself: `run-cascade.sh --push` and
  a new `push-and-record.sh` record `git rev-parse HEAD` after a successful
  push, and a gate on `plan_completion` makes a missing record visible.
  Coordinated `head=` fields are written only by `node-push.sh`, which
  validates the new coordination body before editing it.
- **Outcomes.** Every edge into a terminal assigns `outcome` through
  `context_assignments` (K2), and assigns `step` and `reason` there only when
  the edge fixes them as literals. A `step` or `reason` that comes from a
  script's output is written to context by the record script, since an
  assignment can't read `${context.<key>}`. Every terminal declares a
  `result:` map built from those keys (K1). The outcome-versus-exit table moves out
  of SKILL.md prose into template edges, where the engine-backed retention
  tests walk it. Scripts render the printed exit block from the terminal
  result (`print-scope-exit.sh`, `/execute`'s `print-exit.sh`, and
  `deliver-report.sh`); the agent never composes it (R31). The printed lines
  stay the human-facing contract. Parents read the leg.
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
sequencing. `/deliver` opens a fresh session and a fresh request with a
`scope` leg and an `execute` leg, then runs `/scope --intent=continue` on
the first. koto checks `/scope`'s arguments at init and attaches its session
to the leg; `intake` and `resume_route` decide where the topic stopped. On a
fresh topic, `/plan` settles whether the work splits exactly as it does
today and then, only on a split, picks `coordinated` (for one repository or
many) or `multi-pr` by precedence, and a gate checks the result against
what was forwarded. `/scope` publishes one PR between the recorded exit and
cleanup, and ends at a terminal whose result reaches the leg.

`/deliver` routes on that result, re-checks the PLAN and the owned PR, reads
the mode, asks one confirmation when interactive, and runs `/execute` on the
second leg with `--merge` unless `--no-merge`. `/execute` merges through a
script-recorded verdict and one fixed-flag merge script: through four new
states on single-pr, and node by node in merge order on coordinated, with
the coordination PR last. `/deliver` finds the PR itself and re-reads GitHub
before it reports `merged`. Every printed exit block is rendered from a
terminal result.

The decisions meet at these seams:

- **Who opens coordinated node PRs.** `/execute` opens one PR per node on
  its own branch (Decision 2), and Decision 3's merge scripts run on those
  PRs unchanged.
- **Intent mismatch.** A live session with a different recorded intent is
  refused by koto at attach (`var-mismatch:INTENT_FLAG`) when the caller
  passed `--intent`; a bare re-invocation (`INTENT_FLAG` left out, so empty) attaches
  without refusal and runs with the recorded intent. An unfinished run whose
  session is gone is refused by `intake` (`intent-mismatch`). `/deliver` maps
  both to `deliver:intent-mismatch`. A finished run whose PR records
  `intent=stop` isn't a mismatch: the re-run republishes and rewrites the
  PR's `intent=` field.
- **Per-run settings on a shared session.** `/scope`'s `EXEC_MODE` and
  `/execute`'s `PAUSE_BEFORE_FINALIZE` and `MERGE` are `rebind: true`, so a
  run `/deliver` picks up takes this invocation's mode and merge setting
  (R15, R17). Each has a default (`interactive`, `false`, and `false`), so
  an omitted rebind variable resets to a known value. `TOPIC`, `INTENT_FLAG`, `COORDINATION`, `UPSTREAM`, and the PLAN
  path are not rebindable, and a differing value is a mismatch.
- **Finished single-pr topics.** After a single-pr run the cascade deletes the
  PLAN. `/scope`'s `executed_report` state reads the branch's owned PR and
  ends at `done_executed`; `/deliver`'s `executed_check` finds the owned PR
  itself and reports `merged` or `ready-awaiting-merge`. `/deliver` always
  enters through `/scope`, so a publish that failed after the PLAN was
  written is retried before `/execute` runs.
- **Error line spelling.** Every skill prints `outcome=error` followed by
  `step=<step>`. A refusal prints the same way: `outcome=error` with
  `step=scope:refused` or `step=execute:refused`.
- **Result vocabulary.** A child's result `outcome` is a koto-level
  vocabulary that `/deliver` maps; values such as `re-evaluation`,
  `cancelled`, and `refused` aren't printed tokens. `refused` appears only
  as a value in a result payload, never after `outcome=` on a printed line.
- **Script output into context.** A koto command gate exposes only
  `exit_code` and `error`, so no script's printed output reaches context or
  a result through a gate, and a gate over a script whose exit code doesn't
  carry the decision would route wrongly. Any state that needs a script's
  output (the merge verdict and the confirm read in both `/execute`
  templates, the coordinated verdict, `/scope`'s intake checks, the
  executed-topic PR URL and `pr_state`, and the PR each `/deliver` re-check
  verifies) runs the script as a default action that writes context keys
  with `koto context add`, and routes on `context-matches` gates over those
  keys. Those gates are `overridable: false` (K8).
- **Effective intent.** `intent_declared` and `check-plan-mode.sh` key on
  `RUN_INTENT` (`continue|stop|none`), which `intake` derives, not the raw
  `INTENT_FLAG`, which is empty on a bare re-invocation. There is no
  user-settable `INTENT` variable.
- **Coordinated envelope.** Coordinated needs result-declaring terminals
  (Decision 4) without a full coordinated template (Decision 6). The envelope
  is three states around the script-driven loop, and it shares the
  `execute-<topic>` session name with `execute.md`; attach refuses a session
  created from the other template. The envelope has no refused terminal: an
  init-time refusal creates no session, and koto records it on the leg.
- **Delivery shape.** Seven required koto changes make the work a coordinated
  effort across both repositories (Implementation Approach).

The PRD's Final States carry every step this design emits, including
`scope:refused`, `execute:refused`, `deliver:child-absent`,
`deliver:request-abandoned`, and `scope:intake`, and `cancelled` under
`scope-ended-early`. R30 carries the refusal recorded on the leg under
`/deliver`.

## Solution Architecture

### Overview

Four existing skills change, one is added, and koto gains seven required
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

**koto changes** (in `tsukumogami/koto`). K1-K6 and K8 are required and
ship in one release (R32); K7, K9, and K10 are off the critical path. Each
paragraph below is the contract shirabe consumes. The code-level detail
(files, functions, and internal limits) lives in the koto issues.

- **K1. Declared terminal `result:` map (required, R31).** A terminal state
  may declare `result:`, a map of up to 32 keys whose values are literals,
  `{{VAR}}`, or `${context.<key>}`. koto writes the map into the workflow
  result's existing `payload` field; there's no new field. A terminal that
  declares no map keeps today's evidence-derived payload. A missing key
  resolves empty and is listed in `missing`. The payload rides every path a
  result already takes: the request-store result, the leg promotion, the
  parent's child-completed event, the terminal `koto next` response, and
  `koto status` for a retained terminal.
- **K2. Transition `context_assignments` (koto#204, required).** Values are
  literals, `{{VAR}}`, `${evidence.<field>}`, and
  `${gates.<g>.<path>}`, a dot path into a gate's structured output, and
  references may sit inside string literals. Gate paths cover the
  structured gate types such as `request-leg` (so
  `${gates.scope_leg.payload.pr}` works without leg-specific support). A
  command gate's output is only `exit_code` and `error`, so a gate path
  never carries a script's printed output; that reaches context through a
  default action's `koto context add`. Assignments are recorded with the transition event, so a crash
  can't split them. `${evidence.<field>}` must name a declared `accepts`
  field, and an unknown transition field fails compilation instead of being
  dropped. This turns on shirabe's 58 existing assignment blocks, and the W5
  lint credits assignments that write `failure_reason`.
- **K3. Variable constraints and rebinding (required).** Variable
  declarations gain `values:`, `pattern:`, and `rebind: true`, with the
  default validated at compile time. `koto init` refuses with typed errors
  (`invalid_var`, `duplicate_var`, `unknown_var`) that name the variable,
  value, and constraint. A `rebind: true` variable can change only through
  K4's attach; there's no standalone rebind verb.
- **K4. `koto init` entry flags (required).**
  - `--vars-file <path>` takes the variables as a JSON list of pairs, so a
    duplicate survives to be refused. Variable validation runs before the
    name check.
  - `--replace-terminal` replaces only a terminal session and returns its old
    result; a live session is refused.
  - `--attach-live` joins a live session. It refuses a session created from a
    different template, a session whose origin record (worktree and store)
    differs from the caller's, and an explicit non-rebind variable that
    differs from the recorded one (`var_mismatch` names the variable, the
    recorded value, and the requested one).
  - `--koto-leg <req>:<leg>` performs K5's attach in the same step.
  - Attach, leg attach, and rebind are one atomic step: every check,
    including K5's, runs before any `rebind: true` variable is re-applied,
    so a refused invocation changes nothing on the session. A stale
    invocation can't flip `MERGE` on a session another run owns.
  - On any refusal under `--koto-leg`, koto resolves the unbound leg itself
    with `source: refused` and a K1-shaped payload `{outcome: refused,
    reason, var, recorded, requested}`. Exit codes don't change.
- **K5. `koto request attach <req> <leg> --session <s>` (required).** Admits
  root sessions as well as dispatch children. It refuses a terminal session,
  a session whose template isn't one the leg's `template` names (one
  template identity or a short list), and a
  session whose non-rebind variables don't match the leg's declared inputs.
  It's idempotent for the same session, and re-points a session only when
  its current pointer names an abandoned leg or a closed request. The
  leg-bound event records `attach: self` and the session's template
  identity. On a self-attached leg koto refuses the fenced verbs
  (`progress`, `resolve`, and leg-scoped `abandon`) outright. The leg view
  gains `result_source: refused`. koto's request-lifecycle design and the
  `child_not_fenceable` message are amended with this root carve-out.
- **K6. `request-leg` gate type (required, R30).** Fields: `request`, `leg`,
  and an optional `expect: {key: [values]}`. Output: `found`, `disposition`
  (open, resolved, abandoned, missing), `bound`, `source` (promoted,
  explicit, refused), `status`, `final_state`, `template`, `outcome`,
  `step`, `reason`, `valid`, `payload`, and `error`. An open leg is a
  temporal block.
- **K7. Retention separate from result emission (koto#240, recommended).**
  It serves `/work-on`'s batch children, which stay `--parent` children, and
  would retire their role routing.
- **K8. `overridable: false` on gates (required).** `koto overrides record`
  is refused on a gate so marked, with or without `--with-data`. shirabe
  marks the two leg gates (`scope_leg`, `exec_leg`), the `context-matches`
  gates that route the durable re-checks (`scoped_check`, `executed_check`,
  `merged_check`), `/execute`'s `merge_route` and `merge_confirm` gates and
  `merge_attempt`'s `MERGE` gate, and the `context-matches` gates on
  `coord_verdict`, `coord_merge_confirm`, and `/scope`'s `intake` and
  `executed_report`, the states whose default action writes a script's
  output to context.
- **K9. Request prune (recommended).** Listing by coordinator exists; prune
  doesn't.
- **K10. The `children-complete` `name_filter` fix for cleaned-up
  non-composed children (optional).** Independent, and not used here.

**Shared references.**

- `references/coordination-strategy.md`: "one or more repositories", the
  four-level mode precedence, the single definition of which
  `## PR Grouping Policy:` / `## Reviewability Ceiling:` values mean
  coordinated by default (pinned to what `/scope` Phase 0 resolves today), a
  Branches paragraph (one branch per PR node, cut from the default branch),
  the merge step and `paused-awaiting-merges` pause, and the template
  blockquote without "multi-repo" after the unchanged prefix.
- `references/parent-skill-state-schema.md`: `plan_execution_mode` gains
  `coordinated`; a parent may declare an always-present invocation-intent
  field; the state file's `intent:` records `continue|stop|none`, and the
  empty value exists only on the `INTENT_FLAG` variable and never appears
  in a state file.
- `docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md`: an
  "Opt-in agent merge" paragraph, and the coordination-PR exception amended
  so `/execute` marks it ready once every indexed PR has merged.
- `references/parent-skill-pattern.md`: `--koto-leg` as the pattern-level
  child flag, and a "Parent-of-the-Parent Binding" subsection (a template, a
  request per run, children as leg-attached roots).
- `references/parent-skill-child-inspection.md`: a leg-attached child's
  observable surface is its leg's promoted payload, read only through the
  `request-leg` gate.
- `references/koto-session-retention.md`: `/scope` retains on every tick, a
  leg-attached root reports by promotion, and `--replace-terminal` replaces
  the "read, then clean up" recovery.
- `references/default-action-conversion.md`: `merge_readiness`,
  `merge_confirm`, `coord_merge_confirm`, `republish_record`, `intake`,
  `executed_report`, `coord_verdict`, `open_request`, `scope_absent`,
  `execute_absent`, `scoped_check`, `executed_check`, and `merged_check`
  join the converted states, with the rule that a script's output reaches
  context only through a default action's `koto context add`, never through
  a command gate, and routing reads it through non-overridable
  `context-matches` gates.

**`/plan`.**

- `SKILL.md`: the three flags, with rejection of bad or repeated values
  before any `wip/` write; a "Split mode" rule; "Coordinated Mode" without
  "(multi-repo)".
- `phase-3-decomposition.md`: step 5a and the `split_mode_source` field.
  Step 5a calls a deterministic `scripts/resolve-split-mode.sh` (split
  verdict, flags, intent, and CLAUDE.md headers in; `execution_mode` and
  `split_mode_source` out, with `split_mode_source` set to `none` on a
  no-split outcome), so the one decision this feature turns on is
  table-tested, not model judgment. It also runs on `/plan`'s interactive
  override path and on direct roadmap input. On a `coordinated` outcome,
  every work item names its repository and PR group: as `**Repo**:` and
  `**Group**:` fields on its outline when the PLAN is outline-shaped, or as the
  `_Repo: <owner/repo> | Group: <unit-slug>_` row when it carries issues.
- Tracking level for coordinated (R7): `coordinated` joins `multi-pr` on the
  `flag > CLAUDE.md ## Tracking Level: > mode default` stack, with `none` as
  its default, and Phase 7 now always writes `tracking_level` on a coordinated
  PLAN. The outline form is selected only by an explicit
  `tracking_level: none`; a coordinated PLAN with no `tracking_level` field
  (every coordinated PLAN written before this change, including the existing
  eval and `plan-to-tasks_test.sh` fixtures) keeps the issue-table path, so
  the validator and the extractor apply the same rule. The "coordinated is
  always issue-carrying" text is removed where it lives: `plan-format.md`,
  `phase-7-creation.md`, and the `plan_is_outline_shaped` doc comment in
  `checks.rs`; `plan-doc-structure.md` documents the outline-shaped
  coordinated form (outlines, each with `**Repo**:` and `**Group**:`, plus a
  Dependency Graph). An outline-shaped coordinated PLAN is authored at
  `Active`, as `single-pr` at `none` is, so `/scope`'s PLAN-Active resume row
  and the R25 status table cover it.
- `phase-4-agent-generation.md`: coordinated gets full outline bodies at
  `none` and full issue bodies when issues are filed.
- `phase-7-creation.md`: a coordinated branch that writes outlines at `none`
  and, only at `issues` or `issues-and-milestone`, files through
  `create-issues-batch.sh` behind the explicit filing approval; single-pr and
  coordinated next-step advice names `/execute` (R23).
- The Rust outline parser behind `shirabe plan outlines` gains `repo` and
  `group` fields read from `**Repo**:` and `**Group**:`, so there is still one
  outline parser. The validator flags an outline in a coordinated PLAN that
  lacks either field, with the same validation `plan-to-tasks.sh` applies to
  the table path's annotation row (repo `owner/repo`, group
  `^[a-z][a-z0-9-]*$`).
- `scripts/plan-to-tasks.sh`: `process_coordinated` gains an outline path,
  taken only when the PLAN's `tracking_level` is `none`. It reads each
  outline's repo, group, and dependencies from `shirabe plan outlines`
  (never re-parsing the markdown), refuses an outline missing either field
  with the table path's wording, contracts to `(repo, pr_group)` nodes
  exactly as the table path does, and emits `ISSUES` as local outline IDs with
  `ISSUE_SOURCE=plan_outline` for the children, so `/execute`'s coordinated
  loop dispatches `/work-on` from outlines with no GitHub issue. Both paths
  emit `REPO`, `PR_GROUP`, and `ISSUES` node vars, and the refusal text says
  "atomicity across PR groups".
- The validator (`crates/shirabe-validate/src/checks.rs`):
  `plan_is_outline_shaped()` treats `coordinated` at an explicit
  `tracking_level: none` as outline-shaped, exactly as it treats `multi-pr`
  (an absent field stays issue-carrying for both), so FC04/FC14 accept the
  outline form and still flag a PLAN that populates both outlines and an
  issue table.
- A `gh` shim under `skills/plan/evals/fixtures/bin/` that logs `issue create`
  calls (new), used to assert that none happen at the default level.

**`/scope`.**

- Constrained variables in `scope.md` (K3):
  - `TOPIC`: pattern `^[a-z0-9][a-z0-9-]*$`, so no leading `-`;
  - `PLUGIN_ROOT`: an absolute path with no `..` segment, `rebind: true`;
  - `PLUGIN_ROOT_PLACEMENT`: pattern `^outside$`, `rebind: true`. koto's
    pattern can't see the work tree, so `scope-open.sh` computes this value
    on every invocation (`outside`, or `inside-worktree` when `PLUGIN_ROOT`
    lies inside the repository being worked on) and passes it, and koto
    refuses `inside-worktree`, under `--koto-leg` recording
    `invalid-var:PLUGIN_ROOT_PLACEMENT` on the leg;
  - `INTENT_FLAG`: pattern `^(continue|stop)?$`, default empty, not
    rebindable. It carries the caller's `--intent` token unmodified, so
    `--intent` accepts only `continue` and `stop` (R1) and koto itself
    refuses `--intent=none`, `--intent=unset`, `--intent=absent`, or any
    other token at `koto init` (exit 2, no session; under `--koto-leg` the
    refusal is recorded on the leg with reason `invalid-var:INTENT_FLAG` or
    `duplicate-var:INTENT_FLAG`). When the flag is missing,
    `scope-open.sh` leaves the variable out and it resolves to empty, so a
    bare re-invocation isn't compared at attach. A lone, explicitly empty
    `--intent=` is treated as a missing flag: `scope-open.sh` leaves the
    variable out for it too (omitting a variable refuses nothing, so no leg
    is left open), and it behaves exactly as a bare invocation, attach
    included. There is no user-settable `INTENT` variable: `intake` derives
    `RUN_INTENT` (`continue|stop|none`) from `INTENT_FLAG` when non-empty,
    else the state file's recorded `intent:`, else `none`;
  - `COORDINATION`: `none|coordinated|no-coordinated`, default `none`;
  - `EXEC_MODE`: `auto|interactive|default`, default `interactive`,
    `rebind: true`;
  - `MAX_ROUNDS`: 1 to 50, or empty, `rebind: true` (so a direct run picked up
    by `/deliver` with a different value resumes rather than refusing);
  - `UPSTREAM`: a repository-relative `docs/roadmaps/ROADMAP-*.md` path, or
    `owner/repo:` followed by that path, never with a `..` segment, or empty.
- Phase 0 keeps only tokenizing and the residue rule. The agent writes the
  tokens to an args file outside the work tree (the koto session directory
  or a private `mktemp` directory), and `scripts/scope-open.sh`, a thin
  wrapper over the shared `koto-open.sh` (Key Interfaces > koto entry), maps
  each flag occurrence to one pair with `jq`, never `eval`. A repeated
  `--intent` (every occurrence written, an empty one included, so
  `--intent=stop --intent=` is a repeat), both mode flags, or both
  coordination flags becomes a duplicate key koto refuses. A bare `--intent`
  with no `=` is written as the literal token `--intent`, which
  `INTENT_FLAG`'s pattern rejects. `scope-open.sh` never refuses on its own
  for a check a koto variable can express; it computes the value and lets
  koto refuse it, so under `--koto-leg` every such refusal lands on the leg.
  Its only own refusals are those where no koto call can be built at all (a
  malformed `--koto-leg` value, an args file inside the work tree, no `koto`
  binary), and `/deliver`, which builds those arguments, never produces
  them. `scope-open.sh` renders koto's structured errors in today's exact
  wording (D2). The cold-start prompt stays before init on a standalone run.
- `--koto-leg=<request-id>:<leg>`, checked against koto's request-id pattern
  and a closed leg-name set. It changes nothing but where the result goes.
  Retention is `--no-cleanup` on every tick, unconditionally.
- `intake` becomes `initial_state`. Its read-only default action,
  `run-intake.sh`, prints `RUN_INTENT` (from `resolve-intent.sh`) for koto
  to capture, and runs `check-upstream.sh` and `check-recorded-intent.sh`,
  which compares a non-empty `INTENT_FLAG` against the state file's
  `intent:` and reports `intent-mismatch` when they differ. It clears, then
  writes the checks' verdict, the refusal `reason`, and the `recorded`
  intent to context with `koto context add`, and `intake` routes on
  non-overridable `context-matches` gates over that verdict, not on command
  gates. Failures route to `done_refused` with a reason or `done_error` with
  `scope:intake`.
  `done_refused`'s result carries `outcome: refused`, and
  `print-scope-exit.sh` prints it as `outcome=error` with
  `step=scope:refused`.
- `resume_route` replaces `branch_check`'s setup target. Its single gate
  runs `resume-probe.sh`, the whole resume ladder as one table-tested probe
  over the artifact tree, the state file, the child partials, and the
  handoff, exiting with the row codes in Key Interfaces. `phase-resume.md`
  stays the normative spec. The ladder's prompts become states
  (`resume_stale`, `resume_malformed`, `resume_exit_set`, `resume_draft`,
  `resume_boundary`) with identical wording and choices.
- The intent shortcuts (Decision 5): agent-run `republish` with its
  `--verify --expect-intent` gate, then `republish_record`, a default action
  running `record-scope-exit.sh`; and `executed_report`, whose default
  action runs `owned-pr.sh --state all` and writes the PR's URL and
  `pr_state` to context, routing on non-overridable `context-matches` gates
  over those keys. It has nothing to create, so zero or several owned PRs,
  or a failed read, end at `done_error` with `scope:pr-create`. An Active PLAN with no
  intent still refuses, with `next=` by mode (R23).
- `/plan` hop forwarding in `phase-2-chain-orchestration.md` and the
  template: `--intent`, the coordination flags exactly as passed, and
  `/scope`'s own resolved mode flag when intent is set. `hop_plan`'s
  `landed` edge requires `plan_mode_consistent` (Decision 6).
- With `--intent` set, `/scope` never creates a coordination PR up front;
  the publish step opens it at exit once the PLAN's mode is known. Without
  intent, today's up-front behavior is untouched (D2).
- The three publish states and the `intent_declared` gate (Decision 5).
- Terminals with result maps (K1, R31): `done_full_run`, `done_republished`,
  `done_executed`, `done_re_evaluation`, `done_abandonment`,
  `done_cancelled`, `done_refused` (failure), and `done_error` (failure),
  with `outcome`, `step`, `reason`, and `plan_execution_mode` assigned on
  their edges (K2). The exit-summary block in `phase-4-cleanup.md` is
  rendered by `print-scope-exit.sh` from that result.
- New scripts, each with a `_test.sh`: `publish-scoping-pr.sh`,
  `startable-issues.sh` (wraps `plan-to-tasks.sh`, keeps roots in PLAN
  order, reads titles from the issue cells without calling `gh`),
  `scope-open.sh`, `run-intake.sh`, `resolve-intent.sh`, `check-upstream.sh`,
  `check-recorded-intent.sh`, `resume-probe.sh`, `record-scope-exit.sh`,
  `check-plan-mode.sh`, and `print-scope-exit.sh`. `/scope` reuses the
  shared `owned-pr.sh`, which `/execute`'s single-pr work adds (Key
  Interfaces > Script interfaces).
- The resume redirect for an Active PLAN routes by mode (R23), the
  PLAN-status table reflects what `/plan` writes, and the state-file enum
  re-validation accepts `coordinated` (R25).
- A `gh` shim with a call log under `skills/scope/evals/fixtures/bin/` (new).
- State-schema fields `intent:`, `published_pr:`, `publish_error:`.
- A Publish group in Security Considerations, restated in `/scope`'s
  exit-finalization and cleanup phases.
- The SKILL.md write-target section gains the branch push and PR creation
  (R28); `requires.tsv` gains `gh - - mode:intent` and the koto minimum
  (R32).

**`/execute`.**

- `--merge` parsed and passed as `MERGE`. `MERGE` (default `false`) and
  `PAUSE_BEFORE_FINALIZE` (default `false`, as today; interactive mode sets
  it `true`) become `rebind: true`, and `PLUGIN_ROOT` takes the
  same absolute-path pattern as in `scope.md`, so a resumed run takes this
  invocation's merge and mode settings (R15, R17). `PLAN_DOC` and
  `PLAN_SLUG` aren't rebindable.
- `--koto-leg`, entering through `koto-open.sh` with `--attach-live
  --replace-terminal`, which replaces the read-then-clean recovery of a
  retained terminal. The session stays a root with `--no-cleanup` on every
  tick. `execute.md` and `execute-coordinated.md` share the
  `execute-<topic>` name, so a finished session from the other template is
  replaced, and a live one is refused and prints `outcome=error` with
  `step=execute:refused`.
- New scripts, each with a `_test.sh`: `merge-verdict.sh` (read-only),
  `merge-exec.sh` (the only `gh pr merge` line), `record-merge-verdict.sh`
  (the `merge_readiness` default action), `owned-pr.sh` (the shared
  ownership-filtered lookup, also used by `/scope` and `/deliver`),
  `push-and-record.sh`,
  `print-exit.sh`, and the coordinated `coordinated-next.sh`,
  `node-cut.sh`, `node-push.sh`, and `coordination-verdict.sh`.
- Four koto states and two terminals, the `ci_monitor` edge retargets, and
  the regenerated mermaid (Decisions 3 and 6). `record-merge-verdict.sh`
  clears `merge_verdict` before each recompute, so a failed or timed-out
  action routes to `pending:` rather than replaying an old value. Every
  route into `merged`, row 1's already-merged verdict included, passes
  `merge_confirm`, whose default action records the confirm read as
  `confirm_verdict` and whose `context-matches` gates are
  `overridable: false` (K8); a shim that keeps reporting `OPEN` ends the run
  at `ready_awaiting_merge`. `merge_route`'s gates are non-overridable too,
  and `merge_attempt` carries a non-overridable `test "{{MERGE}}" = true`
  gate whose failure ends `ready-awaiting-merge` with
  `reason=merge-not-requested`. `plan_completion` gains an
  `expected_head_recorded` gate.
- A `result:` map on every terminal (R31). No terminal carries `refused`:
  an init-time or attach refusal creates no session, so koto records it on
  the leg, and `print-exit.sh` prints it as `outcome=error` with
  `step=execute:refused`. Scripts write `home_pr` from the owned-PR
  script's output, never a transition from agent evidence, and a record
  state captures `repos` at start. `/execute` makes no pre-init refusal of
  its own for anything a koto variable can express. The pinned DIRTY edge
  writes `outcome=ready-awaiting-merge` and `reason=merge-state:DIRTY`, and
  `ci_monitor`'s `failing_unresolvable` edge maps to `execute:ci`.
- The coordinated loop (Decision 6) inside a new `execute-coordinated.md`
  envelope: agent-run `coord_setup` records the write set as `repos` and
  the repository holding the coordination branch as `home_repo`; agent-run
  `coord_loop` runs `coordinated-next.sh` and the action it names until it
  prints `done:`, `pause`, or `error:`; `coord_verdict`'s default action
  runs `coordination-verdict.sh` and writes its verdict, `pr`, `waiting`,
  `resume`, and `reason` to context with `koto context add` (clearing them
  first, so a failed or timed-out run can't replay old values), and the
  state routes on non-overridable `context-matches` gates over the verdict
  to `merged` (through the same confirm read, run as
  `record-merge-verdict.sh --confirm` with `home_repo` and the coordination
  branch as its explicit inputs), `ready_awaiting_merge`,
  `paused_awaiting_merges`, or `done_blocked`. The envelope has no
  `done_refused` terminal. Each node PR is titled `feat(<slug>): <node-id>` with a
  fixed body template, and its branch runs the single-pr `wip/` sweep
  before `gh pr ready`. The chain-finalization cascade runs once, on the
  coordination branch, after every node PR has merged.
- Outline-sourced children on node branches: a node branch is cut from the
  default branch (or lives in another repository), so the PLAN isn't in its
  tree. `/execute` dispatches each outline child with `PLAN_DOC` set to the
  PLAN's absolute path in the coordination checkout, the checkout that holds
  the coordination branch, and the child reads its outline from there; with
  issues, the child reads GitHub as today. The coordinated section of
  `skills/execute/SKILL.md` is rewritten accordingly: it reads work items and
  PR status, not "issue/PR status", and dispatches a node's work items, not
  "its issue(s)".
- The ownership filter at every existing PR lookup: the four
  `gh pr list --head ... .[0]` sites in `execute.md` and the resume ladder's
  title search, which becomes a head-branch lookup.
- An exit summary that always prints `outcome=`.
- The write-target section gains `gh pr merge` (R28), and `requires.tsv`
  gains the koto minimum (R32).
- R24 wording, enforced by a new `scripts/check-merged-wording.sh` with an
  allowlist.

**`/work-on`.** R24 wording only.

**Validator and CI.**

- Single-repo tests in `crates/shirabe-validate/src/coordination.rs`,
  `merge_gate.rs`, and `crates/shirabe/tests/coordination_body.rs`.
- `.github/workflows/lifecycle.yml` drops a self-referencing PR-index entry.
- CI's koto pin moves to the release that carries K1-K6 and K8.

**`/deliver` (new).**

- `skills/deliver/SKILL.md`, with no phase files. It writes the args file
  outside the work tree, runs `deliver-open.sh`, runs the tick loop with
  `--no-cleanup`, prints the terminal result through `deliver-report.sh`,
  and closes the request on the way out (if it doesn't, the next run
  abandons it). Its write-target section declares one write of its own, the
  per-run koto request, and names every repository write as its children's
  (R28).
- `skills/deliver/koto-templates/deliver.md` and its mermaid, with variables
  `TOPIC`, `PLUGIN_ROOT`, `COORDINATION`, `UPSTREAM`, and `MAX_ROUNDS` under
  the same constraints as `scope.md`, plus `MODE` (`auto|interactive`,
  default `interactive`) and `MERGE` (`true|false`, default `false`;
  `deliver-open.sh` sets it `true` unless `--no-merge` is given).
- Scripts under `skills/deliver/scripts/`, each with a `_test.sh`:
  - `deliver-open.sh`: resolves the mode from the flags and the
    `## Execution Mode:` header (R15). It's a thin wrapper over
    `koto-open.sh` and never reads an origin record, which koto doesn't
    expose. It first probes `deliver-<topic>` with `koto-open.sh
    --attach-live --replace-terminal` and only `TOPIC` and `PLUGIN_ROOT`:
    `refused=origin_mismatch` or `template_mismatch` means a same-named
    session from another worktree, store, or template, a collision and a
    stop; any accepted outcome means the name is this worktree's, and the
    session is cleaned. It then opens a fresh session through `koto-open.sh`
    with the full args file and prints koto's refusals;
  - `deliver-preflight.sh`: the visibility check (R29);
  - `deliver-open-request.sh`: abandons open requests for the coordinator,
    creates the new one with each leg's role, template, and inputs, and
    prints its id;
  - `deliver-probe.sh`: the `scoped`, `executed`, and `merged` re-checks,
    each finding the owned PR itself. It runs as a default action, so it
    clears its verdict, `checked_pr`, and the result key `pr` first, then
    writes its verdict and, when the lookup succeeds, the owned PR's URL as
    both `checked_pr` and `pr` (and `pr_state`) with `koto context add`. A
    stale `pr` copied from a leg is replaced or left cleared, never
    reported;
  - `deliver-report.sh`: prints the exit lines from the terminal result,
    validating each value against a closed pattern (PR URL, `owner/repo`
    list, enumerated outcome, step, and reason) and dropping anything else.
- A shared `scripts/plan-mode.sh` that maps a PLAN's mode to an exit code.
- `requires.tsv` with the koto minimum (R32) and read-only `gh` and `git`
  (the probes and the merge confirm read).
- `evals/` with a `gh` shim, a real koto, and fixtures.
- A row in `README.md`.

### Key Interfaces

**Flags.**

| Skill | Flag | Notes |
|-------|------|-------|
| `/scope` | `--intent=continue\|stop` | Only these two values. A constrained koto variable: invalid or repeated values are refused at `koto init` with no session. The token reaches koto unmodified as `INTENT_FLAG` (pattern `^(continue\|stop)?$`, empty when the flag is missing), so `--intent=none` and `--intent=unset` are refused by koto with the same wording. On a live session, a differing explicit value is refused as `var-mismatch:INTENT_FLAG`; a bare re-invocation attaches. |
| `/scope`, `/execute` | `--koto-leg=<request-id>:<leg>` | Child-owned; attaches the session to a koto request leg so the terminal result reaches it. Output is otherwise identical to a direct run. |
| `/plan` | `--intent=continue\|stop`, `--coordinated`, `--no-coordinated` | Child-owned, usable directly. `/scope` forwards only what the caller passed. |
| `/execute` | `--merge` | Becomes the koto var `MERGE`, rebound on every invocation. Never remembered across runs. |
| `/deliver` | `--auto`/`--interactive`, `--no-merge`, forwarded `--upstream`, `--max-rounds`, `--coordinated`, `--no-coordinated` | Mode is resolved once and passed to both children. |

**koto entry.** Every koto-backed skill in this chain enters through
`koto-open.sh`, which runs
`koto init <session> --vars-file <file> [--attach-live] [--replace-terminal]
[--koto-leg <req>:<leg>]`. There are four outcomes:

- a new session;
- an attached live session, when its template, origin record, and
  non-rebind variables match, with the `rebind` variables then re-applied
  in the same step;
- a fresh session replacing a retained terminal one, whose old result the
  skill may print;
- a refusal with exit 2 and a typed error, rendered in today's wording and,
  under `--koto-leg`, recorded on the leg by koto. A refusal changes nothing
  on the session, rebind variables included.

**Requests and legs.** `open_request` creates one request per `/deliver`
invocation with two legs and captures the id as `REQ`:

| Leg | `role` | `template` | Inputs |
|-----|--------|------------|--------|
| `scope` | `scope` | `scope.md` | `TOPIC`, `INTENT_FLAG: continue` |
| `execute` | `execute` | `execute.md`, `execute-coordinated.md` | `PLAN_SLUG` |

The request is created before the PLAN's mode is known, so the `execute` leg
names both of `/execute`'s templates, and K5 accepts a session built from
either. The single-pr versus coordinated mismatch is caught one step
earlier, by `--attach-live`'s template check on the `execute-<topic>`
session itself. A leg leaves the open state in one of four ways:

- **promoted**: the child reached a terminal and koto copied its result;
- **refused**: koto refused the child's arguments or attach and recorded
  `{outcome: refused, reason}`;
- **explicit**: `/deliver`'s absent state resolved it with the fixed
  `deliver:child-absent` error;
- **abandoned**: a newer `/deliver` run superseded the request, or some
  party holding the request id abandoned it. The run whose own request is
  abandoned ends `deliver:request-abandoned`.

A leg holds one result per run; a retry is always a new `/deliver`
invocation with a new request. Only a promoted, valid result can move
`/deliver` forward.

**Terminal results.** The keys each skill's terminals declare, and so what a
leg carries:

| Skill | `outcome` values | Other keys |
|-------|------------------|------------|
| `/scope` | `scoped`, `handed-off-multi-pr`, `executed` (progress); `re-evaluation`, `abandonment`, `cancelled` (stops); `refused`, `error` | `exit`, `intent`, `next`, `pr`, `pr_state`, `plan_path`, `plan_execution_mode`, `wip_paths`, `startable`, `boundary`, `via`, `reason`, `recorded`, `requested`, `step` |
| `/execute` | `merged`, `ready-awaiting-merge`, `paused-for-review`, `paused-awaiting-merges`, `error`; `refused` only in koto's refusal record on the leg, never from a terminal | `pr`, `repos`, `resume`, `waiting`, `reason`, `step` |
| `/deliver` | the PRD's Final States for `/deliver` | `step`, `reason`, `pr`, `pr_state`, `repos`, `resume`, `waiting`, `next`, `startable`, `wip_paths` |

`/scope`'s `reason` is one of `invalid-var:<V>`, `duplicate-var:<V>`,
`var-mismatch:<V>`, `template-mismatch`, or `origin-mismatch` (from koto),
`intent-mismatch`, `upstream-wip`, `upstream-untracked`, `upstream-outside`,
`upstream-basename`, `plan-active`, or `plan-done`. Its `step` is one of
`scope:push`, `scope:pr-create`, `scope:intake`, or `scope:resume-probe`.
`/execute`'s `waiting` holds one comma-joined `<pr-url>:<human|predecessor>`
entry per unmerged PR.

**Exit lines.** One `key=value` per line, rendered from the terminal result by
`print-scope-exit.sh`, `/execute`'s `print-exit.sh`, and `deliver-report.sh`,
and asserted by evals. They're the human-facing contract; no skill parses
another's. `/scope`'s block:

```
/scope finished: exit=<exit>; artifact=<path>
intent=<continue|stop|none>
outcome=<scoped|handed-off-multi-pr|executed|error>   # full-run, executed-topic resume, failure, or refusal
step=<scope:push|scope:pr-create|scope:intake|scope:resume-probe|scope:refused>   # error only
next=<command>                               # full-run only
pr=<url>                                     # intent runs only
pr_state=<merged|open>                       # executed only
wip_paths=<comma-separated paths>            # intent runs with wip/ in unpushed history
#<N> <title>                                 # multi-pr startable issues, then one closing line
```

Re-evaluation, abandonment, and cancelled runs print today's exit record with
no `outcome=` line. A refusal prints today's refusal text followed by
`outcome=error` and `step=scope:refused`, whether it comes from
`done_refused` or from `scope-open.sh` rendering a koto init refusal.
`refused` is never printed after `outcome=`.

`/execute` prints `outcome=<token>`, `step=<step>` on error (a refusal is
`outcome=error` with `step=execute:refused`), `repos=<comma-
separated owner/repo list>` (its write set, fixed at start), and for each
unmerged PR `pr=<url> waiting=human|predecessor reason=<condition>`. For a
pause it adds the resume command.

**Script interfaces.** Both merge scripts take everything they decide on as
arguments, and neither reads koto context or state files:

- `merge-verdict.sh --repo <owner/repo> --pr <n> --merge <true|false>
  --expected-head <sha|none> [--confirm]` prints one verdict line and exits 0,
  or exits non-zero on a usage error. `record-merge-verdict.sh` passes the
  session's `MERGE` variable as `--merge`. `--expected-head none` makes row 8
  fire. Because the exit code is 0 for every verdict, `--confirm` included,
  no caller routes on it: callers record the printed line to context in a
  default action and route on that.
- `merge-exec.sh <owner/repo> <pr> <expected-head>` runs
  `merge-verdict.sh --merge true --expected-head <expected-head>` itself,
  refuses unless the fresh verdict is `mergeable:<method>:<expected-head>`,
  then makes the single fixed-text merge call with that method and sha, and
  prints `merge-called:<method>:<sha>` or `merge-refused:<verdict>`. The
  caller confirms with `merge-verdict.sh --confirm`; `merge-called` is never
  read as merged.
- `record-merge-verdict.sh --repo <owner/repo> --head-branch <branch>
  [--confirm]` is the default action that resolves the owned PR and records
  a verdict (`merge_verdict`, or `confirm_verdict` with `--confirm`) in
  context. The repository and head branch are explicit arguments in both
  modes, each pattern-checked; `--repo` is a single `owner/repo`, never the
  comma-joined `repos` write set, which the script doesn't read. Single-pr
  passes its one repository and the run's branch; the coordinated
  envelope's confirm read passes `home_repo` and the coordination branch.
- `owned-pr.sh` is the one shared ownership-filtered lookup, added by
  `/execute`'s single-pr work and called unchanged by `/scope` and
  `/deliver`. It keeps only PRs that pass the ownership filter below (same
  repository, the authenticated author, the expected base, and the expected
  head branch). `--state open` considers OPEN PRs; `--state all` considers
  OPEN and MERGED PRs and drops CLOSED-unmerged ones, so a PR the user
  closed never counts beside the open one that replaced it. When exactly
  one survives, it prints that PR's URL and
  exits 0. When none survives, it prints nothing and exits 0; a branch whose
  only PRs come from forks or other authors counts as none. When several
  survive, it exits 3. When the read fails, it exits 2. The script names no
  step; each caller maps the result to its own:

  | Caller | Zero | Several | Read failure |
  |--------|------|---------|--------------|
  | `/scope` publish | create its PR | `scope:pr-create` | `scope:pr-create` |
  | `/scope` `executed_report` | `scope:pr-create` (nothing to create) | `scope:pr-create` | `scope:pr-create` |
  | `/execute`, where it creates (home PR, node PR) | its create path | `execute:pr-adopt` | `execute:status-read` |
  | `/execute`, where it must adopt (PR-index entries) | `execute:pr-adopt` | `execute:pr-adopt` | `execute:status-read` |
  | `/deliver` re-checks | `deliver:child-outcome` | `deliver:child-outcome` | `deliver:child-outcome` |

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
| 14 | the PR changes `.github/workflows/`, `.github/actions/`, or a CODEOWNERS file and `reviewDecision` isn't `APPROVED`, read from the complete paginated file list (`repos/<repo>/pulls/<n>/files`), not the first page of the snapshot; a list that can't be read, or is shorter than the PR's `changedFiles`, gives `error:execute:status-read`, never a clean result | `awaiting:workflow-change` | `ready-awaiting-merge` |
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

**Merge intent per invocation.** Merge intent is the session's `MERGE`
variable and nothing else. It's set at `koto init` from this invocation's
`--merge` (false without it), and, being `rebind: true`, re-applied from this
invocation's flags whenever a live session is attached, so it's never agent
evidence and never inherited from an earlier run. A session resumed without
`--merge` doesn't merge and one resumed with it does (R17). Rebind happens
only inside an accepted attach (K4), so an invocation whose attach is refused,
such as a stale driver naming an abandoned leg, leaves `MERGE` as it was.
Between two accepted invocations on one session, the later one's setting
wins.

**Expected-head record.** Row 8 compares the PR head with the commit
`/execute` expects, recorded durably by the push itself, never by the agent:

- Single-pr: `run-cascade.sh --push` and `push-and-record.sh` record
  `git rev-parse HEAD` in the koto session's context after a successful push
  (the session is retained across a resume). `plan_completion`'s
  `expected_head_recorded` gate makes a missing record visible.
- Coordinated node PRs: `node-push.sh` pushes and writes a `head=<sha>`
  field on the node's line in the coordination PR's index, validating the
  new body before editing it, so a resume in any working copy reads it back.
  A collaborator who can edit that body can edit the field too, so for
  coordinated nodes the check guards only against pushers who can't; required
  reviews and checks still apply.
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
index entries, whose head branch is the one the node's id determines.
Several matches after that filter is always an error, never a pick. Zero
matches means no owned PR exists: a caller that creates PRs opens one, and a
caller that must adopt one reports an error. `owned-pr.sh`'s exit contract
and each caller's step mapping are under Script interfaces. `/execute` fixes
the set of repositories it may write to when it starts and rejects PR-index
entries, outline `**Repo**:` fields, or `_Repo:` rows outside it.

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

The Overview diagram shows the sequence. What each hand-off carries:

1. **Into `/scope`:** the raw tokens through `--vars-file`, and `REQ:scope`.
   `intake` writes `intent:` to the state file.
2. **Through the `/plan` hop:** the forwarded flags in; `split_branch`,
   `split_rationale`, `execution_mode`, and `split_mode_source` recorded in
   the PLAN, plus Repo and Group on each outline (or issue row, when issues
   are filed) of a coordinated split.
3. **Out of `/scope`:** on intent runs, its own topic `wip/` untracked, one
   pushed branch, one verified PR, and a terminal result on the leg.
4. **Into `/execute`:** the PLAN path, `--merge`, and `REQ:execute`. It
   adopts the PR by head branch through the ownership filter. The CI
   deadline and the no-checks grace window are anchored on the head commit's
   `committedDate` from the same PR snapshot, so the scripts keep no
   bookkeeping and a resumed run measures the same deadline.
5. **Out of `/execute`:** a terminal result on the leg, which `/deliver`
   re-checks against GitHub before reporting.
6. **Coordinated resume** reads the coordination PR (its PR index and
   merge-order block) and the node branches' PRs.

### `/deliver` template states

`deliver.md` always enters through `/scope`, which owns every "where did this
topic stop" question through `resume_route`. No state pushes, merges, or
writes to GitHub as a default action. The default actions either touch
koto's request store or run a read-only probe whose output the state needs.
A command gate yields only an exit code, so each durable re-check runs
`deliver-probe.sh` as a default action that clears, then writes its verdict
and the PR it found to context with `koto context add`, and the state routes
on `context-matches` gates over those keys. The PR it found is written both
as `checked_pr` and as the result key `pr`, replacing the value the leg
copied. That's the only way a re-checked PR reaches a result: a
transition's `context_assignments` can't read `${context.<key>}`, so edges
assign only literals, `{{VAR}}` values, and `${gates.<leg>.payload.*}`
paths, and each terminal's `result:` map reads its keys as
`${context.<key>}`. The two leg gates and the
re-checks' `context-matches` gates are `overridable: false` (K8).

| State | Kind | Gate | Transitions |
|-------|------|------|-------------|
| `preflight` | gate-only | `deliver-preflight.sh` (R29) | Public goes to `open_request`; private or unknown goes to `done_refused` (`private-repo`) |
| `open_request` | default action (koto request store only; safe to re-run) | `deliver-open-request.sh` abandons open requests for this coordinator, creates `REQ` with legs `scope` and `execute` (role, template, inputs) | `scope_run` |
| `scope_run` | agent-run: `Skill /scope <topic> --intent=continue --<mode> --koto-leg=REQ:scope` plus forwarded flags | `scope_leg`: `request-leg` on `scope`, with the scope outcome set, `refused` included, as `expect` | An open leg waits. Every arm copies `outcome`, `plan_path`, `plan_execution_mode`, `pr`, `pr_state`, `startable`, `wip_paths`, and `next` from the leg's `payload` into context (K2). Promoted and valid: `scoped` or `handed-off-multi-pr` go to `scoped_check`; `executed` to `executed_check`; `re-evaluation`, `abandonment`, `cancelled` to `done_stopped` (`scope-ended-early`); `error` to `done_error` with the step; `refused` with `intent-mismatch` to `done_error` (`deliver:intent-mismatch`), and any other promoted `refused` to `done_error` (`scope:refused`). Source `refused` with `var-mismatch:INTENT_FLAG` goes to `done_error` (`deliver:intent-mismatch`); other source refusals to `done_error` (`scope:refused`). Invalid goes to `deliver:child-outcome`; explicit to `deliver:child-absent`; disposition `abandoned` to `done_error` (`deliver:request-abandoned`). Evidence `child_returned: yes` on an open, unbound leg goes to `scope_absent` |
| `scope_absent` | default action: resolve the `scope` leg with the fixed `{outcome: error, step: deliver:child-absent}` | none | back to `scope_run`; if the leg was bound meanwhile, the resolve is refused and `scope_run` keeps waiting |
| `scoped_check` | default action (read-only) plus `context-matches` gates | `deliver-probe.sh scoped`: PLAN tracked and unchanged at HEAD, and `publish-scoping-pr.sh --verify --expect-intent continue`; clears, then writes `scoped_verdict` and the verified PR's URL as `checked_pr` and `pr` | pass goes to `mode_route`; fail to `done_error` (`deliver:child-outcome`) |
| `mode_route` | gate-only | `plan-mode.sh` (0 single-pr, 10 coordinated, 20 multi-pr, 4 invalid) | 0 and 10 go to `confirm`; 20 to `done_stopped` (`handed-off-multi-pr`, with the `startable` value `scope_run` copied); 4 to `deliver:child-outcome` |
| `confirm` | gate plus agent | `test "{{MODE}}" = auto` | auto goes to `execute_run`, ignoring stray evidence; otherwise `decision: proceed` goes to `execute_run` and `decision: stop` to `done_stopped` (`scoped`, `next=/deliver <topic>`) |
| `execute_run` | agent-run: `Skill /execute docs/plans/PLAN-<topic>.md --<mode> [--merge] --koto-leg=REQ:execute` | `exec_leg`: `request-leg` on `execute` | Every arm copies `pr`, `repos`, `resume`, and `waiting` from the leg's `payload`. Promoted and valid: `merged` goes to `merged_check`; `ready-awaiting-merge` to `done`; the two pauses to `done_stopped`; `error` to `done_error` with the step. Refused goes to `done_error` (`execute:refused`). Invalid, explicit, absent, and abandoned arms as in `scope_run`, through `execute_absent` |
| `executed_check` | default action (read-only) plus `context-matches` gates | `deliver-probe.sh executed`: PLAN absent, DESIGN under `current/`, and the owned PR found by `owned-pr.sh` on the topic's branch; clears, then writes `executed_verdict`, the PR's URL as `checked_pr` and `pr`, and `pr_state` | merged goes to `done` (`merged`); open to `done` (`ready-awaiting-merge`); anything else, including an empty verdict, to `deliver:child-outcome` |
| `merged_check` | default action (read-only) plus `context-matches` gates | `deliver-probe.sh merged`: `merge-verdict.sh --confirm` on the PR it finds itself with `owned-pr.sh --state all`, never the leg's `pr`: for single-pr on the topic branch `/scope` published (the branch whose PR `/execute` adopts on a `/deliver` run), for coordinated on the coordination branch; clears, then writes `merged_verdict` and, when the lookup succeeds, the PR's URL as `checked_pr` and `pr` (a failed lookup leaves `pr` empty) | `merged` goes to `done`; anything else, including an empty verdict, can only downgrade, to `done` with `ready-awaiting-merge` |
| `done`, `done_stopped`, `done_error` (failure), `done_refused` (failure) | terminal | none | a result with `outcome`, `step`, `reason`, `pr`, `pr_state`, `repos`, `resume`, `waiting`, `next`, `startable`, and `wip_paths`, read as `${context.<key>}` (`pr` as `${context.pr}`). Keys are assigned on the edges where literal or leg-derived, otherwise written by `deliver-probe.sh`. Into `done`, `execute_run`'s `ready-awaiting-merge` arm carries the leg's own `pr`; `executed_check` and `merged_check` carry the owned PR the probe wrote, or none after a failed lookup |

Because a topic with a PLAN still passes through `/scope`, a run whose
publish failed after the PLAN was written gets its PR opened on the retry
before `/execute` starts (R17). Because every `/deliver` invocation is a fresh
session with a fresh request, `--merge` and the mode are per invocation, and
every progress step is re-derived from durable state.

## Implementation Approach

The work spans two repositories and ships as a coordinated effort. koto's
changes land first, as their own PRs in `tsukumogami/koto`, and are released
(R32). shirabe then raises its koto floor to that release. Nothing in shirabe
that uses the new koto features can merge before the release exists and CI
pins it. Within shirabe, the phases stay ordered provider-first, so none
leaves `main` with a half-wired flag if it lands alone, and the choice
between one shirabe PR and several stays with `/plan`'s split step under the
repository's Delivery Preference.

Phases 3 and 4 (the shared references and `/plan`) use no new koto feature
and run in parallel with Phase 1. Every phase that uses `--koto-leg`,
`--attach-live`, `--replace-terminal`, result maps, or assignments (5a, 5b,
6, and 7) depends on the koto release through Phase 2; those phases can be
written against a koto pre-release, but none merges before the release. The
critical path runs through variable constraints, root attach, and the init
flags, then the release, shirabe's koto floor, `/scope`, `/deliver`, and the
guides.

### Phase 1: koto features (`tsukumogami/koto`)

| Item | Change | Needs |
|------|--------|-------|
| KA | K2, transition `context_assignments`, with generic dot paths into structured gate output | none |
| KB | K1, terminal `result:` map in the result's `payload`, up to 32 keys | none |
| KC | K3, variable `values:`, `pattern:`, and `rebind:` | none |
| KD | K5, `koto request attach` for roots, with template identity, refused fenced verbs, and the request-lifecycle design amendment | KC (non-rebind variables) |
| KE | K4, `koto init --vars-file`, `--replace-terminal`, `--attach-live` with template and origin checks, and `--koto-leg` with atomic attach-then-rebind and refusal recording | KB (refusal payload shape), KC, KD |
| KG | K8, `overridable: false` on gates | none |
| KF | K6, the `request-leg` gate reading the leg's `payload`, plus the change to koto's gate-reachability rule (D4) that lets a state whose only gates are non-overridable compile, since no override default can fire their arms | KB, KD, KG |
| KR | a koto release is published | KA-KG |

KA ships generic gate-field assignment on its own; the leg-gate path
(`${gates.<g>.payload.<k>}`) gets its end-to-end test when KF lands. KR's
condition is only that the release is published; shirabe's pin moves in
Phase 2. K7
(koto#240), K9 (request prune), and K10 (the `name_filter` fix) are
recommended or optional and off the critical path.

Deliverables:

- koto source changes with engine and compile tests
- the custom-skill-authoring guide updated for result maps, assignments,
  constraints, init flags, the leg gate, and non-overridable gates
- the request-lifecycle design amendment
- the release

### Phase 2: shirabe koto floor

Depends on KR (R32).

- The koto minimum raised in `requires.tsv` for `/scope`, `/execute`, and
  `/deliver`, with preflight naming the minimum when it's older.
- CI's koto pin moved to KR.
- A compile and eval sweep of every shirabe template under KR, `work-on.md`
  included. K2 now executes and strictly validates the 58 existing
  `context_assignments` blocks, so any block that names an undeclared
  `accepts` field or fails the new checks is fixed here, and the existing
  evals must pass. This phase also decides whether `/work-on`'s koto floor
  moves.
- The shared `scripts/koto-open.sh`: args-file transport outside the work
  tree with removal on every exit path, `--attach-live`,
  `--replace-terminal`, `--koto-leg`, and rendering koto's errors in today's
  wording, with a `_test.sh`.
- An upgrade note. Sessions created before the floor moves have no origin
  record, so `--attach-live` refuses them. An in-flight `/scope` or
  `/execute` run must finish, or be cleaned up, before the upgrade. This
  phase's migration notes document it.

### Phase 3: Shared contracts

Runs in parallel with Phase 1. Every edit under Components > Shared
references: repository count, precedence, the header definition, Branches,
and the merge and pause in `coordination-strategy.md`; the `coordinated`
enum, intent note, and the rule that the empty `INTENT_FLAG` value never appears in a state
file in the state schema; the draft/ready
amendment; `--koto-leg` and the koto-backed binding in the parent-skill
pattern; the leg-result row in child inspection; and the retention and
default-action references. Deliverables: the edited reference files.

### Phase 4: `/plan` emits both multi-PR modes

Depends on Phase 3's precedence and header definition, and runs in parallel
with Phase 1. It carries the flags and their rejection rules, step 5a
through `resolve-split-mode.sh`, Repo/Group on outlines and rows, the
issue-free default for coordinated (tracking level, the outline path in
`plan-to-tasks.sh`, and the validator's outline-shape rule), the coordinated
creation branch with filing approval when issues are asked for, the
`plan-to-tasks.sh` node vars with a single-repo test, next-step routing (R23), and the updated "(multi-repo)" eval
assertion. Deliverables: `skills/plan/SKILL.md` and phases 3, 4, and 7,
`plan-format.md` and `plan-doc-structure.md`, `plan-to-tasks.sh` and its
test, the plan-to-tasks contract doc, the Rust outline parser and
`plan_is_outline_shaped` in `checks.rs` with tests, the `/plan` `gh` shim, and
plan evals.

Inside the phase, the outline-shape work (the `plan-to-tasks.sh` outline
path, the validator's outline-shape rule, and `plan-doc-structure.md`) comes
first. The flags work follows it and owns the `phase-7-creation.md`
coordinated branch, including dropping the paragraph that exempts
coordinated PLANs. `/plan`'s creation phase runs `shirabe validate` on the
PLAN it writes, so the outline shape must validate before `/plan` can write
it.

### Phase 5a: `/execute` merge step (single-pr)

Depends on Phase 2, and so on the koto release, and on Phase 3's draft/ready
amendment. It carries the single-pr items under Components > `/execute`:
the two merge scripts with table-driven tests, the four states and two
terminals with the `ci_monitor` retargets, `record-merge-verdict.sh` and its
routing, the expected-head record, result maps and assignments, the rebind
and pattern changes, `--koto-leg` entry, the ownership filter, the
write-target addition (R28), and R24 wording with `check-merged-wording.sh`
and the `/work-on` edit. Deliverables: `skills/execute/*` for the single-pr
path, `skills/work-on/SKILL.md`, `scripts/check-merged-wording.sh`, the
execute `gh` shim with a call log and per-scenario fixtures, and execute
evals for the Merging criteria, including retention cases that assert the
result keys.

### Phase 5b: `/execute` coordinated path in one repository

Depends on Phase 2, and so on the koto release, on Phase 4's node vars, and
on Phase 5a's scripts. It carries the four coordinated scripts, each
table-tested; per-node branches, worktrees, PR titles and bodies, and the
`wip/` sweep; the `execute-coordinated.md` envelope with result maps and the
same `--koto-leg` entry; the merge, pause, and resume loop with `head=`
fields written only by `node-push.sh` and the cascade push; and the Rust
single-repo tests and `lifecycle.yml` filter; and outline-sourced children
reading their outline through `PLAN_DOC` in the coordination checkout.
Deliverables: the rewritten coordinated section of `skills/execute/SKILL.md`,
the envelope template and its mermaid, validator tests, `lifecycle.yml`, and
coordinated execute evals, including an outline-shaped coordinated PLAN run
end to end with no `gh issue` call.

### Phase 6: `/scope` intent, intake, resume, and publish

Depends on Phase 2, and so on the koto release, on Phase 3 (schema), and on
Phase 4 (forwarding targets real flags). It carries everything under
Components > `/scope`. Deliverables: `skills/scope/*`, its template and
regenerated mermaid, and scripts; and scope evals, including the "no `gh`
call on a no-intent run" assertion, R1 refusals with koto's exit 2 and
today's wording (including `--intent=none` and `--intent=unset`, which
koto refuses through the `INTENT_FLAG` constraint and, under `--koto-leg`,
records on the leg), and both mismatch cases.

### Phase 7: `/deliver`

Depends on Phases 5a, 5b, and 6, and through them on the koto release.

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
cover, so the "every R1-R25, R30, and R31 covered, 3 of 3 runs" criterion
(R26) can be checked phase by phase:

- GitHub state comes from the per-skill `gh` shims.
- Forced-split fixtures carry a hard constraint in the DESIGN; no-split
  fixtures are designs too small to split.
- `/deliver`'s scenarios run a real koto and cover the stale-run fence (an
  old request with a live mid-hop `/scope` session is abandoned and the
  session re-pointed and resumed, with no second `scope-*` session), a late
  result from a superseded run being refused, a live `intent=stop` run
  refused as `deliver:intent-mismatch` with the working tree unchanged, the
  republish and executed shortcuts, a publish failure and its retry, a
  `/scope` that returns without attaching, an override attempt with
  `--with-data` and a forged promoted result on a leg gate that koto
  refuses, an abandoned request ending `deliver:request-abandoned`, a
  session from another template or worktree refused at attach, and a
  `merged` result that the confirm read downgrades.
- A stale invocation whose attach is refused leaves the session's `MERGE`
  unchanged.
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
`merge-verdict.sh` returns a mergeable verdict only for an open, non-draft
PR whose merge state is `CLEAN`, whose every reported check succeeded (at
least one reported), whose review decision is neither `REVIEW_REQUIRED` nor
`CHANGES_REQUESTED`, and whose head equals the commit the run pushed. If the
base branch requires neither status checks nor reviews, the verdict is
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
invocation's flags, only inside an accepted attach, and no verb rebinds it
on its own. Merge intent never comes from agent evidence. An agent that
re-invokes `/execute --merge` on a live session does set it, because that's
an accepted invocation, so under two drivers on one topic the later accepted
invocation's setting wins. A fork PR named after a predictable
`impl/<slug>-<node-id>` branch can't be adopted, edited, readied, closed, or
merged, because every head-branch lookup filters on same repository, the
authenticated author, the expected base, and the expected head branch. A
branch that holds only a fork's or another author's PR counts as having no
owned PR, so a caller that creates opens its own and a caller that must
adopt reports an error; several owned PRs are always an error.

**No default action writes to GitHub.** The verdict, the expected head, and
`/scope`'s exit record are written by scripts, not the agent, but none of
those scripts pushes, opens a PR, or merges. `merge_attempt`, `republish`,
and the publish states stay agent-run. The default actions that carry a
script's output into context (`merge_readiness`, `merge_confirm`,
`coord_verdict`, `coord_merge_confirm`, `intake`, `executed_report`, and
`/deliver`'s re-checks) make read-only `gh` and `git` calls, and
`/deliver`'s other default actions touch only koto's local request store.

**Pushes never touch the default branch and never force.** The publish script
and every node push refuse a detached HEAD or the remote's default branch.
They push with an explicit `HEAD:refs/heads/<branch>` refspec and never pass
a force option. Branch names are built only from the validated topic slug and
node id.

**Published content is bounded.** PR bodies come from a fixed template over
validated fields and are passed with `--body-file`. The fields are the slug,
exit, outcome, intent, mode, `docs/` artifact paths, and work-item IDs
(outline IDs, or issue numbers when issues are filed).
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
shell: each skill writes them to an args file outside the work tree, maps
them with `jq` (no `eval`), and koto reads them through `--vars-file`; the
file is removed on every exit path, so a crash can't leave it for the
publish step's commit. koto enforces these patterns at init, before any gate
command sees a value:

- the topic starts with a letter or digit, so it can't be read as an option
  by the `git` and `gh` calls that take it;
- `--upstream` is a repository-relative `docs/roadmaps/ROADMAP-*.md` path or
  `owner/repo:` followed by that path, never with a `..` segment;
- `PLUGIN_ROOT` is an absolute path with no `..` segment, and changes only
  through an accepted attach; for `/scope`, `PLUGIN_ROOT_PLACEMENT` must be
  `outside`, so a plugin root inside the work tree is refused by koto, not
  by a wrapper;
- `--max-rounds` is a bounded integer.

`EXECUTE_CI_WAIT_LIMIT_SECS` must be a bounded integer, or the default
applies. Gate commands quote every `{{VAR}}`. The existing slug and enum
re-validation rules apply unchanged. `deliver-report.sh` validates each value
it prints from a leg against a closed pattern and drops anything else, so a
leg can't carry control characters or prose into the report.

**The koto request store is local state, and it grows.** Requests live under
`~/.koto/requests/`. The store is unix only and isn't replicated under koto's
cloud backend, so a `/deliver` run is a single-machine flow. Records hold
topic slugs, leg inputs, and results (outcome tokens, step names, PR URLs),
never credentials, and they accumulate until koto ships a prune verb (K9).
Progress never rests on a request record alone: every forward step re-checks
the PLAN, the owned PR, or GitHub.

**Leg attach and refusal are koto's, not the agent's.** Attach refuses a
terminal session, a session built from a template the leg doesn't name, and
a session whose non-rebind variables don't match the leg's inputs, so a
throwaway template that declares `outcome: merged` can't bind the leg. It
re-points a session only away from an abandoned leg or a closed request, so
one run can't take over another live run's bound leg. `--attach-live` also
compares the session's origin record (worktree and store): session names are
machine-wide, and a same-named `scope-<topic>` or `execute-<topic>` from
another repository or worktree is refused, not adopted. Admitting root
sessions carves an exception into koto's epoch fence, argued in koto's
request-lifecycle design: roots are never redelegated and their results
arrive only by promotion, so the fenced verbs (`progress`, `resolve`, and
leg-scoped `abandon`) are refused on a self-attached leg. koto records every
argument and attach refusal on the leg itself. The only result `/deliver`
writes is the absent record, a fixed JSON value that can reach only an error
arm, and koto rejects it if the child bound in the meantime. Request-scoped
abandon isn't fenced in koto, so a confused child that knows the request id
can abandon `/deliver`'s request; both leg gates route that disposition to
`deliver:request-abandoned`.

**Gate overrides can't manufacture progress or a report.** koto today lets
`koto overrides record` force any gate and logs it, and `--with-data`
replaces the override default without checking it against the gate's
output, so one override on a leg gate could drive any arm, including the
ones with no durable re-check behind them (`ready-awaiting-merge`, the
pauses, the multi-pr hand-off). K8 is therefore required: the two leg gates,
`merge_attempt`'s `MERGE` gate, and the `context-matches` gates that route
`merge_route`, `merge_confirm`, `coord_verdict`, `coord_merge_confirm`,
`scoped_check`, `executed_check`, `merged_check`, and `/scope`'s `intake`
and `executed_report` are `overridable: false`, and koto refuses an
override on them with or without `--with-data`. So an override can't carry
a run with `MERGE=false` into `merge_attempt`. Each state whose default
action writes those keys clears them before rewriting them, so a failed or
timed-out read leaves no value for a gate to match. Other gates can still
be forced, with a log entry, and none of them leads to `merged`.
`merge_confirm`, `merged_check`, and `executed_check` find the PR
themselves through the ownership filter, so agent evidence or a forged leg
`pr` naming some other merged PR proves nothing.

**Two drivers on one topic.** If an agent from an older `/deliver` keeps
ticking a child session after a newer run re-points it, nothing detects it:
koto can't know whether an agent is alive. Abandoning the old request shows
that agent koto's stop notice only until the newer child attaches, often a
matter of seconds, so the old agent's later work becomes the new run's work
under the new run's settings. A stale invocation that re-enters with the old
request id is refused at attach before any rebind, so it can't flip `MERGE`.
The merge protections above hold either way, since a merge still needs a
fresh verdict at a head commit the run itself recorded.

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

**Override records.** Replacing a terminal session with `--replace-terminal`
deletes that session's override log along with it. With K8 required, the gates
that matter can't be overridden at all, so the loss is limited to gates that
still accept overrides; recording overrides outside the session is left to
koto's request prune work (K9).

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
- The 58 `context_assignments` blocks koto silently dropped start working,
  including the `failure_reason` writes koto's batch view reads.
- `/scope`'s retained-terminal bug is fixed: a re-run on a finished topic
  gets a fresh session that walks the resume ladder instead of ticking a dead
  one.
- Direct `/execute` users resume with `--merge` correctly, because `MERGE`
  is rebound per invocation.
- CI waiting gets a real, testable limit, and `ci_monitor`'s ungated
  `failing_fixed -> done` shortcut is closed.
- The next-step advice and "merged" wording become accurate, and the PR body
  `/scope`'s exit-finalization phase promises becomes real on intent runs.
- The parent-of-the-parent slot gets a concrete koto binding. A future driver
  can nest `/deliver` by attaching it to a leg the same way.

### Negative

- Every `/scope` and `/execute` run, including a plain no-intent `/scope`,
  now needs a koto at or above the new floor. That's the one exception to D2.
- Sessions created before the floor moves have no origin record, so attach
  refuses them. A `/scope` or `/execute` run in flight across the upgrade
  can't resume without a manual cleanup.
- Delivery is coupled across repositories: shirabe can't ship until a koto
  release carries seven features, and koto's request-lifecycle reasoning
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
- The new koto turns on `/work-on`'s 38 dormant assignment blocks, so
  `/work-on` starts writing `failure_reason` and its W5 lint result changes.
- Under two drivers on one topic, merge intent is whatever the later
  accepted invocation passed.
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
- Phase 2's migration notes tell operators to finish, or clean up, any
  in-flight `/scope` or `/execute` run before upgrading koto.
- koto lands and releases first, with its own tests. If the leg gate slips,
  `deliver.md` captures a `koto request get` script's output into context
  through a default action. If the root carve-out is rejected, both children
  fall back to `--parent` children with a parent-side fence.
- Phase 2 compiles every shirabe template under the new koto and runs the
  existing evals, fixing any assignment block the stricter compiler rejects.
- The new states and scripts are covered by table-driven shell tests and
  mermaid regeneration; `resume-probe_test.sh` covers every ladder row and
  the first-match order. The pinned DIRTY route is untouched, and the two
  retargeted `ci_monitor` edges only add a verdict step before a terminal, so
  existing evals hold apart from R24 wording and deliberate exit-summary
  changes.
- K9 (request prune) is recommended to koto, and progress never depends on
  an old request record.
- The outcome-to-exit mapping lives on template edges and in one table in
  `/execute`'s SKILL.md.
- `/scope`'s `executed_report` lets `/deliver` report a single-pr PR's state;
  a future PR-number input mode for `/execute` is the path to re-merging it.
- `merge-not-observed` is a safe under-claim, named in the report so the
  author knows to check the queue.
- `publish-scoping-pr.sh` names any foreign tracked `wip/` path in its report,
  so the author sees why the PR's CI will fail.
- Evals pin every exit line and every result key `/deliver` routes on.
