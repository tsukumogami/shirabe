# Lead: What does the replacement prose actually say?

Round 1 converged on what to cut from `skills/scope/SKILL.md`. This
lead drafts what goes in its place. Everything under `## Draft Text`
is candidate text, written to be pasted and reacted to, not
described. Nothing in `skills/scope/SKILL.md` was edited.

Source reading behind the drafts:

- `skills/scope/SKILL.md:19-47` (lede), `:442-445`, `:532-578`,
  `:847` (write-target set)
- `skills/scope/references/phases/phase-2-chain-orchestration.md`:
  `:14-20` (what makes Phase 2 different), `:488-500` (`**Why it
  exists.**`), `:502-520` (firing condition), `:597-600` (the
  judgment question), `:619-632` (compose + carry check),
  `:719-739` (the no-floor prohibition — register model)
- `skills/scope/references/phases/phase-1-discovery.md:303-306`,
  `:486-488` (constant `planned_chain:`)
- `/charter`'s `references/phases/phase-2-chain-orchestration.md:463-511`
  ("Why /roadmap Is Unconditional" — register model)
- Per-type contribution declarations, which is where the
  operational definition actually bottoms out:
  `skills/brief/references/brief-format.md:503-504`,
  `skills/prd/references/prd-format.md:249-250`,
  `skills/design/references/design-format.md:364-365`,
  `skills/plan/references/quality/plan-doc-structure.md:309-310`
- Child phase inventories: `skills/brief/SKILL.md:208-241`,
  `skills/prd/SKILL.md:96-142`, `skills/design/SKILL.md:160-206`,
  `skills/plan/SKILL.md:442-515`,
  `skills/plan/references/phases/phase-6-review.md:1-40`
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md:674-706`
  (Required SKILL.md Structural Elements)

Prose is wrapped at 66 columns, matching the file.

## Draft Text

### 1. Purpose statement for the lede

Placement: immediately after the opening paragraph of `# Scope`
(`SKILL.md:21-33`), before the pattern-contract paragraph at
`:35-47`. It is the second thing a reader meets.

> The process is the product. Each child runs a workflow — a
> scoping conversation, a research fan-out, a decision bakeoff, a
> jury, a security review — and the artifact it writes is the
> materialization of that workflow: the sink for the step that
> produced it, and the source for the step that follows. `/plan`
> is handed a DESIGN because a DESIGN is what `/design` finished
> holding. That is why the chain has four hops instead of one.
>
> A run is not a way to obtain four documents. "Should we produce
> this artifact" is not a question the chain asks, at Phase 1 or
> anywhere else. What each type owes the chain is one
> **contribution** — the single thing it adds that no other type
> does, small enough to compress into one section of whatever
> document outlives it. BRIEF contributes WHY: the problem the
> feature solves and the outcome a user should experience. PRD
> contributes WHAT: the requirements the feature must meet and the
> criteria that decide it's done. DESIGN contributes HOW: the
> technical approach, the alternatives weighed, and why this one.
> PLAN contributes WHEN: the order the work happens in, and what
> each unit depends on. Each child's format reference declares its
> own; Phase 2 reads them.
>
> The reduction question `/scope` does ask is narrow, local, and
> late: given two documents that exist, does the upstream hold
> anything *beyond* its contribution that folding into the
> downstream would lose? An agent holding this file and no
> artifacts cannot answer that about a document nobody has
> written, and shouldn't try.

Notes on this draft: the four contributions are quoted from the
format references rather than invented, so the definition has a
source of truth and the lede is a lift rather than a second
authority. The last sentence is deliberately addressed to the
agent in the second person, matching the register at
`phase-2-chain-orchestration.md:719-739`.

### 2. Per-hop statements of what each child buys

Register target: `/charter`'s "Why /roadmap Is Unconditional"
argues a step in terms of what skipping it *strands downstream*
("a chain that ends at a STRATEGY alone strands whatever it made
actionable"). Each passage below ends on that move. Every phase
named is real: the two-reviewer brief jury, the PRD research
fan-out and three-agent jury, `/design`'s per-question `/decision`
bakeoff plus mandatory security review, `/plan`'s value guard and
`/review-plan`.

#### Shape (a) — four passages in `SKILL.md`

Placement: a `## What Each Hop Buys` section, sitting where
`## Why the Artifact Set Shrinks` is now (`:532`), i.e. after the
chain-proposal output and before `## Consolidation Judgment`.

> ## What Each Hop Buys
>
> **`/brief`** converts a topic string into a stated problem and a
> stated outcome, then puts concrete user journeys and a scope
> boundary under them. Two reviewers read the result in parallel:
> one checks that the Problem Statement states a problem rather
> than a smuggled solution and that the journeys are distinct and
> exercisable, the other checks structure and visibility. Both
> must pass before the BRIEF is Accepted. Skip the hop and `/prd`
> writes requirements against whatever the topic string implied,
> with no agreed problem to test them for relevance against.
>
> **`/prd`** turns that problem and outcome into requirements with
> acceptance criteria. Phase 1 is a scoping dialogue with coverage
> tracking, and it hands Phase 2 a set of research leads that
> specialist agents investigate in parallel — so the requirements
> are written against what the codebase and its ecosystem actually
> support, not against a guess. A three-agent jury then reads the
> draft, because authors consistently miss ambiguity and
> testability gaps in their own writing. Skip the hop and
> `/design` picks an architecture with no statement of what the
> thing must do: nothing bounds the alternatives, and nothing
> decides when the feature is done.
>
> **`/design`** is where the alternatives get weighed. Phase 1
> decomposes the problem into independent decision questions;
> Phase 2 runs `/decision` against each one in parallel, at equal
> depth — a bakeoff with adversarial agents, peer revision, and
> cross-examination, per question. Phase 3 cross-validates the
> assumptions those decisions made against each other, and always
> runs, even with one decision. Phase 5's security review always
> runs too; its output may be N/A but the review is not optional.
> Phase 6 checks that the rejected alternatives were argued rather
> than propped up. Skip the hop and the PLAN sequences an approach
> nobody compared to anything, and no security review happens
> anywhere in the chain.
>
> **`/plan`** decomposes the DESIGN into atomic issues, sequences
> them, and maps the dependency graph. A value-confirmation guard
> checks that each unit delivers observable incremental value and
> can fail, naming the unit and the reason it failed. Phase 6
> hands the whole artifact to `/review-plan`, which challenges it
> on scope, design fidelity, whether the acceptance criteria
> discriminate, and sequencing integrity. Design fidelity is the
> check with nothing to read when no DESIGN exists — a PLAN
> reached without one still validates, and still passes review,
> because the reviewer can only measure fidelity against what it
> is given.

#### Shape (b) — general statement in `SKILL.md`, detail at the hop

`SKILL.md`, same placement, replacing `## Why the Artifact Set
Shrinks`:

> ## What Each Hop Buys
>
> Every hop produces something the next hop consumes, and the
> consumption is literal: Phase 2 invokes each child with the path
> of the artifact above it, not with the topic slug. `/brief`
> buys an agreed problem and outcome. `/prd` buys requirements a
> design can be bounded by, researched by agents that fanned out
> on the leads and read by a three-agent jury. `/design` buys a
> compared approach, an argued set of rejected alternatives, and a
> security review that runs whether or not it finds anything.
> `/plan` buys a sequence, a dependency graph, and an adversarial
> pass over both.
>
> Skipping a hop doesn't buy a smaller artifact set. It hands the
> next child less to work from, and the next child has no way to
> tell that from a thin upstream. What each hop strands when it
> doesn't run is stated at the invocation itself, in the Child
> Invocation section of
> `skills/scope/references/phases/phase-2-chain-orchestration.md`.

Then, in `phase-2-chain-orchestration.md`, under `## Child
Invocation` (`:162`) — one passage attached to each row of the
existing per-child input-mode list, in the same order the list
already uses. The four passages are the ones drafted in shape (a),
verbatim; only the framing sentence changes:

> Each entry below states what the hop buys and what not running
> it strands, because the invocation is the last point at which
> that is actionable.

#### Which shape is better

Neither alone. Ship shape (b)'s general statement in `SKILL.md`
**and** shape (a)'s four passages in `SKILL.md` — that is, put the
general statement first and the four passages under it, and put
nothing new in Phase 2.

The reason is round 1's own caveat, and it decides the question.
Deferred material only governs an agent that reaches the deferral
point. An agent that skips the hop never reads the Phase 2
passage — which is precisely the failure in issue #331, where the
skill's live warning about per-hop gating sat in text the agent
did have and still read as settled history. Putting the only
motivating text at the hop reproduces the defect with the polarity
reversed: the argument for shortcutting would be gone from
`SKILL.md`, but so would the argument against, and `SKILL.md`
would once again state exactly one thing about the artifact set
(that consolidation can shrink it) with nothing beside it.

The placement defect from the issue doesn't argue against shape
(a) here, and it's worth being precise about why. That defect is
about revealing *the conclusion of a downstream decision* — a
verdict an agent can then aim at. "What this hop buys" is not a
verdict; it's the premise the chain runs on. There is nothing to
optimize against in "the security review always runs."

The one real cost of shape (a) is that it puts a full inventory of
each hop's machinery in front of an agent that has run none of it,
and an agent looking for a reason to skip can read "two reviewers"
as cheap. That is a wording problem, not a placement problem, and
the drafts answer it by ending every passage on the downstream
consequence rather than on the machinery.

### 3. Rewritten `## Consolidation Judgment`

Replaces `SKILL.md:532-578` in full. The rationale is removed —
it lives at `phase-2-chain-orchestration.md:492-500` under
`**Why it exists.**` and stays there. What survives at this
altitude is the bound.

> ## Consolidation Judgment
>
> A `/scope` run has exactly one mechanism that removes a document
> from disk, and this is it. After each child returns and its
> artifact validates, Phase 2 judges the hop this run drew — the
> artifact that just landed, against the artifact this run handed
> the child as its invocation argument — and reaches `keep` or
> `absorb`. On `absorb`, the upstream's contribution is carried
> into the survivor as one section immediately after `## Status`,
> every link to the upstream is re-pointed, the survivor declares
> what it took in via `absorbed:` and a `## Status` absorption
> line, and the upstream is deleted. Nothing else in a `/scope`
> run deletes a document.
>
> Three bounds hold at this altitude:
>
> - **It runs only after both artifacts exist.** The judgment
>   fires only when both endpoints of the edge appear in
>   `chain_ran:`. An artifact held back by re-entry protection was
>   never a party to a judgment; an artifact nobody wrote cannot
>   become one by assertion.
> - **It decides against the two documents, never against their
>   types.** No check anywhere in the judgment may read either
>   type's required-section list or compare the two types' section
>   sets. The test for a violation: a condition that refuses one
>   pair while permitting its structural twin under identical
>   repository state is a type rule.
> - **Nothing is deleted without a carry check.** Before any
>   deletion, itemize where each of the absorbed artifact's
>   concerns landed, including every contribution the ancestor was
>   itself carrying. Anything that didn't arrive aborts the absorb
>   and leaves both artifacts in place.
>
> The full procedure — eight steps, the citation preflight that
> can reach no outcome stronger than `keep`, the rollback table,
> the firing condition, why the judgment exists at all, and the
> prohibition on reintroducing a durable-artifact floor — lives in
> the Consolidation Judgment section of
> `skills/scope/references/phases/phase-2-chain-orchestration.md`.

Net: 47 lines become 34, and the section now reads as a notice
that files get deleted plus the conditions on it, rather than as a
case for deleting them. The three bounds are the three an agent
holding only `SKILL.md` can act wrongly on; everything else is
procedure and stays downstream.

### 4. Replacement text for the three licensing sentences

#### 4a. `SKILL.md:29` — the PLAN as product

Current (`:28-29`): "lands at one of three terminal exits: a
`full-run` that produces a PLAN at `docs/plans/PLAN-<topic>.md`".

Replacement — the sentence continues into `:30-33` unchanged:

> ...and lands at one of three terminal exits: a `full-run`, whose
> last hop consumes the DESIGN and deposits a PLAN at
> `docs/plans/PLAN-<topic>.md`, a `re-evaluation` exit that writes
> a Decision Record at a settled-upstream boundary (PRD or
> DESIGN), or an `abandonment-forced` exit that force-materializes
> the most-recently-running child's intermediate as a Draft
> artifact.

The change is two words of grammar doing the work: `/scope`
doesn't produce a PLAN, the terminal hop deposits one, and it
deposits one because it consumed a DESIGN. An agent reading the
replacement cannot get to `docs/plans/PLAN-<topic>.md` without
also reading that a DESIGN is what it takes to get there.

The same edit applies to `SKILL.md:583-588` (`full-run` under
`## Three Exit Paths`), which currently reads "Terminal artifact
is `docs/plans/PLAN-<topic>.md`". Suggested: "The chain completes
through `/plan`, whose input is the surviving artifact above it.
The PLAN it deposits at `docs/plans/PLAN-<topic>.md` is the
terminal artifact (status Draft when ...)". Flagged rather than
drafted in full, because it wasn't in the brief and the
parenthetical carries contract detail I'd rather not disturb.

#### 4b. `SKILL.md:442-445` — direct entry

Current: "An author who wants to start above `/brief` still
invokes `/design` or `/plan` directly. That buys a shorter
conversation, not a smaller artifact set: inside `/scope`, the set
is settled per hop after the artifacts land."

Replacement:

> An author who wants to start above `/brief` invokes `/design` or
> `/plan` directly, and that stays supported — all four children
> ship as standalone entry points. Be exact about what it gives
> up. `/plan` invoked with a topic string plans against the
> string: it has no DESIGN to decompose, so the sequencing rests
> on whatever the invoker inferred, and `/review-plan`'s
> design-fidelity check has nothing to read. The same holds one
> hop up — `/design` with no PRD weighs alternatives against no
> stated requirement. Entering above `/brief` asserts that the
> skipped steps were already taken somewhere else. Inside
> `/scope`, they're taken here.

What changed: the old text disclaims the *artifact set*, which
tells a reader the artifact set was the thing at stake and then
says direct entry isn't how you shrink it. The replacement
disclaims the *input*, which is the thing actually lost. And it
names the mechanism that goes blind (`/review-plan`'s
design-fidelity category), so the claim is checkable rather than
rhetorical.

#### 4c. `SKILL.md:43-46` — the reduction conclusion in the lede

Current, inside the asymmetry enumeration at `:40-47`: "a
post-hoc consolidation judgment that is the only thing reducing
the artifact set and runs only after the artifacts exist".

**Recommendation: rewrite, don't remove.** The pattern's Required
SKILL.md Structural Elements list
(`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md:674-706`)
names seven elements: Input Modes, execution-mode flag parsing,
topic-slug constraint, Workflow Phases diagram, Resume Logic
ladder, Phase Execution list, Reference Files table. A lede
paragraph enumerating parent-specific asymmetries is not among
them, and `/charter`'s lede has no equivalent enumeration —
so removing the clause breaks no pattern-conformance narrative.
It does break `/scope`'s own: the enumeration is what tells a
reader which prose contracts follow the seven elements and why
they exist, and dropping one of the five leaves a contract further
down the file with no forward reference.

So keep the slot and change what it declares. Replacement clause,
in place within the existing sentence:

> ...and the prose contracts after them bind the `/scope`-specific
> asymmetries the tactical chain introduces (two settled-upstream
> boundaries, Mandatory-with-auto-skip re-entry protection on
> every child, a post-hoc consolidation judgment that can remove a
> document only after both documents exist, a refuse-and-redirect
> Slot 5 shape for PLAN's downstream-owned lifecycle states, and a
> terminal child with two output modes).

"is the only thing reducing the artifact set" states a purpose —
that reducing the set is something the skill does, and this is how
it's done. "can remove a document only after both documents exist"
states a bound on a capability. The single-mechanism fact isn't
lost; it moves to the rewritten `## Consolidation Judgment`
(item 3), where it reads as a notice rather than as the skill's
mission, and where the reader meets it after the hop discussion
rather than in paragraph three.

### 5. The constant-chain promise, at `SKILL.md` altitude

Placement: a `## The Chain Is a Constant` section immediately
before `## Chain-Proposal Output` (`:420`), so it's read before
the proposal's three branches. It replaces nothing; the two
paragraphs at `:435-440` ("The proposal never offers a shorter
chain...") stay and now have something to lean on.

> ## The Chain Is a Constant
>
> `planned_chain:` is the literal list `[brief, prd, design,
> plan]` on every run. Phase 1 has no input that can shorten it
> and no field that records a different shape — not the topic
> string, not the execution-mode flags, not an `--upstream`
> document, not the size of the work in front of you. Re-entry
> protection can hold a child back when its artifact is already
> settled on disk, and that's recorded under its own name in
> `chain_skipped:` with the reason; it doesn't subtract from
> `planned_chain:`.
>
> Nothing here bounds how many artifacts a run ends with. That's
> Phase 2's call, made per hop against two documents that exist.
> Hold the two facts apart. A constant chain is not a promise of
> four documents, and a reducible artifact set is not a licence to
> run fewer steps.

Source: `phase-1-discovery.md:486-488` for the constant and the
absence of a shortening input; `:303-306` for "nothing here bounds
how many artifacts a run ends with." The last two sentences are
new, and they're the point of promoting the material: the two
facts have always been true and separately stated, and the
incident is what happens when a reader composes them.

## Notes on the Drafting

**The "contribution" definition is a lift, not an invention.**
`phase-2-chain-orchestration.md:597-600` gives the operational
shape — a contribution is what a document holds that compresses
into one section of a survivor, and the judgment asks whether the
upstream holds anything *beyond* it. But the four concrete values
are declared per type, in the format references, one sentence
each: WHY / WHAT / HOW / WHEN. I quoted those four rather than
paraphrasing, so `SKILL.md` doesn't become a second authority that
can drift. If the author would rather not carry four quoted
declarations in the lede, the fallback is one sentence plus a
pointer — but then `SKILL.md`'s eight uses of "contribution" still
have no local referent, which was the defect this item exists to
fix.

**I did not reproduce the withdrawn-design narration.** Roughly
half of `## Why the Artifact Set Shrinks` is past-tense history
("An earlier revision of this skill decided per hop...", "A
briefly-shipped revision... It was withdrawn"). None of it appears
in any draft above. Where a past design's failure is the reason
for a present rule, the rule is stated in the present imperative
and the history stays in Phase 2, which is where a maintainer
looks.

**Two facts from the deleted section needed a new home and got
one.** "There is no durable-artifact floor" and "`/scope` means
walk the whole chain" are both load-bearing. The first is already
stated at `phase-2-chain-orchestration.md:719-739` with the
prohibition attached, so the rewritten `## Consolidation
Judgment` just points at it. The second is what item 5's section
says, in operational terms, without the slogan.

**Register check.** Every draft passage is present-tense, second
person where it addresses the agent, and attaches a reason to each
instruction. I avoided the banned vocabulary (`tier` appears
nowhere; no `robust`, `leverage`, `comprehensive`, `holistic`,
`facilitate`), used contractions in the passages where the file
already uses them, and kept sentence length varied — the hop
passages deliberately end on a short clause.

**Where I was unsure.**

- Whether `## What Each Hop Buys` should sit before or after
  `## Chain-Proposal Output`. I put it after (at `:532`, where the
  deleted section was) so the file's order stays: what the
  proposal says, then why each item on it runs, then what can
  remove an artifact afterward. An argument exists for putting it
  before the proposal, since the proposal is the moment an agent
  could try to trim the list — but item 5's section already sits
  there and does that job.
- The `/brief` passage is the weakest of the four, because
  `/brief`'s machinery genuinely is the lightest: six phases, a
  two-reviewer jury, no research fan-out. I resisted inflating it.
  If the author finds it thin, the honest strengthening is the
  downstream clause, not the phase inventory.
- Whether the lede can carry all three of item 1's paragraphs
  without pushing `## Team Shape` too far down. Item 1 adds ~25
  lines to a 29-line lede. A tighter variant would drop the four
  quoted contributions to a single sentence naming WHY/WHAT/HOW/
  WHEN with a pointer to the format references.

## Surprises

**The chain's own docs already answer the question `SKILL.md`
asks eight times.** Every one of the four types declares its
contribution in a single bolded sentence in its format reference,
and all four sentences were written in the same shape. The
material for item 1 existed and had simply never been lifted. The
same is true of item 5: `phase-1-discovery.md` states both halves
of the constant-chain promise explicitly, in two places, with the
second half labelled "What Phase 1 Does Not Decide About the
Artifact Set."

**`## Why the Artifact Set Shrinks` is a near-verbatim duplicate
of the Phase 2 passage, including the sentence the incident
quoted.** `SKILL.md:534-537` and
`phase-2-chain-orchestration.md:491-495` say the same thing about
three documents costing a reader three reads. The Phase 2 copy is
labelled `**Why it exists.**` and sits under the mechanism it
justifies. The `SKILL.md` copy sits under a heading that promises
the artifact set shrinks. Same words, and only one of them can be
read as licence.

**The old text disclaims the wrong noun in two separate places.**
`SKILL.md:442-445` and `:560-566` both handle direct entry, and
both frame the loss as "not a smaller artifact set." Neither
mentions that a `/plan` invoked without a DESIGN has nothing to
decompose. The chain's most concrete argument for running the
steps was never made in the file that tells an agent to run them.

## Open Questions

1. **Does `## What Each Hop Buys` need a companion in the
   chain-proposal output itself?** The proposal is emitted to the
   author at runtime and currently narrates the re-entry verdict
   and the R6 predicate reasons per child. One clause per child
   naming what it buys would put the argument in front of the
   agent at the moment it renders the list. That's beyond
   prose-and-placement if it changes what the proposal must
   contain contractually, so it's a question rather than a draft.
2. **Does the write-target set at `SKILL.md:847` need touching?**
   The issue argues it hands over `docs/plans/PLAN-<topic>.md`
   before any journey. Item 4a's reframing means the lede no
   longer names the PLAN as a product, but the security
   enumeration still prints the address. Out of scope for this
   lead; flagged because the item-4a draft is weaker if the path
   is still handed over 800 lines later. Whichever lead owns that
   conflict should know the lede is no longer reinforcing it.
3. **Should the `full-run` exit-path binding at `:583-588` be
   redrafted too?** Item 4a proposes wording but doesn't commit
   to it, because the parenthetical carries `plan_execution_mode`
   contract detail.
4. **Does `/charter` want the same `## What Each Hop Buys`
   treatment?** It has one, informally, at
   `phase-2-chain-orchestration.md:463-511` for `/roadmap` only —
   the model I wrote against. `/vision` and `/strategy` have no
   equivalent. Not this issue's scope; worth recording that the
   pattern would want it in both parents.

## Summary

Drafted all five items as literal candidate text: a three-paragraph
lede purpose statement that lifts the per-type contribution
declarations (WHY/WHAT/HOW/WHEN) out of the four format references
and states the sink-and-source framing; four per-hop passages naming
each child's real machinery and ending on what skipping strands
downstream; a `## Consolidation Judgment` rewritten from 47 lines of
rationale to 34 lines of bound; replacements for all three licensing
sentences; and a `## The Chain Is a Constant` section promoting
`planned_chain:`'s constancy and Phase 1's non-bounding of the
artifact set into `SKILL.md`.

On the (a)/(b) choice I recommend neither alone: put shape (b)'s
general statement and shape (a)'s four passages both in `SKILL.md`
and add nothing to Phase 2, because deferred material only governs
an agent that reaches the hop — the exact failure in #331 — and the
issue's placement defect doesn't apply here, since "what this hop
buys" is a premise rather than a verdict an agent can aim at.

On `SKILL.md:43-46` I recommend rewrite over removal: the pattern's
seven required structural elements don't include the asymmetry
enumeration, so removing it breaks no conformance narrative, but it
does strand four forward references to prose contracts further down
the file. Changing "is the only thing reducing the artifact set" to
"can remove a document only after both documents exist" turns a
stated purpose into a stated bound and keeps the slot.
