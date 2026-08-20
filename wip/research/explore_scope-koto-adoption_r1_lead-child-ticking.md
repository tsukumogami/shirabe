# Lead: Who actually ticks a child session in `/execute` today, and does a context boundary exist anywhere in this repo?

**Disposition: no context boundary exists anywhere in this repo at a chain-child
hop, under either dispatch binding.** The stronger claim in the lead prompt is the
true one. Both `/scope`'s inline binding and `/execute`'s materialized binding run
the child in the same agent context as the parent. This is not an inference from
absence — koto's own engine source states it as a design fact, and shirabe's own
pattern reference states it in prose for the first binding.

All paths below are relative to the shirabe worktree
`/home/dgazineu/dev/niwaw/tsuku/tsuku+scope_koto_adoption-5e77c59f/public/shirabe/.claude/worktrees/docs+scope-koto-adoption`
unless prefixed with `koto:`, which means
`/home/dgazineu/dev/niwaw/tsuku/tsuku+scope_koto_adoption-5e77c59f/public/koto/`.

## Findings

### 1. What happens when the parent reaches a materialized child

`skills/execute/` was read end to end: `SKILL.md` (773 lines),
`koto-templates/execute.md` (649), `koto-templates/execute.mermaid.md`,
`references/cross-issue-context.md`, `requires.tsv`, all four `scripts/`, and
`evals/evals.json` plus every fixture. The complete set of `koto next` call sites
in the skill is two, both against the parent's own session:

- `skills/execute/koto-templates/execute.md:475` — `koto next {{SESSION_NAME}} --with-data @"$TMP"` (Tick 1, submits `tasks`)
- `skills/execute/koto-templates/execute.md:516` — the same call again (Tick 2, submits `tasks` + `batch_outcome`)

Between them, the template's entire account of the child hand-off is one sentence
at `execute.md:479`:

> koto materializes one child per task using `work-on.md` with `failure_policy: skip_dependents`. Children receive `SHARED_BRANCH` and commit directly to it without creating their own branches. After each child completes and before dispatching the next, run the context assembly step in `references/cross-issue-context.md`...

Tick 2 then opens at `execute.md:481` with "**Tick 2 — complete**: once all children
reach terminal states, the `batch_done` gate unblocks." The transition from "koto
materializes children" to "all children reach terminal states" is narrated as if it
happens on its own. **No instruction anywhere in `skills/execute/` says who calls
`koto next` on a child session, and no file in the directory mentions the Agent
tool, `subagent_type`, `run_in_background`, `koto session start`, `--needs-agent`,
`unassigned_children`, or `--dispatch-epoch`.** Verified by grep across
`skills/execute/**` for each of those terms: zero hits.

`skills/execute/requires.tsv` is the load-bearing negative evidence, because it is
an *enumeration*, not an absence. It declares every command `/execute` runs, and
`scripts/check-skill-requires.sh` enforces it against the skill body. The complete
koto surface it declares is:

```
koto	init	--template,--var	always
koto	next	--with-data	always
koto	context add	--from-file	always
koto	context get	-	always
koto	workflows	-	always
koto	status	-	always
```

`koto session` does not appear. The file's own header comment (lines 4-9) explains
what each verb is for: "`next` submits the tasks array and the finalization
evidence, context add/get carry the settled branch and the per-child batch view,
`workflows` inspects child outcomes, `status` reports progress." Every declared
koto call is a parent-session call. There is no declared call that advances a
child, and no declared tool that launches an agent.

**Answer to sub-question 1: nobody, explicitly.** The mechanism is implicit. The
only actor in scope is the agent already running `/execute`; it submits `tasks`,
koto writes child state files to disk, and the same agent must then tick those
child sessions itself by following `work-on.md`'s directives — but no line in the
repo instructs it to. See §6 for the one documented entry path that does exist,
and §7 for why this is a real gap rather than an omission I failed to find.

### 2. What the eval fixtures assert about child dispatch

`skills/execute/evals/evals.json` carries 35 evals. Ten are `mode: execute`
(fixture-backed end-to-end); the rest are `mode: plan_only` (the model describes
what it would do and is judged on the description).

**No eval, in either mode, asserts anything about how a child is entered, run, or
ticked.** Every rubric item that contains the word "dispatch" constrains *ordering*
or *routing*, never mechanism:

- `evals.json:109-112` — "Agent reads prior completed children's summaries via `koto context get` before dispatching the next child... Agent does NOT dispatch a new child without first assembling cross-issue context." (ordering)
- `evals.json:60-63` — "Agent runs `scripts/assert-child-template.sh` as the Step 1 cross-skill check before spawning any child... Agent halts the run on a non-zero exit rather than proceeding to spawn children." (a path-resolution precondition)
- `evals.json:79` — "Workflow routes to `escalate_upstream_drift` -> `done_blocked` (children NOT dispatched)." (a gate that prevents dispatch)

The end-to-end fixtures elide the child hand-off entirely. `evals.json:239-240`
(eval 15, `e2e-execute-happy-path`, the only full happy-path execute eval) states
the expected trajectory as:

> ...runs `plan-to-tasks.sh` on the fixture to produce tasks JSON, **submits tasks to koto. Then receives `pr_finalization` state**, reads `batch_final_view`...

Four children come into existence and reach `success` between one sentence and the
next. The fixture that supplies that jump is
`skills/execute/evals/fixtures/scenarios/e2e-plan-happy/koto-next-work-on.json`, a
single canned response for the *parent* session `execute-diamond-test` already
sitting in `pr_finalization`, paired with
`koto-context-batch-final-view.json`, which hands back four children all
`"outcome":"success"` with PR URLs. The resume scenario is the same shape:
`evals.json:274` — "Receives `spawn_and_await` state indicating 2 of 4 children are
still pending. Agent **monitors** remaining children." Monitors, not runs.

The fake koto binary confirms this by construction.
`skills/execute/evals/fixtures/bin/koto` (85 lines) is a case statement over eight
argument patterns. Its `next` arm is `*"next work-on"*|*"next"*"work-on"*` (line
38), which requires the literal string `work-on` in the arguments. Child sessions
in these fixtures are named `outline-feat-add-auth-service` and similar
(`koto-context-batch-final-view.json`), so a call of the form
`koto next outline-feat-add-auth-service` matches no arm and falls through to line
84-85: `echo "koto shim: no match for args: $ARGS" >&2; exit 1`. **The eval harness
cannot execute a child tick — any attempt to make one fails hard.**

A fixture set that never exercises a child hand-off, plus a shim that would error
if one were attempted, is affirmative evidence that no child hand-off mechanism is
under test — because there is none to test.

### 3. koto's side: `--needs-agent`, `unassigned_children`, the epoch fence

All three exist and all three are real. **None of them are used by `/execute`, and
none of them apply to a materialized child.**

**`koto session start --needs-agent`** creates a child session whose header carries
`needs_agent = Some(true)` and an empty `template_path`; it requires `--role`,
`--template`, and `--inputs` together, rejecting at parse time otherwise
(`koto:src/cli/session.rs:91-106, 316, 336`;
`koto:plugins/koto-skills/skills/koto-user/SKILL.md:206`). It spawns nothing. It
sets a marker meaning "this session is waiting for someone to send it an agent."

**`unassigned_children`** is an informational array on directive-bearing `koto next`
responses listing children that name this coordinator and carry that marker
(`koto:plugins/koto-skills/skills/koto-user/SKILL.md:78`). It is a to-do list for
the coordinator. It causes nothing to happen.

**The `--dispatch-epoch` fence** is a write-authorization check: a dispatched agent
must present the epoch baked into its spawn, validated before any persistence call,
rejected with `epoch_fence_violation` / exit 65
(`koto:plugins/koto-skills/skills/koto-user/SKILL.md:110`;
`koto:docs/reference/error-codes.md:275`). It polices *who may write*, not *who
runs*.

koto's own claims verify against source. `koto:plugins/koto-skills/skills/koto-user/SKILL.md:181`:

> A parent workflow can spawn child workflows and wait for them to finish. koto tracks the relationship but doesn't launch child agents — you do that yourself (Agent tool, subprocess, etc.).

and `:213`: "`koto request create` spawns nothing." Both are accurate. The only
non-test `std::process::Command` uses in the entire koto source tree are
`src/action.rs:33` (running a state's declared shell `default_action`),
`src/session/local.rs:1807` (a `#[cfg(test)]` re-exec inside a flock contention
test), and `src/session/version.rs:220` (`hostname`). koto launches no agents and
no child processes. `koto:docs/designs/current/DESIGN-hierarchical-workflows.md:69-72`
states it as a decision driver: "koto is a contract layer, not an execution engine.
koto doesn't launch agents."

**The decisive finding is that materialized children are not `needs-agent` children
at all, and koto's engine says why.** The batch scheduler creates children through
`init_child_from_parent` (`koto:src/cli/batch.rs:15, 1538, 1569`), which writes a
header with `needs_agent: None` (`koto:src/cli/init_child.rs:483`). That places
them outside the dispatch fence, and `koto:src/engine/epoch.rs:117-127` explains
the exclusion in a comment that answers this lead's central question directly:

> 2. Batch-spawned children of a `materialize_children` parent that have no request-store semantics (`needs_agent.is_none()` or `Some(false)`). These children are not subject to redelegation in the request-store sense; **the fence would reject legitimate in-process writes.**
>
> R43's wording is "every writer to a CHILD'S log" but the design's scope is the request-store dispatched-agent protocol. Batch children predate the request-store and have their own single-writer discipline (**the dispatched agent is the same process as the spawning batch scheduler**).

The corresponding test is named
`fence_does_not_apply_to_batch_spawned_child_without_needs_agent`
(`koto:src/engine/epoch.rs:299-310`).

The user-facing skill says the same thing in one line —
`koto:plugins/koto-skills/skills/koto-user/SKILL.md:209`:

> Omit all four to start a plain child session without a dispatch marker — **useful when the child is launched in-process by the same agent.**

That describes `/execute`'s children exactly.

The inverse case confirms the split. Ticking a *real* `--needs-agent` child directly
is an error: `koto:src/cli/mod.rs:3150-3170` raises `needs_agent_not_dispatched`
(exit 66) with the message "the coordinator must claim and dispatch this session via
the request-store protocol before it can be ticked directly." A materialized child
hits none of that guard (`needs_agent == None` fails the first conjunct), so
`koto next <materialized-child>` is a plain, permitted, unfenced call that any
process may make. koto is architecturally indifferent to which agent makes it —
which is precisely why nothing in koto creates a boundary.

The batch scheduler itself only writes files: it "extracts the submitted task list…
builds an in-memory DAG… classifies each task by reading child state files
directly… spawns ready tasks via `init_child_from_parent`"
(`koto:src/cli/batch.rs:8-16`). "Spawn" in koto's vocabulary means *create a state
file on disk*. `koto:src/cli/mod.rs:4340-4368` shows it running inline inside
`handle_next` right after the advance loop, appending a `SchedulerRan` audit event
and returning. One process, one tick, no fan-out.

### 4. `/work-on` standalone vs. `/work-on` as `/execute`'s child

Both paths run in the invoking agent's context. They differ in *entry* and in a
handful of *behavioral overrides*, not in isolation.

**Standalone** (`skills/work-on/SKILL.md:278-282`): the agent resolves the issue,
runs `koto init <WF> --template .../work-on.md --var ...` itself, submits entry
evidence `{"mode": "issue_backed", ...}`, and then runs the Execution Loop
(`skills/work-on/SKILL.md:210-221`):

> 1. Run `koto next <WF>`
> 2. If `action: "execute"` with `advanced: true` — run `koto next <WF>` again
> 3. If `action: "execute"` with `expects` — do the work described in `directive`, read any phase file it references, then submit evidence...
> 4. If `action: "done"` — report the outcome and stop.

**As `/execute`'s child**: koto's batch scheduler has already created the session
and materialized `work-on.md` into it, so `koto init` is skipped. Everything after
that is the identical loop against the identical template. The child template
carries no `--dispatch-epoch` on any of its `koto next` calls
(`skills/work-on/koto-templates/work-on.md:1059`,
`references/phases/phase-4a-scrutiny.md:60`, `phase-4b-review.md:58`,
`phase-4c-qa.md:57`, `phase-5-finalization.md:94`) — consistent with
`needs_agent: None` and inconsistent with a dispatched subagent, which koto would
require the flag from.

The documented differences between the two paths are all behavioral, and they are
enumerated at `skills/work-on/SKILL.md:143-170`: a plan-backed child skips staleness
checks, submits `status: override` instead of creating a branch when `SHARED_BRANCH`
is set, submits `pr_status: shared` to skip PR creation, and takes an `ISSUE_TYPE`
hint. None of these are context-scoping. Every one of them is the child being told
to *reuse the parent's resources* — the parent's branch, the parent's PR.

Crucially, `skills/work-on/SKILL.md:136` documents the plan-backed entry as an
argument shape on a slash-command invocation, under a heading that reads "When
invoked as `/work-on <argument>`" (`:134`):

> If `$ARGUMENTS` begins with `-- plan-backed` — **plan-backed child mode** (highest priority; the plan-level coordinator /execute is spawning this as a per-issue child workflow)

A slash-command invocation is a Skill-tool call in the current agent's context. This
is the only documented entry path into plan-backed child mode anywhere in the repo,
and it is an in-process one.

**Answer to sub-question 4: no, they run in the same kind of agent context.** A
standalone `/work-on` runs in the invoking agent's context; a materialized
`/work-on` runs in `/execute`'s agent context. Neither gets a fresh window.

### 5. The consequential question: does a boundary exist anywhere?

**No.** Neither binding provides one, and the pattern reference says so for the
first binding in as many words.

`references/parent-skill-pattern.md:496-513` defines the Dispatch Mechanism with two
Layer-2 bindings:

> - **Inline Skill-tool invocation.** The authoring parents (`/scope`, `/charter`) call the Skill tool from their own agent context with the child's name and the topic slug, the same way a user typing `/<child-name> <topic-slug>` would. **The child runs in the parent's agent context** and constructs whatever team it needs at the child layer.
> - **Materialized `/work-on` runs.** `/execute` submits its per-issue children to a koto session that materializes one child per issue against `/work-on`'s child template, and drives that loop rather than blocking on a single call.

The first binding is explicit: same agent context, stated at `:502`. The second says
`/execute` "drives that loop" without naming a driver — and §1-§4 establish that the
driver is the same agent, since no other actor is instructed, declared, or created.

`/scope`'s own instruction confirms the first binding is a literal slash-command
call. `skills/scope/references/phases/phase-2-chain-orchestration.md:166-194`
invokes each child as `/brief <topic-slug>`, `/prd docs/briefs/BRIEF-<topic>.md`,
`/design docs/prds/PRD-<topic>.md`, `/plan docs/designs/DESIGN-<topic>.md`, and
notes at `:193-199` that "these are input modes each child already ships…
equally usable by an author invoking either directly." Grep across
`skills/scope/`, `skills/charter/`, `skills/execute/`, and `skills/work-on/SKILL.md`
for `subagent_type`, `Agent tool`, and `run_in_background` returns **zero hits**.

The most direct evidence in shirabe's own prose is a file whose *name* claims the
opposite of what its *body* says. `references/fixes/sub-agent-dispatch.md` is
"Sub-Agent Dispatch Fallback Resolution," dereferenced by each child's Phase 0
sentinel detection. Its first fallback shape, at `:52-59`:

> ### 1. Serial-self-jury
> When the child's normal flow spawns a multi-reviewer jury in parallel (e.g. `/design`'s Phase 6 architecture + security + structural-format reviewers), and the dispatch context does not support parallel sub-agent spawns, **the child runs each reviewer serially within the same process**, preserving the rubric set but losing parallelism.

A genuinely separate child agent would have its own Agent-tool budget and could
spawn its own parallel jury. This shape exists precisely because the child is
*inside* the parent's context and cannot. Its second shape,
Parent-delegated-approval (`:64-71`), has the same tell: the child cannot prompt the
author because "the parent chain owns the unified prompt at the chain boundary" —
one shared conversation with one user, not two isolated contexts.

The `parent_orchestration:` sentinel is described the same way. `SKILL.md:420` says
it is written "before a child is dispatched **via the Skill tool** and cleared
immediately on hand-back," and `references/parent-skill-state-schema.md:256` says
the parent writes it "before invoking the child via the Skill tool; the child reads
it at its own Phase 0." A sentinel passed through a *file on disk* is the shape you
build when you cannot pass arguments into a fresh context — and the fact that the
child can read the parent's `wip/` state file at all is itself a shared-filesystem,
shared-context arrangement.

So the claim at `references/parent-skill-pattern.md:521-528` that isolation is
"preserved by construction under both" bindings is accurate but is about something
else entirely. Read it carefully:

> R14 child-isolation is preserved by construction under both. The parent reads only the child's durable artifact… **The Skill tool gives the parent no privileged view into the child's internals**…

R14 is a *discipline* about which surfaces the parent is permitted to read
(`:580-590`: "The parent SHALL NOT inspect the child's internal team coordination,
the child's inbox, the child's `wip/` state"). It is a rule the agent follows, not a
runtime partition. It constrains what the parent *should* look at; it does not
create a window the parent *cannot* see into. Under both bindings the parent and
child share one context window, so every token the child produces is already in the
parent's context whether the parent "inspects" it or not.

**This is the stronger disposition the lead asked for.** It is not that binding two
would buy nothing for `/scope`. It is that *no context boundary exists anywhere in
this repo at a chain-child hop*, so there is nothing for `/scope` to adopt. The
"fresh child context per hop" attributed to koto does not exist under either
binding, and the claim at `execute.md:428-430` that "the coordinator stays thin by
delegating each issue to a fresh `work-on.md` child and reading only status, so its
context lasts the whole run" is **false as written**. "Fresh" describes the child's
*koto session state* — a new state file with its own event log and context store —
not a fresh agent context. The session is fresh; the context window is the same one.

### 6. Where boundaries DO exist (and why they are not the hop)

Agent-tool dispatch is used extensively in this repo — just never at a chain-child
hop. Every use is a *disposable helper inside a single skill*, whose findings return
as a summary:

- Jury reviewers: `skills/strategy/references/phases/phase-4-validate.md:45`, `skills/brief/.../phase-4-validate.md:47`, `skills/design/references/phases/phase-6-final-review.md:23`, `skills/prd/.../phase-4-validate.md:36`, `skills/roadmap/.../phase-4-validate.md:25`, `skills/vision/.../phase-4-validate.md:25`, `skills/comp/.../phase-4-validate.md:23`
- Research agents: `skills/explore/references/phases/phase-2-discover.md:127`, `skills/decision/references/phases/phase-1-research.md:19`, `skills/design/references/phases/phase-2-execution.md:28`
- Decision validators: `skills/decision/references/phases/phase-3-bakeoff.md:14`
- Issue-generation agents: `skills/plan/references/phases/phase-4-agent-generation.md:209-215`
- `/work-on`'s own analysis and review panel: `skills/work-on/references/phases/phase-3-analysis.md:19`, `phase-4a-scrutiny.md:7`, `phase-4b-review.md:7`, `phase-4c-qa.md:7`

So the repo knows exactly how to create a context boundary and does so routinely for
leaf work. It has simply never applied that mechanism to the parent→child hop. The
capability is present; the application at the hop is absent. That distinction
matters for the exploration: adopting a real per-hop boundary would be *new
construction*, not adoption of an existing koto affordance.

## Implications

**The claimed secondary win does not exist.** "A fresh child context per hop" is not
something koto provides, not something `/execute` implements, and not something any
skill in this repo does at a chain boundary. If `/scope` adopts koto, it gets
instruction sequencing and gating — the established primary win — and nothing else.
Any exploration option whose case rests partly on context isolation is resting on
nothing, and the two koto bindings are equivalent on this axis rather than one
being better.

**This sharpens the framing of issue #331.** The failure mode — an agent following
`/scope`'s structure, producing only the terminal PLAN, and asserting the upstream
artifacts away in prose — is a *single agent accumulating its own reasoning across
all four hops in one context window*. That is the actual runtime today, not a
deviation from it. The agent asserted the upstream artifacts away because it had
been reasoning about them continuously and its own prose was as available to it as
any instruction. A boundary would plausibly help with exactly this, but no such
boundary exists to turn on, under koto or otherwise. Framing #331 as "koto would
have prevented this via fresh contexts" would be wrong on the mechanism.

**Two documentation defects are now established as fact, not suspicion.**
`skills/execute/koto-templates/execute.md:428-430` (and its restatement at
`skills/execute/SKILL.md:641`) asserts a context-budget property the implementation
does not deliver. And `references/fixes/sub-agent-dispatch.md` is named for a
mechanism its own body documents workarounds for the *absence* of. Both would
mislead a future reader reasoning about `/execute`'s context behavior — which is
precisely what happened to whoever attributed the fresh-context win to koto in the
first place.

**A separate, more serious gap surfaced.** See Surprises.

## Surprises

**Nothing in the repo instructs anyone to tick a materialized child, and that looks
like a live defect rather than an omission in my search.** I grepped `skills/` and
`references/` for `koto next` (every hit is a parent-session tick or a `/work-on`
self-tick), for `drive the child`, `drive each child`, `run each child`, `tick the
child`, and `child session`. `skills/execute/requires.tsv` — an enforced
enumeration of every command the skill runs — declares no child-advancing call. The
lifted template narrates the gap between "koto materializes one child per task"
(`execute.md:479`) and "once all children reach terminal states"
(`execute.md:481`) as if it closes itself.

It does not close itself. koto's scheduler writes state files and returns
(`koto:src/cli/batch.rs:8-21`); koto launches nothing
(`koto:docs/designs/current/DESIGN-hierarchical-workflows.md:69`). Somebody has to
run `koto next <child-name>` and follow `work-on.md`'s directives, and the only
somebody available is the agent running `/execute`. The one documented on-ramp,
`/work-on -- plan-backed ...` (`skills/work-on/SKILL.md:136`), is a slash-command
form that `/execute`'s template never emits — `/execute` goes through koto's `tasks`
array instead, which produces a session but no invocation. So `/execute` has a
documented way to *create* children and no documented way to *start* them.

**The most authoritative statement about shirabe's execution model lives in koto's
Rust source, not in shirabe.** `koto:src/engine/epoch.rs:117-127` — a comment
justifying a fence exclusion — is the clearest description anywhere of how
`/execute`'s children actually run: "the dispatched agent is the same process as the
spawning batch scheduler." Nothing in shirabe states this. A reader staying inside
shirabe would find only the false claim at `execute.md:428-430`.

**The eval shim would hard-fail on a child tick.** `fixtures/bin/koto:84-85` exits 1
on any unmatched argument, and no arm matches a child session name. The test
infrastructure is not merely silent about child dispatch — it is structurally
incapable of it. That is stronger than "the fixtures don't cover it."

**`/execute`'s materialized binding passes children *more* shared context, not
less.** `skills/execute/references/cross-issue-context.md` exists specifically to
concatenate every completed child's `summary.md` into each new child's context, and
insists: "Don't skip this step even when only one prior child has completed."
`evals.json:111` makes it a rubric item. On top of a shared context window, this is
deliberate additional sharing. (This confirms rather than adds to what the prior
exploration established.)

## Open Questions

1. **Does `/execute` work at all today, and if so how?** If no instruction tells the
   agent to tick children, either (a) agents infer it from `work-on.md`'s directives
   appearing in the `koto next` response and it works by luck, (b) the missing tick
   is a real bug and single-pr `/execute` runs stall at `spawn_and_await`, or (c)
   there is a runtime affordance outside these files — a koto hook, plugin config,
   or harness behavior — that I did not search. I searched the shirabe skill tree,
   koto's `src/`, `docs/`, and `plugins/koto-skills/`. I did not search niwa or the
   plugin marketplace configuration. **This needs a human who has watched a real
   `/execute` run to say which.** It does not change this lead's disposition either
   way — under (a) and (b) alike there is no boundary — but it is a potentially
   serious defect that surfaced incidentally.

2. **Should the two false-to-misleading documentation sites be corrected as part of
   this work, or filed separately?** `execute.md:428-430` / `SKILL.md:641` (the
   context-budget claim) and `references/fixes/sub-agent-dispatch.md` (the name).
   Both are outside `/scope`'s scope but both actively propagate the belief this
   lead just falsified.

3. **Is a real per-hop boundary wanted?** The repo has the mechanism (Agent tool,
   used in a dozen places for leaf helpers) and has simply never applied it at a
   chain hop. Whether that is a deliberate choice — parents need conversational
   continuity with the author across hops, which a fresh context destroys — or an
   unexamined default, is not answerable from the files. The pattern reference
   asserts isolation is "preserved by construction" under both bindings
   (`parent-skill-pattern.md:524`), which suggests the authors considered R14
   discipline sufficient and did not see a runtime boundary as missing. **A design
   question for a human, not a research question.**

## Summary

No context boundary exists anywhere in this repo at a chain-child hop: `/scope`'s
children run in the parent's agent context by explicit statement
(`references/parent-skill-pattern.md:502`), and `/execute`'s koto-materialized
children are created with `needs_agent: None` (`koto:src/cli/init_child.rs:483`),
which koto's engine excludes from the dispatch fence precisely because "the
dispatched agent is the same process as the spawning batch scheduler"
(`koto:src/engine/epoch.rs:117-127`) — so the claim at
`skills/execute/koto-templates/execute.md:428-430` that the coordinator stays thin
via "a fresh `work-on.md` child" is false, since the koto *session* is fresh but the
context window is not. The implication is that the secondary win attributed to koto
does not exist under either binding, the two bindings are equivalent on isolation,
and issue #331's failure mode — one agent accumulating its own reasoning across all
four hops — is the actual runtime today with no existing boundary available to fix
it. The biggest open question is incidental but sharp: nothing in `skills/execute/`
instructs anyone to tick a materialized child, `requires.tsv` declares no
child-advancing call, and the eval shim would hard-fail on one — so whether
single-pr `/execute` completes today by inference, by an affordance outside these
files, or not at all, needs a human who has watched a real run.
