# Lead: What happens to `/scope`'s Phase 1 author conversation under a koto binding, and what actually serializes the unwritten parts?

**Headline: the prior run's "deciding obstacle" does not survive contact with
the files.** The Phase 1 author conversation is two questions with a
three-value answer at the end of it; none of its content reaches any child;
`/scope`'s children explicitly receive no conversational pre-population; the
one sibling parent that *does* pre-populate a child writes a file rather than
relying on the transcript; and `/scope` already ships a mode (`--auto`) in
which the conversation does not happen at all. Details below, with the
contradicting evidence flagged in Surprises.

---

## Findings

### 1. What the Phase 1 author conversation structurally is

Source: `skills/scope/references/phases/phase-1-discovery.md` (563 lines).

**It decides almost nothing.** The file's own opening section is titled "What
Phase 1 Decides, and What It Does Not" and answers immediately
(`phase-1-discovery.md:13-16`):

> Phase 1 decides **nothing about the size of the artifact set.**
> `planned_chain:` is `[brief, prd, design, plan]` on every run. There is no
> starting altitude to choose and no child that Phase 1 can decide is not
> worth invoking.

Restated at `:486-489`: "That list is a constant, and now literally so… Phase 1
has no input that can shorten it and no field that records a different shape."

**Author touchpoints: exactly two.**

| # | Where | What is asked | Answer shape |
|---|---|---|---|
| 1 | Discovery prompt (`:53-59`) | The framing-shift question — has the problem shape, audience, scope boundary, or success criterion changed in a way that invalidates an existing BRIEF/PRD/DESIGN? | Effectively yes/no + reason |
| 2 | Chain proposal (`:333-360`) | `Proceed / Adjust / Bail?` | Three-value enum |

`:122-124` is explicit that there is only one options block in the whole
phase: "Phase 1 offers exactly one options block, the chain proposal's
`Proceed / Adjust / Bail`, and this gate does not open a second one."
`:458-459` repeats it: "the author still answers exactly one question here."

**Everything else in the phase is machine-derivable.** Concretely:

- Child-doc discovery is five filesystem globs plus a frontmatter `status:`
  read (`:61-68`).
- The cold-start PRD projection is *keyword-driven* against the topic slug —
  the keyword list is literally enumerated: `feature`, `fix`, `migration`,
  `rollout`, `consolidation` (`:79-86`).
- Re-entry protection is a table lookup: canonical path × settled status
  (`:152-159`).
- The R6 predicates P1/P2/P3 are inspections of PRD text and the repo's
  directory tree, each with five worked positive/negative examples
  (`:207-285`). P2 in particular "cross-references the PRD's component
  mentions against the repo's existing directory structure" (`:239-241`) —
  pure filesystem work.
- R7 turns the three verdicts into a roster cardinality (`:287-301`).

**What it writes down.** `planned_chain:`, `chain_skipped:` (with a reason from
a closed vocabulary), and `child_snapshots:` (status + git blob hash +
timestamp) — `:461-531`.

**What it leaves unwritten.** I grepped: **`framing_shift` does not exist in
`skills/scope/references/state-schema.md`.** The framing-shift answer is a
phase-local variable consumed by one gate in the same phase — "The
framing-shift answer feeds R4's override for `/brief`" (`:70-72`) — and then
discarded. So is the cold-start projection, so are the P1/P2/P3 verdicts. The
file is emphatic that the last of these is deliberate (`:132-138`): the
post-`/prd` gate "records nothing in the state file… a field this gate wrote
would have no reader in `state-schema.md` to name."

**Gate placement.** Proceed advances to Phase 2 (`:364-366`). Adjust re-enters
the discovery prompt and re-emits the proposal, unbounded iterations
(`:367-377`, `:539-551`) — but **Adjust cannot change chain membership**
(`:369-371`): "`/scope`'s Adjust refines the topic and the framing; it cannot
change chain membership, because the planned chain is the same four children
on every run." The only thing Adjust can actually move is the framing-shift
answer, which can un-skip `/brief`. Bail routes to R8 (`:378-386`).

**One structural wrinkle for any state machine.** Phase 1 is not contiguous.
The "Post-`/prd` Re-evaluation Gate" (`:113-142`) lives in the Phase 1 file but
executes *after* `/prd` returns, mid-Phase-2. It is a notice, not a prompt
(`:120-121`), and records nothing — so it is a re-entrant, side-effect-free
piece of Phase 1 that a template would have to site inside the chain loop.

---

### 2. What koto offers a workflow with a human in the loop

**No gate type waits for a human.** The complete gate roster is four types
(`koto-author/references/template-format.md:288-296`):

| Type | Passes when |
|---|---|
| `context-exists` | A key exists in the context store |
| `context-matches` | Content for a key matches a regex |
| `command` | A shell command exits 0 |
| `children-complete` | All child workflows reached their completion condition |

All four are machine-checkable. There is no `human-approval` gate.

**But an interactive state is expressible, and koto ships one.** The mechanism
is the `accepts` block (`template-format.md:154-181`): the template declares
typed fields (`enum` with a closed `values` list, `string`, `number`,
`boolean`, each `required` or not), and transitions route on submitted values
with AND semantics. The compiler enforces mutual exclusivity between
conditional transitions (`:250-277`) — two transitions from one state must
differ on at least one shared field or compilation fails.

A state with an `accepts` block surfaces to the caller as
`action: evidence_required` (`:134-140`), and the caller blocks there until it
submits. koto's own user guidance repeatedly names the human as the resolver
of last resort — `koto-user/SKILL.md:68` ("escalate to the user"), `:122`,
`:155` ("Escalate to the user instead"), `:484`. So koto's model of
human-in-the-loop is: **the agent holds the conversation; koto blocks the state
until the answer arrives as typed evidence.** koto never talks to the human.

That is exactly the shape of `Proceed / Adjust / Bail`. It compiles as:

```yaml
chain_proposal:
  accepts:
    author_decision: { type: enum, values: [proceed, adjust, bail], required: true }
  transitions:
    - { target: chain_loop, when: { author_decision: proceed } }
    - { target: discovery,  when: { author_decision: adjust  } }   # self-loop back
    - { target: bail,       when: { author_decision: bail    } }
```

The Adjust self-loop is the documented `await_doc` pattern
(`template-format.md:392-405`, `:625-635`).

**The shipped precedent is `skills/execute/koto-templates/execute.md` (649
lines), and it contains three distinct human-in-the-loop shapes despite
`/execute`'s `--auto` mandate:**

1. **`paused_for_review` (`execute.md:325-338`)** — a **terminal** state, not a
   blocking one. Its comment: "a non-failure terminal reached in interactive
   mode… It is a SUSPENSION, not a termination: at the `/execute` SKILL layer
   `exit:` stays UNSET with a resumable `paused_for_review` marker." koto
   models a human pause as *end the run and resume later with a different
   variable*, not as block-and-wait.
2. **Mode-driven enum routing (`execute.md:174-190`)** — `pause_decision:
   [pause, finalize]`, where "The agent reads the `{{PAUSE_BEFORE_FINALIZE}}`
   variable and submits `pause` when it is `true` (interactive mode) or
   `finalize` when it is `false` (`--auto` mode)." This is precisely `/scope`'s
   `--auto` / `--interactive` split, expressed in a template.
3. **Escalation states with free-string capture (`execute.md:136-144`,
   `:314-323`)** — `escalate_upstream_drift` and `escalate` each declare a
   `rationale` / `failure_reason` field of `type: string, required: true`, and
   the transition carries a `context_assignments` entry that deposits the
   agent-submitted prose into the context store:
   `failure_reason: "worktree_discipline_check: upstream-drift detected (intent-changing): ${evidence.rationale}"`.

**`--needs-agent` is not a human-pause construct.** It marks a child *session*
as awaiting agent dispatch (`koto/docs/guides/cli-usage.md:852-886`;
`--role`/`--template`/`--inputs` are required companions). koto's own design
doc settles the question at
`koto/docs/designs/current/DESIGN-request-lifecycle.md:703-720` — it is about
agent-to-agent delegation, orthogonal to anything human-facing.

**The one real constraint I found.** Template `--var` values are validated
against an allowlist: "letters, digits, `. _ - /`, `:`, `@`, and spaces; shell
metacharacters… quotes, backticks, and newlines are rejected"
(`template-format.md:747-751`). **Conversational prose cannot ride `--var`** —
no newlines, no punctuation. Prose has exactly two channels: `koto context add`
(opaque content, from stdin or `--from-file`,
`cli-usage.md:376-400`) and a `type: string` accepts field routed through
`context_assignments`. Note that `context_assignments` is **not documented in
`template-format.md` at all** — it appears only in
`koto-author/references/batch-authoring.md:89`, in the batch design doc, and in
engine source (`koto/src/template/types.rs:1219-1242`). That is an
underdocumented surface a template author would have to reverse-engineer.

---

### 3. What would write conversational content into a child's koto context

`skills/execute/references/cross-issue-context.md` is **15 lines total**. In
full, the mechanism is:

```bash
rm -f current-context.md
for child in <completed-child-names>; do
  koto context get "$child" summary.md >> current-context.md
done
koto context add <new-child-name> current-context.md --from-file current-context.md
```

So: a collect half (`koto context get` from every completed child's
`summary.md`) and a deposit half (`koto context add` into the next child's
session, keyed `current-context.md`). Its stated purpose is "awareness of what
prior children found, decided, or changed" (`:15`).

**What would be different for `/scope`, precisely — four things:**

1. **The collect half has no source.** `/execute`'s children are koto sessions
   that write `summary.md` into their own koto context. `/scope`'s children
   write durable Markdown to `docs/` and read the parent state file off disk;
   none of them touches a koto context store. Only the deposit half transfers.
2. **The content would be author prose, not child summaries.** `/execute`
   assembles machine-collected child output. `/scope` would be depositing what
   the author said. Nothing in koto objects — `context add` is opaque — but it
   is a different provenance, and it is the half that has no existing writer.
3. **Homogeneous vs. heterogeneous children.** `/execute` materializes N
   children against one template (`work-on.md`). `/scope` has four *different*
   children, and **none of `/scope`, `/charter`, `/brief`, `/prd`, `/design`,
   or `/plan` ships a `koto-templates/` directory** — only `skills/execute/`
   and `skills/work-on/` do. A materialized `/scope` binding would need four
   new child templates before `context add` had a session to add to. That is
   the real porting cost, and it is a template-authoring cost, not a
   conversational one.
4. **A `context-exists` gate becomes available on the deposit.** That is the
   gating win the exploration already established, and it applies to the
   deposited conversation the same way it applies to an artifact.

---

### 4. Testing the transcript claim — it is stated, and it is not the channel

**The cited sentence is real.** `parent-skill-pattern.md:499-504`:

> **Inline Skill-tool invocation.** The authoring parents (`/scope`,
> `/charter`) call the Skill tool from their own agent context with the child's
> name and the topic slug, the same way a user typing `/<child-name>
> <topic-slug>` would. **The child runs in the parent's agent context** and
> constructs whatever team it needs at the child layer.

So the prior run's citation is accurate as to what the sentence says. But the
sentence describes where the child *executes*, not what it *consumes*, and the
rest of the corpus says the child consumes nothing from the transcript.

**The actual parent→child channel is three named things, all durable:**

1. **argv.** `phase-2-chain-orchestration.md:166-192` gives the complete table:
   `/brief` gets `<topic-slug>` (plus `--upstream <roadmap-path>` iff
   `consumed_upstream:` is set); `/prd` gets
   `docs/briefs/BRIEF-<topic>.md`; `/design` gets `docs/prds/PRD-<topic>.md`;
   `/plan` gets `docs/designs/DESIGN-<topic>.md` (plus `--upstream`).
   `:194-201` adds: "These are input modes each child already ships… Passing
   the path is choosing among a child's shipped modes, not extending its input
   surface."
2. **The durable artifact at that path.**
3. **The `parent_orchestration:` sentinel block**
   (`phase-2-chain-orchestration.md:145-160`), three fields:
   ```yaml
   parent_orchestration:
     invoking_child: brief | prd | design | plan
     suppress_status_aware_prompt: true
     rationale: fresh-chain | revise
   ```

**`rationale:` is the entire author-intent bandwidth to a child, and it is a
two-valued enum.**

**And the child does not read a transcript — it globs the filesystem.**
`skills/design/references/phases/phase-0-setup-prd.md:37-43`:

> Before applying the hard-stop status check below, look for the
> `parent_orchestration:` sentinel block. **Read any `wip/*_<topic>_state.md`
> file matching the current topic** (glob pattern, not a hardcoded
> `wip/scope_<topic>_state.md` — the glob keeps the branch
> forward-compatible with future parent skills beyond `/scope`).

That is a deliberately parent-agnostic, file-based channel — designed so the
child works under *any* parent, including one that is not in its context.
`skills/plan/references/phases/phase-1-analysis.md:44` and
`skills/prd/SKILL.md:117` do the same thing.

**So: is it explicitly stated that the child sees the parent's transcript?** No.
The strongest statement is `:502-503`, which says the child *runs in* the
parent's context — a true fact about the Skill tool that makes the transcript
*available*. That the children *depend on* it is inference, and the children's
own files contradict it (next section). The one place the pattern discusses
what crosses the boundary is `:524-530`, and it is about the *opposite*
direction: "The parent reads only the child's durable artifact… never inspects
the child's `wip/` state, the child's inbox, or any sub-team the child spawns."

---

### 5. (a) the parent conversation vs. (b) what children need from it

**(b) is empty, and one of the children says so in one sentence.**

`skills/prd/SKILL.md:127-129`:

> The `wip/prd_<topic>_scope.md` row is a partial-run row, not a handoff row.
> Its only producer is this skill's own Phase 1 — **`/scope` pre-populates
> nothing for `/prd`; it invokes `/prd` and lets Phase 1 do the scoping.**

`/prd` holds its own author conversation and is emphatic about it:
"**Conversational First**: Phase 1 is a dialogue, not a form to fill out"
(`prd/SKILL.md:139`); "**User Review**: Never finalize a PRD the user hasn't
reviewed and given feedback on" (`:141`).

Two more confirmations that (b) is empty:

- **The framing-shift answer is explicitly re-asked downstream.**
  `phase-1-discovery.md:88-94`: on an empty cold start, "the framing-shift
  answer is deferred to the BRIEF authoring conversation." The parent's answer
  isn't handed down; `/brief` asks again.
- **It isn't recorded either.** `framing_shift` appears nowhere in
  `state-schema.md` (grepped). If a child wanted it, there would be nothing to
  read.

**The contrast case proves the rule.** `/charter` — the sibling parent, under
the *same inline Skill-tool binding* — genuinely does need to hand `/roadmap`
conversational content, and it does not use the transcript. It writes a file.
`skills/charter/references/phases/phase-2-chain-orchestration.md:433-461`:

> A pre-populated `wip/roadmap_<topic>_scope.md` file matching the schema
> `/roadmap` Phase 1 expects. The handoff causes `/roadmap` to skip its Phase
> 1. `/charter` is the only skill that pre-populates that file…

Seven named fields: Theme Statement, Initial Scope, Candidate Features,
Dependency Sketch, Sequencing Constraints, Downstream Artifact State, Coverage
Notes. `/roadmap` reads it at startup and skips Phase 1
(`skills/roadmap/SKILL.md:134-151`).

This is the load-bearing observation. **If the inline binding's transcript were
the channel that carries conversation to children, `/charter` would not need to
write that file. It writes it anyway.** The pattern's own answer to "how does a
parent give a child conversational content" is already "serialize it to a file
in the child's namespace" — under the inline binding, today, in shipped code.

**And `/scope` already has a shipped, specified serialization of the exact
Phase 1 conversation.** The `/explore` handoff, `phase-resume.md:177-197`:

> **What the handoff carries.** …provenance…; the problem statement; the scope
> boundary; the decisions the exploration already settled; coverage notes on
> what it did and did not examine; observations about upstream artifacts it
> found; **the author's framing-shift answer with the evidence behind it**; and
> a shape-signals block carrying the architectural alternatives left open and
> the complexity signals surfaced — predicate inputs, never predicate verdicts.
>
> **What it does not carry…** The handoff carries conversation, never
> filesystem state. It states no artifact's existence, no frontmatter
> `status:`, no content hash, no repo visibility, and no upstream validation
> result. Every one of those is re-read on every run…

That is a file that carries the framing-shift answer, the scope boundary, the
settled decisions, and the P1/P3 predicate inputs — i.e. essentially the whole
Phase 1 conversation — and whose design principle ("carry conversation, re-read
filesystem") is exactly the split a koto context key would want. The one rule
attached to it is worth carrying forward:
`phase-resume.md:154-162` — a pre-supplied framing-shift answer "is never
accepted as recorded state… the confirmation is mandatory rather than a
formality," because it is "the one carried value that reaches a gate."

**Finally: `/scope` already runs with no author at all.** `skills/scope/SKILL.md:106-107`:
`--auto` is "non-interactive mode. Decisions follow the recommended default
based on context; the run does not block on user input." It applies to all
phases (`:118`).

---

## Implications

1. **The prior run's deciding obstacle is not deciding.** "`/scope` drives a
   563-line author conversation" conflates the length of the *reference file*
   with the size of the *conversation*. The file is 563 lines because it argues
   at length about what Phase 1 must *not* decide; the conversation inside it
   is two questions and a three-value answer. `Proceed / Adjust / Bail` is a
   textbook koto `accepts` enum, and the compiler's mutual-exclusivity check
   would enforce something the prose currently only asserts.

2. **Nothing conversational needs to reach a child, so the hard part of a
   materialized binding evaporates.** The channel is argv + a durable artifact
   + a two-valued `rationale:` enum in a file the child globs for. All three
   survive materialization untouched — the child already reads them from disk
   and is already written to work under a parent it cannot see.

3. **The real porting cost is template authoring, not conversation.** Four new
   `koto-templates/` directories for `/brief`, `/prd`, `/design`, `/plan` (none
   exists today), plus a `/scope` parent template. That is a concrete,
   estimable engineering cost with no philosophical component.

4. **An inline koto binding is available and may be the whole answer.** Nothing
   requires materializing children to get the exploration's stated win.
   `/scope` could drive a koto session for its *own* phase sequencing —
   directives drip-fed one state at a time via `koto next` instead of a
   968-line SKILL.md arriving whole — while keeping inline Skill-tool child
   dispatch. That addresses the actual defect (SKILL.md loads whole, including
   the reader-economy argument) without touching the four children at all.

5. **The gating win lands where it was claimed.** A `context-exists` gate keyed
   on each hop's durable artifact makes the shirabe#331 failure mode
   — reach the terminal PLAN, assert the upstream artifacts were consolidated
   away — structurally unreachable: the parent cannot advance past a hop whose
   artifact does not exist.

6. **`--auto` maps cleanly onto the shipped pattern.** `execute.md`'s
   `{{PAUSE_BEFORE_FINALIZE}}` → `pause_decision` enum → `paused_for_review`
   terminal is a working template-level expression of exactly `/scope`'s
   `--auto` / `--interactive` split, including the resume path.

---

## Surprises

**Four things contradict the established findings. Flagging loudly.**

1. **"That is not a porting cost; it is a change to what `/scope` is" is
   wrong, and `/scope`'s own SKILL.md is the counter-evidence.** `--auto`
   (`scope/SKILL.md:106-107`) already runs the entire chain with zero author
   input, across all phases. A skill that ships a supported no-conversation
   mode cannot have the conversation as its identity.

2. **`/scope` passes children *nothing* conversational, and `/prd` states it
   outright.** `prd/SKILL.md:128-129`: "`/scope` pre-populates nothing for
   `/prd`; it invokes `/prd` and lets Phase 1 do the scoping." The children
   hold their own author conversations. The parent conversation is for the
   parent's own two gates.

3. **The transcript is demonstrably not the pattern's conversational channel —
   `/charter` proves it under the same inline binding.** `/charter` writes a
   seven-field `wip/roadmap_<topic>_scope.md` into `/roadmap`'s namespace
   (`charter/references/phases/phase-2-chain-orchestration.md:433-461`). If the
   shared agent context carried conversation to children, that file would be
   redundant. It ships anyway. Serializing parent conversation into a child is
   the pattern's *existing* answer, not a new requirement koto would impose.

4. **The serialization of Phase 1's conversation is already specified and
   already in the repo.** The `/explore` handoff (`phase-resume.md:177-197`)
   carries the framing-shift answer with its evidence, the scope boundary, the
   settled decisions, and the P1/P3 predicate inputs — and its stated design
   principle is "carries conversation, never filesystem state." The question
   "what would serialize the unwritten parts" has a shipped answer that
   predates the koto question.

**Two smaller surprises:**

5. **Phase 1's framing-shift answer is never persisted anywhere.**
   `framing_shift` is absent from `state-schema.md`. On a `/scope` resume the
   answer is re-asked. A koto binding would *improve* this — an `accepts` enum
   is recorded in the event log by construction.

6. **`context_assignments` is undocumented in the template-format reference**
   despite being used by the shipped `execute.md` template and validated by the
   engine (`koto/src/template/types.rs:1219-1242`). It is the mechanism by
   which agent-submitted prose reaches the context store. A template author
   following the docs would not find it.

**One genuine constraint, in the other direction:** template variables cannot
carry prose. The `--var` allowlist rejects newlines, quotes, and shell
metacharacters (`template-format.md:747-751`). Any conversational content must
go through `koto context add` or a `type: string` accepts field —
never `{{VAR}}`.

---

## Open Questions

1. **Inline-koto or materialized?** The exploration's stated defect is that
   SKILL.md loads whole. An inline koto binding (koto sequences `/scope`'s own
   phases; children still dispatched via the Skill tool) fixes that without
   authoring four child templates. Nothing I read forces materialization.
   Needs a decision.

2. **What is the actual directive budget?** If koto drip-feeds directives one
   state at a time, someone has to decide what of the 968-line SKILL.md and the
   3,946 lines of phase references belongs in directives, what belongs in
   `<!-- details -->` blocks (`template-format.md:113-124`), and what stays as
   files the directive points at. That is the load-bearing design work and I
   did not size it.

3. **Does the Adjust self-loop need a bound?** `phase-1-discovery.md:548-551`
   states there is "no implicit limit on Adjust iterations" and that
   `--max-rounds=N` explicitly does not govern them. koto templates can
   self-loop indefinitely, so this ports as-is — but an unbounded loop in a
   state machine is more visible than an unbounded loop in prose, and someone
   may want to bound it once it is.

4. **Where does the re-entrant post-`/prd` gate live in a template?** It sits
   in the Phase 1 *file* but executes mid-chain after `/prd` returns
   (`phase-1-discovery.md:113-142`). It records nothing and prompts nothing, so
   it could be directive text on the chain-loop state — but the phase/state
   mapping is not one-to-one here and a template author will hit it.

5. **Would a `/scope` koto binding want its own handoff-shaped context key?**
   Given finding 4 in Surprises, the natural move is a `discovery.md` context
   key with the handoff's section list, gated by `context-exists`. Whether that
   is worth doing when no child consumes it — it would serve resume and audit,
   not the children — is a judgment call for the human.

6. **Does `/scope --auto` change the eval surface?** If the author conversation
   compiles to an `accepts` enum, `--auto` becomes a template variable that
   pre-answers it (the `execute.md` pattern). Whether eval 17 and AC9's literal
   `Proceed`/`Adjust`/`Bail` substring checks
   (`phase-1-discovery.md:338-340`) still grade anything meaningful when the
   options block is compiler-enforced rather than prose-asserted is worth
   asking.

---

## Summary

Phase 1's author conversation is two questions — a framing-shift ask and a
three-value `Proceed / Adjust / Bail` — everything else in its 563-line
reference is machine-derivable from globs, a keyword list, and a status table,
and none of it reaches any child: `/prd`'s own SKILL.md states that "`/scope`
pre-populates nothing for `/prd`," the framing-shift answer is never even
written to the state file, and the entire parent→child channel is argv plus a
durable artifact plus a two-valued `rationale:` enum in a state file the child
*globs the filesystem* for rather than reading from any transcript. The prior
run's deciding obstacle therefore does not hold — `/scope` already ships
`--auto`, which runs the whole chain with no author at all; `/charter` already
serializes parent conversation into a child via a seven-field file *under the
same inline binding*, proving the transcript was never the channel; and koto
expresses interactive states fine (`accepts` enums, escalation states with
free-string capture, and a `paused_for_review` suspend-and-resume terminal, all
shipped in `execute.md`), so the real porting cost is authoring five koto
templates that do not exist yet, not preserving a conversation. The biggest
open question is whether materialization is needed at all: an inline koto
binding that sequences `/scope`'s own phases fixes the stated defect —
SKILL.md arriving whole — without touching the four children.
