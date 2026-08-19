# Lead: How is `P2: Default to the lowest ceremony` reconciled with a chain whose steps are mandatory?

## Findings

### 1. `workflow-principles.md` scopes itself to two skills, in its first sentence

`references/workflow-principles.md` is 115 lines and opens with an explicit
scope statement (lines 3-7):

> Five principles the roadmap and plan workflows derive from. Each
> principle states the rule, names the consequence, and lists the
> specific workflow rules that flow from it. Skill surfaces reference
> these by name -- when a surfaced rule cites a principle, it's citing
> this file.

And lines 9-10:

> The set is intentionally small enough to hold in mind. Use it to
> reason at the edges where a procedure doesn't fit.

The two sentences pull slightly apart — the first bounds the file to the
roadmap and plan workflows, the second invites an agent to reason at edges
generally — but the binding scope is stated first and stated as a fact about
what the principles are derived from, not as an aspiration.

That scope was deliberate. `docs/briefs/BRIEF-roadmap-plan-standardization.md:275-277`
says the set is "authored to be reusable by sibling doc types later, **though
this work wires only the roadmap and plan workflows to it**." The narrow wiring
is the shipped state; broader reuse is a stated future intent that has not
happened.

### 2. P2 verbatim, and what its derived rules actually govern

`references/workflow-principles.md:41-53`:

> ## P2: Default to the lowest ceremony
>
> Reach for the least machinery the work needs. Escalate only when a
> named condition forces it.
>
> **Rules derived from this:**
>
> - One PR over many (see P1).
> - A self-contained PLAN doc over GitHub issues when the work is
>   single-pr.
> - Don't promote a check to error-level when a notice suffices for the
>   current corpus state (see P5 for the inverse: strictness when blast
>   radius warrants).

All three derived rules are **choices between two forms of the same finished
output**, made after the work is decided:

| Rule | The choice | What is being chosen between |
|------|-----------|------------------------------|
| One PR over many | delivery packaging | two ways to land the same code |
| PLAN doc over GitHub issues | decomposition container | two ways to record the same decomposition |
| Notice over error | check severity | two ways to surface the same finding |

None of the three is "skip a step." None is about how many judgments to force,
how many agents to spawn, or how many gates to hold. Each presupposes that the
work has already been done and asks what shape it lands in.

### 3. The requirements document bounds P2 explicitly, in a rejected alternative

`docs/prds/PRD-roadmap-plan-standardization.md:636-640` rejects collapsing P2
into P1 and, in doing so, states P2's domain outright:

> - *Collapse "lowest-ceremony default" into "usable value."* Rejected: they
>   look adjacent but answer different questions. **Lowest-ceremony governs
>   artifact ceremony (one PR or many; a PLAN doc or GitHub issues)**; usable
>   value governs the shape of the deliverable (does each unit land observable
>   value). They can pull in opposite directions, and an author needs both
>   visible to land the single-pr/multi-pr call.

"Artifact ceremony," with the two examples being exactly the two output-form
choices in the principle body. This is the strongest single piece of evidence
in the corpus: the requirements that produced P2 say what P2 is for, and it is
output form, not step count. The closing clause — "an author needs both visible
to land the single-pr/multi-pr call" — names the one decision P2 was written to
support.

### 4. Citation census: nobody outside `/plan` and `/roadmap` loads it

Full repo grep for `workflow-principles`, excluding `wip/` and design/PRD prose:

**Skill surfaces that load it (5 sites, all in two skills):**

- `skills/plan/SKILL.md:156` — cites P1 for the delivery-preference default in
  the Execution Mode section.
- `skills/plan/references/quality/plan-doc-structure.md:42-45` — "the five
  principles both workflows derive from. The single-pr default (P1) and the
  lowest-ceremony principle (P2) drive the execution mode choice below."
- `skills/plan/references/phases/phase-3-decomposition.md:407-409` — cites P1
  for the value-confirmation guard.
- `skills/roadmap/references/roadmap-format.md:40-43` — cites P1 for why a
  roadmap is multi-pr.
- `skills/plan/evals/evals.json:234,240` — an eval asserting the plan surface
  cites P1.

**Shared references that cite it back:** `references/split-triggers.md:6,70`
(consumed by P1), `references/issues-table.md:8` and
`references/dependency-diagram.md:7` (both "Cited by P4").

**Zero citations from:** `skills/scope/` (all of SKILL.md and every phase file),
`skills/charter/`, `skills/execute/`, `skills/explore/`, `skills/brief/`,
`skills/prd/`, `skills/design/`, and `references/parent-skill-pattern.md`.

Note the shape of what *is* cited: of the five live skill-surface citations,
**four cite P1 and one cites P2** — and the one P2 citation
(`plan-doc-structure.md:44`) uses it for the single-pr/multi-pr call, which is
the exact use the PRD says it is for. P2 has never been invoked in this corpus
for anything but choosing an output form.

### 5. P2 *is* reachable from inside a `/scope` run — but only at the last hop

`/plan` is `/scope`'s terminal child. An agent executing the `/plan` hop loads
`plan-doc-structure.md`, which is the one file that names P2 by its full title
("the lowest-ceremony principle (P2)"). So P2 does reach an agent inside a
`/scope` run.

But it reaches that agent at the fourth of four hops, after every gate, jury,
and review has already been paid for, and it reaches it in the context of
"single-pr or multi-pr." It cannot cause the #331 incident, and it cannot be
read there as license to prune upstream hops that have already run. The
exposure is real but downstream of the decision it would have to corrupt.

### 6. The corpus never connects the mandatory-steps model to P2 — but does carry the reconciliation, unnamed, in a file `/scope` loads

Grep for `P2` and `workflow-principles` across
`docs/designs/current/DESIGN-scope-chain-mandatory-steps.md`,
`docs/prds/PRD-scope-chain-mandatory-steps.md`,
`references/parent-skill-pattern.md`, and `skills/scope/SKILL.md`:
**zero matches in all four.** The design that pushed the mandatory-steps model
up into the shared pattern never considered P2, and `parent-skill-pattern.md`'s
Gate Vocabulary states the model without reference to any principle.

What the Gate Vocabulary does say (`references/parent-skill-pattern.md:113-122`):

> **Chain steps are mandatory, and reduction is post-hoc.** A parent
> SHALL NOT decide, before a child's artifact exists, that the artifact
> is not worth producing. Reduction of the artifact set happens against
> documents that exist, or it does not happen.

That is an argument about *timing* (when reduction may happen), not about
ceremony. It closes the door P2 might be read as opening, but it never says so.

The reconciliation that does exist lives in `references/pipeline-model.md` —
a file `/scope` already loads three times (`skills/scope/SKILL.md:156`,
`skills/scope/references/phases/phase-0-setup.md:209`,
`skills/scope/references/phases/phase-2-chain-orchestration.md:217`). Two
passages, neither naming P2:

`references/pipeline-model.md:32-35`:

> Not all work passes through all three diamonds. Trivial and simple work goes
> straight to Diamond 3 through `/work-on`, and a finished PLAN enters there
> through `/execute`. Everything else enters at the top of a chain: `/explore`
> when the shape is unclear, `/scope` or `/charter` when it isn't.

`references/pipeline-model.md:84-89`:

> There is no transition that bypasses a diamond's steps. Work enters the pipeline
> at one point, and from there every step of the chain it entered runs. Whether a
> document is worth producing is answered by reading it against the one before it,
> which is possible only once both exist, so the reduction happens afterward and
> not from a classification made at entry.

Plus the complexity table (`pipeline-model.md:41-46`) and the skill routing
table (`pipeline-model.md:255-266`), which route "Trivial fix (typo, config)"
and "Simple task with issue" to `/work-on` directly and reserve
`/scope -> BRIEF -> PRD -> DESIGN -> PLAN` for "Whole tactical chain in one
sitting."

Read together, these say: **ceremony selection is an entry-point decision, made
before any chain runs. Once an entry point is chosen, its steps all run.** That
is precisely the reconciliation the lead asked for, sitting in a file `/scope`
loads at Phase 0 — but stated as routing mechanics, never connected to the
principle it discharges.

### 7. Verdict on the tension

**P2 survives a careful reading.** It does not contradict the mandatory chain,
on three independent grounds, any one of which is sufficient:

1. **Stated scope.** The file's first sentence binds it to the roadmap and plan
   workflows. `/scope` is neither.
2. **What its rules govern.** All three derived rules choose between output
   forms for work already decided. A chain hop is not an output form; it is the
   judgment that produces one.
3. **Where ceremony is chosen.** `pipeline-model.md:32-35` and the routing table
   put the ceremony decision at entry-point selection — `/work-on` versus
   `/scope` versus `/charter`. Running `/scope` at all *is* the escalation P2
   contemplates, and the author has already made it. P2's "escalate only when a
   named condition forces it" is answered by the routing table's named
   conditions; it does not license re-litigating the escalation from inside.

Under reading 3, the chain is itself the escalation, not something to be
escalated out of — which is the lead's own second candidate reconciliation, and
it holds.

**But the tension is live as a reading risk, not as a textual contradiction.**
Three things make it so:

- P2's second sentence in the file header ("Use it to reason at the edges where
  a procedure doesn't fit") invites exactly the generalization the first
  sentence forecloses. An agent hitting an edge in `/scope` — which is what an
  agent facing a small feature is doing — is being told by this file to reason
  from these principles.
- The BRIEF says the set was "authored to be reusable by sibling doc types
  later." A reader who knows that reads the narrow scope as provisional.
- The strongest bound on P2 (the PRD's "governs artifact ceremony") lives in a
  requirements document nobody loads at runtime. It is not on any skill surface
  and not in the principles file itself.

So: after `## Why the Artifact Set Shrinks` is removed or rewritten, an agent
that generalizes P2 finds nothing in `/scope` that stops it, and nothing
anywhere that names P2 and says "not this." The pieces of the answer exist
(pipeline-model's routing layer, the Gate Vocabulary's timing rule); no document
assembles them.

### 8. The seam that is sharper than P2

Closed issue #280 ruled `/scope` is "the front door for tactical work of any
size" — deliberately no lower bound. `pipeline-model.md:32` and the routing
table simultaneously say trivial and simple work goes to `/work-on` and never
enters `/scope`.

These are compatible: "any size" means `/scope` does not itself refuse small
work, not that all work enters at `/scope`. But no document says so, and the
combination "the front door for work of any size" + "default to the lowest
ceremony" is a materially more dangerous pair than P2 alone. It reads as: the
front door should be cheap when the work is small. That is one step from the
#331 failure — an agent deciding the upstream documents weren't worth the paper.

Any reconciliation `/scope` writes should carry the entry-point/step distinction
in a form that answers both pairings, not just P2.

## Implications

**A rewrite that says "the process is the product" does not need to defend
itself against P2 on the merits.** P2 is scoped elsewhere, and every one of its
derived rules is about output form. The rewrite is not making a claim P2
contests. It should not be written defensively, and it should not concede
anything.

**It should still name the boundary once, because the boundary is currently
stated nowhere an agent reads.** The cost is one or two sentences; the thing
they buy is that a future agent who goes looking for a reduction argument finds
the answer instead of the invitation.

**The smallest honest reconciliation, within blast radius.** Place it in the
same location the purpose argument lands — replacing or joining
`skills/scope/SKILL.md:472+` (`## Why the Artifact Set Shrinks`) — and have it
do two things:

1. Name the entry-point/step distinction and anchor it on a file `/scope`
   already loads: choosing `/scope` over `/work-on` *is* the ceremony decision,
   and by the time this skill runs the author has made it
   (`references/pipeline-model.md:32-35`, and the routing table at 255-266).
   Inside a run there is no lighter variant of a hop, because a hop's cost is
   the judgment it forces, not the file it leaves
   (`references/pipeline-model.md:84-89`).
2. Name P2 explicitly in one clause, so the connection is greppable: the
   lowest-ceremony default in
   `${CLAUDE_PLUGIN_ROOT}/references/workflow-principles.md` governs which
   command an author runs and what form its output takes; it does not prune the
   steps of the command they ran.

Naming P2 costs `/scope` one new citation to a shared reference — legal, cheap,
and it is the only thing that makes the reconciliation findable by an agent who
arrives at the problem from the principles file rather than from `/scope`.
Recommend naming it rather than gesturing at it.

**Out of blast radius — flag, do not do.** Two durable fixes are edits to shared
files the author does not own:

- `references/workflow-principles.md` — the honest structural fix is either
  tightening the header's second sentence, or adding one derived rule to P2 of
  the form "a chain hop is not machinery to be reduced; see
  `parent-skill-pattern.md` Gate Vocabulary." Either would put the answer where
  the question is asked. Out of scope; worth a follow-up issue.
- `references/parent-skill-pattern.md` — the Gate Vocabulary states the
  mandatory-steps model without naming the principle it appears to override.
  One clause there would close it for `/charter` and `/execute` too. Out of
  scope.

Neither is required for the `/scope` rewrite to be correct. Both would make the
corpus-level answer stop depending on a reader arriving via `/scope`.

## Surprises

**The PRD already answers the question, in a rejected alternative.**
`PRD-roadmap-plan-standardization.md:636-640` says "Lowest-ceremony governs
artifact ceremony (one PR or many; a PLAN doc or GitHub issues)" — a scope
statement at least as tight as anything a rewrite could add, written two years
of corpus ago, in a section explaining why P2 was *not* merged into P1. The
sharpest bound on the principle is in a document nobody loads.

**Four of five live citations are P1, not P2.** P2 has exactly one runtime
consumer (`plan-doc-structure.md:44`) and it uses P2 for the single-pr/multi-pr
call. Despite being the principle round 1 flagged as the open flank, P2 is the
least-used principle in the set. Its danger is entirely prospective.

**`pipeline-model.md` already carries the mandatory-steps argument in prose, in
a file `/scope` loads at Phase 0.** Lines 84-89 state the model — no bypass,
reduction is post-hoc, the entry classification cannot answer the question — in
language nearly identical to the Gate Vocabulary. `/scope` cites this file three
times, every time for the *lifetime rule* about which document records the
strategic-to-tactical crossing. It has never cited it for the passage that
answers why the chain runs.

**The mandatory-steps design never mentions the principles file.** Zero matches
for `P2` or `workflow-principles` across `DESIGN-scope-chain-mandatory-steps.md`
and `PRD-scope-chain-mandatory-steps.md`. The work that pushed the model into
the shared pattern audited four surfaces for stale skip language and did not
look at the file that states the framework's ceremony default.

## Open Questions

1. **Should `/scope` cite `workflow-principles.md` at all?** Naming P2 makes the
   reconciliation findable but creates the corpus's first citation from a parent
   skill into a file scoped to `/plan` and `/roadmap` — which could be read as
   asserting the file governs `/scope`, the opposite of the intent. A phrasing
   that cites it *to bound it* ("governs X, not Y") avoids this, but it is
   worth a second read.

2. **Does the same reconciliation belong in `/charter`?** `/charter` runs three
   mandatory hops and cites `workflow-principles.md` zero times, identically to
   `/scope`. Out of blast radius, but if the `/scope` prose is written well it
   is the template.

3. **Is the "#280 front door for any size" seam worth its own lead?** It is the
   more direct route to the #331 failure than P2 is, and it sits in a closed
   issue rather than in any loaded file. The scale-lower-bound lead may already
   own it.

4. **Does the invitation in `workflow-principles.md:9-10` ("Use it to reason at
   the edges where a procedure doesn't fit") need bounding?** It is the sentence
   that turns a scoped file into a general-purpose one in an agent's hands. Out
   of blast radius, but it is the actual mechanism by which P2 becomes live.

## Summary

P2 survives a careful reading and poses no textual contradiction: `references/workflow-principles.md:3` scopes the whole set to "the roadmap and plan workflows," all three of P2's derived rules (lines 48-53) choose between output *forms* for work already decided, and `docs/prds/PRD-roadmap-plan-standardization.md:637` bounds it outright — "Lowest-ceremony governs artifact ceremony (one PR or many; a PLAN doc or GitHub issues)." A citation census confirms it: five live skill-surface citations, all in `/plan` and `/roadmap`, four of them to P1; zero from `/scope`, `/charter`, `/execute`, or `parent-skill-pattern.md`.

The tension is a reading risk, not a contradiction, and the corpus already carries the answer unnamed in a file `/scope` loads at Phase 0 — `references/pipeline-model.md:32-35` and `:84-89` put the ceremony decision at entry-point selection (`/work-on` vs `/scope` vs `/charter`) and then state "there is no transition that bypasses a diamond's steps." Nothing connects that to P2: `DESIGN-scope-chain-mandatory-steps.md` and `parent-skill-pattern.md` mention P2 zero times, and the sharpest bound on the principle sits in a PRD nobody loads at runtime.

Recommended fix, within blast radius: one or two sentences where the purpose argument lands (`skills/scope/SKILL.md:472+`), naming the entry-point/step distinction on `pipeline-model.md`'s authority and naming P2 in one clause to make the connection greppable — the lowest-ceremony default governs which command you run and what form its output takes, not whether the steps of the command you ran happen. Editing `workflow-principles.md` or `parent-skill-pattern.md` would be the durable corpus-level fix and is out of scope; flag as follow-up. Note also a sharper seam than P2: #280's "front door for tactical work of any size" paired with a lowest-ceremony default reads as "the front door should be cheap for small work," and the prose should answer both pairings.
