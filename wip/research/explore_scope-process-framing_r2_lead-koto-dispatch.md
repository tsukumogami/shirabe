# Lead: Would koto-materialized dispatch for `/scope` create the boundary the sourcing property needs?

Round-2 lead. Paths relative to `public/shirabe/` unless noted; shared
references resolve at
`/home/dgazineu/.claude/plugins/cache/shirabe/shirabe/0.18.1-dev/`
(`${CLAUDE_PLUGIN_ROOT}`), koto's plugin skills at
`/home/dgazineu/.claude/plugins/cache/koto/koto-skills/0.11.5-dev/`,
koto's own docs at `public/koto/docs/`.

## Findings

### 1. The Layer-1 mechanism is already key-passing, under both bindings

`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md:495-497` states
the substrate-agnostic element:

> The Layer-1 element is that a parent hands a child a name and a topic
> key and then waits on it, owning no team of its own at the parent layer.

That sentence is the whole answer in miniature. The pattern defines
dispatch — under *either* binding — as handing over a **name and a topic
key**. Neither binding was designed to carry an artifact across the
boundary, and neither withholds one. A second binding cannot supply a
property the Layer-1 element does not name.

The two Layer-2 bindings (`:499-510`):

- **Inline Skill-tool invocation** (`:499-504`) — `/scope` and `/charter`
  call the Skill tool from their own agent context with the child's name
  and the topic slug, "the same way a user typing `/<child-name>
  <topic-slug>` would". The child runs in the parent's agent context.
- **Materialized `/work-on` runs** (`:505-510`) — `/execute` submits
  per-issue children to a koto session that materializes one child per
  issue against `/work-on`'s child template, and drives that loop rather
  than blocking on a single call.

What the second binding guarantees that the first does not is **drive
shape, not payload shape**: durable resumable state, N-way fan-out with a
`waits_on` dependency DAG and `failure_policy: skip_dependents`, and
aggregate outcome routing. The pattern is explicit that isolation is
*equal* under both (`:521-528`): "R14 child-isolation is preserved by
construction under both... a materialized child is reached through the
same durable surfaces plus `gh` metadata on the child's own pull
request." The pattern does not claim the materialized binding isolates
more; it claims it isolates the same.

### 2. The concrete payload a materialized child receives is a pointer, not a document

`skills/plan/scripts/plan-to-tasks.sh:6` documents the emitted shape:

```
# Each object has the shape: {"name":"...","vars":{...},"waits_on":[...]}.
```

The `vars` objects it actually emits (`:373`, `:721`, `:728`):

- github-issue mode: `{ISSUE_SOURCE, ISSUE_NUMBER}`
- plan-outline mode: `{ISSUE_SOURCE, ARTIFACT_PREFIX}` (+ `ISSUE_TYPE`
  when the PLAN supplies one)

`skills/execute/koto-templates/execute.md:474` then adds one more var by
jq: `TASKS_WITH_BRANCH=$(echo "$TASKS" | jq --arg b "$SETTLED_BRANCH" '[.[] |
.vars.SHARED_BRANCH = $b]')`.

So a materialized `/work-on` child receives, in total: an issue number or
an artifact prefix, a source enum, an optional type hint, and a branch
name. Four strings. No document content. koto's own batch reference
confirms this is the whole surface — `${CLAUDE_PLUGIN_ROOT}`-adjacent
`koto-skills/.../koto-author/references/batch-authoring.md:44-56` shows
the task entry as `{"name": ..., "vars": {"ISSUE_NUMBER": "101"},
"waits_on": [...]}` and nothing else; children get composed names
`<parent>.<task>`.

**The child sources its own upstream.** `skills/work-on/koto-templates/work-on.md`,
`plan_context_injection` prose:

> - If ISSUE_SOURCE is `github`: read the GitHub issue with `gh issue view
>   $ISSUE_NUMBER` and write it to koto context as `context.md`.
> - If ISSUE_SOURCE is `plan_outline`: the PLAN doc is already available via
>   the PLAN_DOC variable. Extract the specific issue outline from the PLAN
>   doc and write it as `context.md`.

The child is handed a key and goes and fetches the artifact itself, from
GitHub or from the working tree. That is structurally identical to what
`/scope` does today: hand a path, let the child read the file.

The one place a parent *deposits* content into a child is
`skills/execute/references/cross-issue-context.md`, which concatenates
completed siblings' `summary.md` and writes it into the new child with
`koto context add <new-child-name> current-context.md --from-file`. Note
the direction of travel: the materialized binding gives children **more**
context than the inline one, not less, and deliberately so.

### 3. koto does not launch child agents

`koto-skills/0.11.5-dev/skills/koto-user/SKILL.md`, "Hierarchy":

> A parent workflow can spawn child workflows and wait for them to finish.
> koto tracks the relationship but doesn't launch child agents — you do
> that yourself (Agent tool, subprocess, etc.).

This is the single most important fact for the lead. "Materialized
dispatch" does not mean koto forks a fresh agent. koto creates a child
*session* — a state file and a context namespace — and blocks the parent's
`children-complete` gate until those sessions reach terminal states.
Whether a child runs in a fresh agent context is decided entirely by
whoever calls `koto next <child>`, which is a human or an agent, not koto.

koto does ship a marker for this (`koto session start --needs-agent
--role --template --inputs`, plus the `unassigned_children` array on every
directive-bearing `koto next` response, plus a `--dispatch-epoch` fence on
child write-backs). But those record *that a child wants an agent* and
police *which* agent may write back. They spawn nothing:
"`koto request create` spawns nothing", "A request is a container, not a
spawner".

`/execute`'s template asserts the coordinator "stays thin by delegating
each issue to a fresh `work-on.md` child and reading only status, so its
context lasts the whole run" (`skills/execute/koto-templates/execute.md:428-430`).
I could not find the instruction that makes that true. `grep -rn "koto
next" skills/execute/` returns exactly two hits, both
`koto next {{SESSION_NAME}}` — the parent's own session (`execute.md:475`,
`:516`). Nothing in `skills/execute/` mentions the Agent tool, a subagent,
`--needs-agent`, or `unassigned_children`. The freshness of the child
context under today's second binding is an authoring claim I can see
stated but not a mechanism I can see shipped. See Open Questions.

### 4. koto's context model can enforce sequencing, but not ignorance

Does koto let a step receive *only* what the previous step deposited?

**Partly yes, as a gate.** `koto-author/references/template-format.md:277-288`
declares two store-backed gate types:

| `context-exists` | A key exists in the context store | `key` |
| `context-matches` | Content for a key matches a regex | `key`, `pattern` |

`public/koto/docs/guides/cli-usage.md:425-437` gives the CLI equivalent
(`koto context exists <name> <key>`, exit 0/1). A template can therefore
make state N un-advanceable until state N-1 deposited a named key, and
koto — not the agent's good intentions — evaluates it. `/work-on` already
uses exactly this: `work-on.md:77-81` gates `context_injection` on
`context-exists: context.md`. `template-format.md:758` even recommends
these gates over `command` gates because they don't invoke a shell.

**But not as an information barrier.** The store is per-session, keyed by
session name and key, and "All content is stored opaquely by koto"
(`cli-usage.md:377`); any agent with the CLI can `koto context get` any
session's key. More decisively, the child is an agent with a filesystem.
Nothing in koto withholds `docs/designs/DESIGN-<topic>.md` from a child
that decides to read it. koto can make a *step* refuse to advance. It
cannot make an *agent* hold nothing.

### 5. The crux: the boundary withholds nothing that isn't already withheld

Under a materialized binding, `/scope` would submit tasks whose `vars`
carry the topic slug or the slug-derived path
`docs/designs/DESIGN-<topic>.md`
(`skills/scope/references/phases/phase-2-chain-orchestration.md:183-187`).
Round 1 established that path is a Phase-0 constant computable from the
slug alone. Template vars are strings the parent chooses; koto does not
audit their provenance. A `/scope` run that skipped `/design` could emit
that exact var, and koto would materialize the child with it.

What actually differs when a hop is skipped is that **no file exists at
the path** — and that is equally true today under inline dispatch. The
child then hits `/plan`'s Input Mode 3 (`skills/plan/SKILL.md:256-258`):

> 3. **Anything else** -- treat as a direct topic (input_type: topic). No
>    upstream document is required.

which is a deliberate, documented degradation, not a failure. So: **the
dispatch binding is not what stands between `/scope` and the sourcing
property, and changing it would not deliver the property.** The property
fails on the child's Input Modes, one layer below the binding, exactly
where round 1 left it.

**What a materialized binding *would* reach** is the weaker guarantee the
lead named: a `context-exists` gate on a `plan` state, keyed on something
the `design` state deposits, makes the *parent* unable to reach its
terminal state having skipped a hop. That is "the parent cannot skip a hop
and still produce a coherent run" — real, mechanical, and machine-checked.
It says nothing about what the child holds.

And note that guarantee is already asserted in the inline binding, just
softer. `phase-2-chain-orchestration.md:38-77` lists an eight-step
per-child loop whose step 4 is the **R20 structural file-existence check**
("Confirm the child's canonical durable artifact exists after the child
returns", detailed at `:266`), with step 7 a validator pass-through that
"halts the chain" on violations, and per-child gates driven from
`planned_chain:` rather than re-walked (`:760`). So moving to koto would
convert an agent-honored precondition into a machine-evaluated one. That
is an **enforcement-hardness delta on a property `/scope` already
asserts**, not a new property — and specifically not the sourcing
property.

### 6. One documentation inconsistency worth recording

`parent-skill-pattern.md:657-658` says, in the team.yaml v1 read-semantics
paragraph: "The substrate has no team.yaml parser; the inline Skill-tool
dispatch mechanism passes only the topic-slug argument." Taken literally
that contradicts `phase-2-chain-orchestration.md:174-187`, whose table
passes `docs/briefs/BRIEF-<topic>.md`, `docs/prds/PRD-<topic>.md`,
`docs/designs/DESIGN-<topic>.md` and an optional `--upstream <roadmap-path>`.
In context the pattern is only making the point that team.yaml does not
cross; but the sentence as written understates what `/scope` actually
hands its children, and anyone reasoning about the payload from the
pattern alone will get it wrong.

## Implications

**The proposal is a category error, and cleanly so.** The sourcing
property asks that a child *hold nothing* when a step was skipped. Both
dispatch bindings are defined — at Layer 1, in the pattern's own words —
as handing over a name and a topic key. Neither carries artifacts;
therefore neither can withhold one. Switching bindings changes how the
parent waits, not what the child gets. The honest disposition for the
crystallized outcome is not "would need mechanism" but "the mechanism
usually reached for is the wrong axis": the sourcing property lives in
the children's Input Modes, and the repo deliberately keeps those open
(round 1's `CLAUDE.md`, `skills/scope/SKILL.md:508-517`,
`phase-1-discovery.md:38-42`).

**A real but different guarantee is reachable.** koto's `context-exists`
gate would let `/scope` express "this hop cannot advance until the
previous hop deposited its artifact" as something koto evaluates rather
than something an agent is told to check. That is worth naming in the
outcome as the thing that *is* buyable, precisely so it isn't confused
with the thing that isn't. It hardens `/scope`'s own sequencing; it does
not constrain a child, and it does not touch standalone child entry, which
is the case #331's sourcing property was really aimed at.

**The gap the second binding actually closes is fan-out.** `/execute` has
N independent children with a dependency DAG and needs skip-dependents
semantics and resumable per-child state. `/scope` has four children in a
fixed linear order with an author in the loop. The pressure that produced
the second binding does not exist at `/scope`.

## Cost

Costed as if someone decided to do it anyway. Roughly descending.

**1. Four new koto templates for children that have none.** This is the
dominant cost and it is structural, not incidental. `/execute` could adopt
the materialized binding cheaply because `/work-on` already shipped
`work-on.md` (43KB). `/scope`'s children ship nothing: `grep -rn -i koto
skills/scope/` is empty, and `koto-templates/` exists only under
`skills/work-on/` and `skills/execute/`. koto's compile rules make this
unavoidable — E9 requires `default_template` to resolve to a *compilable*
template, and F5 requires every child template to declare a reachable
`skipped_marker: true` terminal (`batch-authoring.md`, rules table). So
`/brief`, `/prd`, `/design`, `/plan` each need a state machine authored
over a skill that is today 900-2700 lines of conversational prose. Anything
short of that collapses back to invoking the child by name inline — i.e.
back to binding one.

**2. Re-expressing the eight-step per-child loop as states.**
`phase-2-chain-orchestration.md:38-77`. Some steps map cleanly (R20 →
`command` or `context-exists` gate; validator pass-through → `command`
gate; sentinel write/cleanup → `context_assignments`). One does not:
**Consolidation judgment** (`:488-760`, ~270 lines) is a three-stage
reasoning step — citation preflight, judgment, compose/verify/move/
re-validate — with rollback, a judgment-entry format, an explicit "no
durable-artifact floor" clause, and cascade-across-hops behavior. It can be
*routed* by an evidence enum (`keep | absorb`), but the prose still has to
live in a state's directive, and it now has to survive being read by an
agent that did not have the Phase-1 conversation.

**3. Dual state.** `/scope` keeps `wip/<parent>_<topic>_state.md`
(255-line schema at `skills/scope/references/state-schema.md`) and would
add a koto session. `/execute` already lives with exactly this — its
SKILL describes "a wip-yaml-md state projection over the durable home PR"
(`skills/execute/SKILL.md:122`) — so the pattern is proven, but it is two
sources of truth to keep reconciled.

**4. The resume ladder.** `skills/scope/references/phases/phase-resume.md`
is 360 lines: Slot 5 status-aware re-entry (9 rows, most-downstream-first),
Slot 6 partial-child-run (4 rows), Slot 7 the `/explore` feeder handoff,
plus recorded-upstream re-validation and drift detection. Every row is
keyed on artifact status on disk. A koto session introduces a second
resumption axis (`koto next` on a live session) that has to be reconciled
with all of it. `/execute` solved the analogous problem by making resume a
topic-keyed home-PR lookup that re-inits with a flipped
`PAUSE_BEFORE_FINALIZE` (`SKILL.md:261-268`); `/scope` has no PR to key
on mid-Phase-2, so that solution does not transfer.

**5. Pattern text.** Less than feared. `parent-skill-pattern.md:519-522`
already says the four remaining elements "are written against the inline
binding because it came first; where they name the Skill-tool call, read
it as the dispatch under whichever binding the parent uses" — the pattern
anticipated a second parent adopting binding two. What *would* need
editing: the Observability Surface (`:570-590`) enumerates "durable
artifact path polling", `git log` since `pre_invocation_sha`, and the
parent's own `wip/`, and says "nothing else"; a koto-driven `/scope` also
reads `koto workflows` and `batch_final_view`, which the surface would
have to name for `/scope` the way `:527-528` names it for `/execute`. The
Hand-Back Contract's seven steps (`:594-620`) survive as-is; they key on
the artifact, not on the call's return.

**6. Evals.** `skills/scope/evals/evals.json` is 478 lines of prose-level
assertions. `/execute` ships a whole koto fixture apparatus for its
binding — `evals/fixtures/bin/koto` (a fake binary), plus
`koto-next-work-on.json`, `koto-context-batch-final-view.json`,
`koto-workflows.json` across four scenario directories. `/scope` would
need the equivalent built from scratch.

**7. A cross-skill template-path assertion per child.** `/execute` ships
`scripts/assert-child-template.sh` specifically because the cross-skill
template reference is load-bearing and fragile (`SKILL.md:735-736`).
`/scope` would acquire four such edges.

**8. The compatibility problem, which is the one that actually decides it.**
`/execute` drives *issues*: a list computed once by a script from a
document, with no author in the loop — its `--auto` mandate is explicitly
"do NOT pause between children to advise a checkpoint" (`execute.md:424-432`).
`/scope` drives a *conversation*: Phase 1 discovery is 563 lines of author
dialogue that decides `planned_chain:`, and the inline binding is what
lets that conversation reach each child, because "the child runs in the
parent's agent context" (`parent-skill-pattern.md:502-503`). Under
materialization the child is a separate session; everything the author
said that was not written to a document would have to be serialized into
the child's koto context first. koto has the mechanism — it is precisely
what `cross-issue-context.md` does — but the content does not exist as a
file today, and manufacturing it at each hop is a new obligation on every
hop of every run. That is not a porting cost; it is a change to what
`/scope` is. (The "child sees the conversation" claim is inference from
"runs in the parent's agent context", not from an explicit statement that
the transcript is visible — flagged as such.)

## Surprises

**koto does not launch agents.** `koto-user/SKILL.md` states it flatly:
"koto tracks the relationship but doesn't launch child agents — you do
that yourself." Everyone reading "materialized dispatch" hears "koto forks
a fresh agent per issue". It does not. It creates a state file and a
context namespace and gates the parent until they go terminal. The context
boundary people attribute to the second binding is not koto's to give.

**The materialized binding passes more to children, not less.**
`cross-issue-context.md` exists specifically so each `/execute` child sees
what its predecessors found: "Don't skip this step even when only one
prior child has completed." If anyone reaches for binding two hoping to
starve children of context, the shipped reference does the opposite on
purpose.

**The Layer-1 element already concedes the point.** The mechanism is
defined as handing over "a name and a topic key" (`:495-497`). The
sourcing property was never in scope for the dispatch contract at either
layer — this is not an omission the second binding could repair.

**Nothing in `/execute` says who ticks a child.** Two `koto next` calls
ship, both on the parent's own session. No Agent-tool call, no
`--needs-agent`, no `unassigned_children` handling anywhere in
`skills/execute/`. The "fresh child" property is asserted at
`execute.md:428-430` and not implemented in any text I could find.

**`/plan` already ships a `plan-to-tasks.sh`.** If `/scope` ever did move,
the artifact-to-task-list translation for its terminal hop exists. It is
also 1000+ lines of bash whose own header says "a thousand lines of graph
contraction and topological ordering is not what shell is for" — worth
knowing before treating it as a free reuse.

## Open Questions

1. **Who drives `/execute`'s children today?** If it is the same agent
   calling `koto next <child>` in-process, then binding two provides no
   context boundary either, and the boundary being discussed for `/scope`
   does not exist anywhere in the repo. If it is a dispatched subagent,
   the instruction that dispatches it is not in `skills/execute/` and I
   could not find it. Answering this changes the framing from "the
   boundary would buy nothing for `/scope`" to "there is no such boundary
   at all" — a stronger and cleaner disposition. Someone with a live
   `/execute` run can settle it in one look at the transcript.

2. **Would a `context-exists` sequencing gate be worth wanting on its own
   merits, independent of #331?** It is the one real thing this
   investigation found buyable. It is out of scope for #331 by the
   author's ruling, and I am not proposing it — but it is a coherent
   standalone question about `/scope`'s hop discipline, and it should not
   be lost by being answered "no" as part of a question it wasn't asked
   under.

3. **Does the `:657-658` / `phase-2:174-187` payload inconsistency matter
   to anyone downstream?** It is a one-sentence fix in the pattern, and
   it sits in the exact paragraph a reader would consult to learn what
   crosses the boundary.

## Summary

Moving `/scope` to the materialized binding would not create the boundary the sourcing property needs, because neither binding carries artifacts: the pattern's own Layer-1 mechanism is "a parent hands a child a name and a topic key" (`parent-skill-pattern.md:495-497`), a materialized child's payload is four strings (`plan-to-tasks.sh:373/721/728` plus `SHARED_BRANCH` at `execute.md:474`), and the child sources its own upstream by fetching it (`work-on.md` `plan_context_injection`) — exactly what `/scope`'s children already do. The `/plan` child would still get the slug-derived path, still find no file when a hop was skipped, and still degrade to Input Mode 3's "No upstream document is required" (`skills/plan/SKILL.md:256-258`), so the boundary withholds nothing; koto's `context-exists` gate could make the *parent* unable to skip a hop and still finish, which is the weaker guarantee the lead anticipated and is an enforcement-hardness upgrade on `/scope`'s existing R20 check (`phase-2-chain-orchestration.md:38-77`), not a new property.

The cost is dominated by something structural rather than incremental: `/execute` got binding two cheaply because `/work-on` already had a koto template, whereas `/scope`'s four children have none and koto's E9/F5 compile rules require one each, over skills that are 900-2700 lines of conversational prose — plus re-expressing the eight-step per-child loop including the ~270-line consolidation judgment, reconciling a koto session against a 360-line artifact-status resume ladder, and building the koto eval fixture apparatus `/execute` ships. The deciding objection is shape, not effort: `/execute` drives a script-computed issue list with no author in it, `/scope` drives a 563-line author conversation whose unwritten content reaches children only because the inline binding runs them in the parent's agent context (`:502-503`).

Two findings worth carrying into the crystallized outcome regardless of #331's disposition: koto explicitly "doesn't launch child agents — you do that yourself" (`koto-user/SKILL.md`), so the context boundary commonly attributed to materialized dispatch is not koto's to give, and nothing in `skills/execute/` names who ticks a child session (two `koto next` calls ship, both on the parent) — so the "fresh child" property at `execute.md:428-430` is asserted but not visibly implemented; separately, `cross-issue-context.md` shows the materialized binding deliberately gives children *more* context than the inline one.
