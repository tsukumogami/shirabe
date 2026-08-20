# Lead: Which of the drafted replacement passages are premises that belong in the bootstrap, and which are verdicts that must arrive at their state?

## Findings

### 1. What "bootstrap" means under koto, and why koto does not shrink it for you

Before classifying anything, the destination has to be real. I read
koto's contract to find out what an agent actually holds before state 1.

`koto-user/SKILL.md:36-62` gives the whole lifecycle: `koto init <name>
--template <path>`, then `koto next <name>` in a loop, dispatching on the
`action` field. `template-format.md:79-95` defines the directive surface:
each state gets a `## state_name` body section, "the directive text the
agent receives when it calls `koto next` in that state." The
`<!-- details -->` marker (`template-format.md:97-120`) splits a section
into a directive (always returned) and details (first visit or `--full`).

There is no koto-provided preamble. The template's `description:`
frontmatter field is not delivered by `koto next`. So under a koto-driven
`/scope`, the bootstrap is **whatever text remains in
`skills/scope/SKILL.md`**, which loads whole at invocation and never
unloads — the exact surface that produced #331.

This has a consequence the exploration should treat as load-bearing:

**koto directives are additive, not substitutive.** `koto next` output
arrives *on top of* the skill body already in context. koto therefore buys
early-arrival reduction only for text that is physically *removed* from
`SKILL.md` and relocated into the template. A koto adoption that adds a
state machine while leaving `## Why the Artifact Set Shrinks` at
`SKILL.md:472` reproduces #331 with better plumbing — which is the brief's
own load-bearing constraint, now with a mechanism attached. The
premise/verdict cut is a **deletion** instruction first and an ordering
instruction second.

Corollary for the mapping below: "bootstrap" is expensive. Every line
placed there is permanently resident. The default should be a state
directive; bootstrap needs a positive argument each time.

### 2. Inventory of the draft, with candidate text reproduced

The draft (`explore_scope-process-framing_r2_lead-replacement-prose.md` on
`origin/docs/scope-process-framing`, non-durable) contains five numbered
items, one of which has three sub-items and one of which offers two
competing shapes. Quoting the substance here so it survives that branch's
cleanup.

#### Item 1 — Lede purpose statement

Draft placement: after `SKILL.md:21-33`, before the pattern-contract
paragraph at `:35-47`. Three paragraphs.

Paragraph 1:

> The process is the product. Each child runs a workflow — a scoping
> conversation, a research fan-out, a decision bakeoff, a jury, a security
> review — and the artifact it writes is the materialization of that
> workflow: the sink for the step that produced it, and the source for the
> step that follows. `/plan` is handed a DESIGN because a DESIGN is what
> `/design` finished holding. That is why the chain has four hops instead
> of one.

Paragraph 2:

> A run is not a way to obtain four documents. "Should we produce this
> artifact" is not a question the chain asks, at Phase 1 or anywhere else.
> What each type owes the chain is one **contribution** — the single thing
> it adds that no other type does, small enough to compress into one
> section of whatever document outlives it. BRIEF contributes WHY: the
> problem the feature solves and the outcome a user should experience. PRD
> contributes WHAT: the requirements the feature must meet and the criteria
> that decide it's done. DESIGN contributes HOW: the technical approach,
> the alternatives weighed, and why this one. PLAN contributes WHEN: the
> order the work happens in, and what each unit depends on. Each child's
> format reference declares its own; Phase 2 reads them.

Paragraph 3:

> The reduction question `/scope` does ask is narrow, local, and late:
> given two documents that exist, does the upstream hold anything *beyond*
> its contribution that folding into the downstream would lose? An agent
> holding this file and no artifacts cannot answer that about a document
> nobody has written, and shouldn't try.

#### Item 2 — Four per-hop passages, under a `## What Each Hop Buys` heading

Draft placement: at `SKILL.md:532`, where `## Consolidation Judgment`
currently starts, i.e. replacing `## Why the Artifact Set Shrinks`
(`:472-530`).

> **`/brief`** converts a topic string into a stated problem and a stated
> outcome, then puts concrete user journeys and a scope boundary under
> them. Two reviewers read the result in parallel: one checks that the
> Problem Statement states a problem rather than a smuggled solution and
> that the journeys are distinct and exercisable, the other checks
> structure and visibility. Both must pass before the BRIEF is Accepted.
> Skip the hop and `/prd` writes requirements against whatever the topic
> string implied, with no agreed problem to test them for relevance
> against.

> **`/prd`** turns that problem and outcome into requirements with
> acceptance criteria. Phase 1 is a scoping dialogue with coverage
> tracking, and it hands Phase 2 a set of research leads that specialist
> agents investigate in parallel — so the requirements are written against
> what the codebase and its ecosystem actually support, not against a
> guess. A three-agent jury then reads the draft, because authors
> consistently miss ambiguity and testability gaps in their own writing.
> Skip the hop and `/design` picks an architecture with no statement of
> what the thing must do: nothing bounds the alternatives, and nothing
> decides when the feature is done.

> **`/design`** is where the alternatives get weighed. Phase 1 decomposes
> the problem into independent decision questions; Phase 2 runs `/decision`
> against each one in parallel, at equal depth — a bakeoff with adversarial
> agents, peer revision, and cross-examination, per question. Phase 3
> cross-validates the assumptions those decisions made against each other,
> and always runs, even with one decision. Phase 5's security review always
> runs too; its output may be N/A but the review is not optional. Phase 6
> checks that the rejected alternatives were argued rather than propped up.
> Skip the hop and the PLAN sequences an approach nobody compared to
> anything, and no security review happens anywhere in the chain.

> **`/plan`** decomposes the DESIGN into atomic issues, sequences them, and
> maps the dependency graph. A value-confirmation guard checks that each
> unit delivers observable incremental value and can fail, naming the unit
> and the reason it failed. Phase 6 hands the whole artifact to
> `/review-plan`, which challenges it on scope, design fidelity, whether
> the acceptance criteria discriminate, and sequencing integrity. Design
> fidelity is the check with nothing to read when no DESIGN exists — a PLAN
> reached without one still validates, and still passes review, because the
> reviewer can only measure fidelity against what it is given.

The draft also offers a shape (b) general statement:

> Every hop produces something the next hop consumes, and the consumption
> is literal: Phase 2 invokes each child with the path of the artifact
> above it, not with the topic slug. `/brief` buys an agreed problem and
> outcome. `/prd` buys requirements a design can be bounded by, researched
> by agents that fanned out on the leads and read by a three-agent jury.
> `/design` buys a compared approach, an argued set of rejected
> alternatives, and a security review that runs whether or not it finds
> anything. `/plan` buys a sequence, a dependency graph, and an adversarial
> pass over both.
>
> Skipping a hop doesn't buy a smaller artifact set. It hands the next
> child less to work from, and the next child has no way to tell that from
> a thin upstream.

The draft recommends shipping **both** (a) and (b) in `SKILL.md` and
nothing in Phase 2. I disagree with that recommendation under koto; see
§4.2.

#### Item 3 — `## Consolidation Judgment` rewritten as a bound

Replaces `SKILL.md:532-578` (47 lines → 34).

> A `/scope` run has exactly one mechanism that removes a document from
> disk, and this is it. After each child returns and its artifact
> validates, Phase 2 judges the hop this run drew — the artifact that just
> landed, against the artifact this run handed the child as its invocation
> argument — and reaches `keep` or `absorb`. On `absorb`, the upstream's
> contribution is carried into the survivor as one section immediately
> after `## Status`, every link to the upstream is re-pointed, the survivor
> declares what it took in via `absorbed:` and a `## Status` absorption
> line, and the upstream is deleted. Nothing else in a `/scope` run deletes
> a document.
>
> Three bounds hold at this altitude:
>
> - **It runs only after both artifacts exist.** The judgment fires only
>   when both endpoints of the edge appear in `chain_ran:`. An artifact
>   held back by re-entry protection was never a party to a judgment; an
>   artifact nobody wrote cannot become one by assertion.
> - **It decides against the two documents, never against their types.** No
>   check anywhere in the judgment may read either type's required-section
>   list or compare the two types' section sets. The test for a violation:
>   a condition that refuses one pair while permitting its structural twin
>   under identical repository state is a type rule.
> - **Nothing is deleted without a carry check.** Before any deletion,
>   itemize where each of the absorbed artifact's concerns landed,
>   including every contribution the ancestor was itself carrying. Anything
>   that didn't arrive aborts the absorb and leaves both artifacts in
>   place.
>
> The full procedure — eight steps, the citation preflight that can reach
> no outcome stronger than `keep`, the rollback table, the firing
> condition, why the judgment exists at all, and the prohibition on
> reintroducing a durable-artifact floor — lives in the Consolidation
> Judgment section of
> `skills/scope/references/phases/phase-2-chain-orchestration.md`.

#### Item 4a — `SKILL.md:29`, the PLAN-as-product sentence

Current text, verified at `SKILL.md:27-33`: "lands at one of three terminal
exits: a `full-run` that produces a PLAN at `docs/plans/PLAN-<topic>.md`".

> ...and lands at one of three terminal exits: a `full-run`, whose last hop
> consumes the DESIGN and deposits a PLAN at
> `docs/plans/PLAN-<topic>.md`, a `re-evaluation` exit that writes a
> Decision Record at a settled-upstream boundary (PRD or DESIGN), or an
> `abandonment-forced` exit that force-materializes the most-recently-
> running child's intermediate as a Draft artifact.

#### Item 4b — `SKILL.md:442-445`, direct entry

Current text, verified at `SKILL.md:442-445`: "An author who wants to start
above `/brief` still invokes `/design` or `/plan` directly. That buys a
shorter conversation, not a smaller artifact set: inside `/scope`, the set
is settled per hop after the artifacts land."

> An author who wants to start above `/brief` invokes `/design` or `/plan`
> directly, and that stays supported — all four children ship as standalone
> entry points. Be exact about what it gives up. `/plan` invoked with a
> topic string plans against the string: it has no DESIGN to decompose, so
> the sequencing rests on whatever the invoker inferred, and
> `/review-plan`'s design-fidelity check has nothing to read. The same
> holds one hop up — `/design` with no PRD weighs alternatives against no
> stated requirement. Entering above `/brief` asserts that the skipped
> steps were already taken somewhere else. Inside `/scope`, they're taken
> here.

#### Item 4c — `SKILL.md:43-46`, the reduction conclusion in the lede

Current text, verified at `SKILL.md:43-46`: "a post-hoc consolidation
judgment that is the only thing reducing the artifact set and runs only
after the artifacts exist".

> ...and the prose contracts after them bind the `/scope`-specific
> asymmetries the tactical chain introduces (two settled-upstream
> boundaries, Mandatory-with-auto-skip re-entry protection on every child,
> a post-hoc consolidation judgment that can remove a document only after
> both documents exist, a refuse-and-redirect Slot 5 shape for PLAN's
> downstream-owned lifecycle states, and a terminal child with two output
> modes).

#### Item 5 — `## The Chain Is a Constant`

Draft placement: immediately before `## Chain-Proposal Output`
(`SKILL.md:421`).

> `planned_chain:` is the literal list `[brief, prd, design, plan]` on
> every run. Phase 1 has no input that can shorten it and no field that
> records a different shape — not the topic string, not the execution-mode
> flags, not an `--upstream` document, not the size of the work in front of
> you. Re-entry protection can hold a child back when its artifact is
> already settled on disk, and that's recorded under its own name in
> `chain_skipped:` with the reason; it doesn't subtract from
> `planned_chain:`.
>
> Nothing here bounds how many artifacts a run ends with. That's Phase 2's
> call, made per hop against two documents that exist. Hold the two facts
> apart. A constant chain is not a promise of four documents, and a
> reducible artifact set is not a licence to run fewer steps.

### 3. The rule needs four categories, not two

Applying premise/verdict to the inventory above, two items refused to
classify: item 3's three bounds and item 5's second paragraph. Both are
neither a reason to act nor a conclusion the agent has to earn. Forcing
them into the binary is what makes the classification feel strained.

The cut that actually falls out of the material:

- **Premise** — a reason the work is worth doing. Input to action.
  Must arrive at or before the state that acts on it. Cannot be cited to do
  less.
- **Verdict** — the conclusion of a decision the agent has not yet earned.
  Must not arrive before the work it judges.
- **Bound** — a constraint on a capability. It only ever subtracts legal
  moves, so it is always safe early. Belongs in bootstrap whenever it
  constrains something the agent could attempt at any state; belongs at the
  state otherwise.
- **Obituary** — narration of a withdrawn design. Addressed to a
  maintainer, not to a running agent. Belongs in no state directive. See
  §6.

The operational test that separates premise from verdict, which the draft
implies but never states:

> **Can the agent cite this text as a reason to do less?**

Grammatical form does not decide it. `SKILL.md:474-478` ("Sparing the
reader that is worth doing") is grammatically a premise — a reason — and it
is the sentence #331's agent quoted back at the skill to justify producing
one document. It fails the test. "Phase 5's security review always runs
too" passes: there is no way to read it as licence.

### 4. Passage-by-passage classification and state mapping

Assumed state sequence (per the brief): `phase_0_setup`, `phase_1_discovery`,
`chain_proposal`, then per hop `hop_brief` / `judge_brief_prd`, `hop_prd` /
`judge_prd_design`, `hop_design` / `judge_design_plan`, `hop_plan`, then
`phase_3_exit`, `phase_4_cleanup`. Judgment states are separate from hop
states because the judgment fires only when both endpoints are in
`chain_ran:` (`phase-2-chain-orchestration.md:503-505`) — which is a
different precondition from "the child returned."

#### 4.1 Item 1, the lede — split three ways, not kept whole

**Paragraph 1 (process-is-the-product): premise. Bootstrap.** It states
why the chain has four hops. There is nothing to aim at: an agent cannot
use "the artifact is the materialization of the workflow" to skip the
workflow. It passes the citation test. Keep verbatim. This is the single
strongest thing in the draft and the file currently has no equivalent —
established: nothing in `SKILL.md`'s 968 lines argues that an outcome is
worth wanting except the section being deleted.

**Paragraph 2, first two sentences: bound. Bootstrap.** "A run is not a way
to obtain four documents. 'Should we produce this artifact' is not a
question the chain asks, at Phase 1 or anywhere else." This forecloses a
move. It cannot license one. Keep verbatim in bootstrap.

**Paragraph 2, the four contribution declarations: I disagree with the
draft. These are not bootstrap material.**

The draft's reason for lifting them is real — "contribution" appears eight
times in `SKILL.md` with no local referent — but the fix is
over-delivered. Two separate things are being conflated:

1. *What kind of thing a contribution is* — "the single thing a type adds
   that no other type does, small enough to compress into one section of
   whatever document outlives it." This is the operational definition. It
   is what the eight uses need. It is a bound (it says how small the thing
   is). **Bootstrap.**
2. *The four values* — WHY / WHAT / HOW / WHEN, one sentence each. These
   are only ever consumed by the consolidation judgment, which asks
   "does the upstream hold anything beyond its contribution"
   (`phase-2-chain-orchestration.md:596-599`). That question is asked per
   hop, against one pair. **The judgment state for that hop, and only the
   pair being judged.**

Delivering all four values in the bootstrap is worse than merely
unnecessary. Four sentences that summarize what an entire BRIEF, PRD,
DESIGN and PLAN each contain, in front of an agent that has written none of
them, *is a compression recipe*. It is the raw material for exactly the
Status section #331's agent wrote. It fails the citation test: an agent can
cite it as "I know what each of these would have said."

The child skills already declare their own contribution in their format
references (`skills/brief/references/brief-format.md:503-504`,
`prd-format.md:249-250`, `design-format.md:364-365`,
`plan-doc-structure.md:309-310`, per the draft's source list). The child
reads its own. The parent does not need to tell it. The draft names this
fallback itself ("one sentence plus a pointer") and rejects it for lack of
a local referent; the split above keeps the local referent and drops the
recipe.

**Paragraph 3: bound. Bootstrap, verbatim, highest priority.** "An agent
holding this file and no artifacts cannot answer that about a document
nobody has written, and shouldn't try." This is the only line in the whole
draft addressed at precisely the agent-state that produced #331 — holding
`SKILL.md`, holding no artifacts. It is second person, present tense,
reason attached: the register model at
`phase-2-chain-orchestration.md:719-739`. It only subtracts. It must be
resident for the whole run, which is what bootstrap means.

#### 4.2 Item 2, the four hop passages — the draft's placement argument is dissolved by koto

Each passage has two halves, and they classify differently.

**The machinery inventory** ("two reviewers read the result in parallel",
"a three-agent jury then reads the draft", "Phase 2 runs `/decision`
against each one in parallel"): premise, **but aimable**, and the draft
knows it — "an agent looking for a reason to skip can read 'two reviewers'
as cheap." The draft calls this a wording problem. It is more than that.

An inventory of a hop's machinery is a **cost disclosure**. Telling an
agent up front that `/design` runs a per-question adversarial bakeoff plus
an unconditional security review is telling it the price. Cost disclosed
before value is earned is the asymmetry that produces skipping, and it is
structurally the same defect as disclosing a verdict early: both hand the
agent something it can act on before it has done the work that would let it
judge. So the machinery half fails the citation test at bootstrap and
passes it at the hop, where the agent is inside the work.

**The "skip and X strands downstream" clause**: premise, non-aimable in the
useful direction. It only ever adds reason to run. Safe anywhere.

Now the placement. The draft recommends both shapes in `SKILL.md` and
nothing in Phase 2, on this reasoning:

> Deferred material only governs an agent that reaches the deferral point.
> An agent that skips the hop never reads the Phase 2 passage — which is
> precisely the failure in issue #331 [...] Putting the only motivating
> text at the hop reproduces the defect with the polarity reversed.

**That argument is correct for a plain skill and is dissolved under koto.**
Under a whole-file skill, whether the agent reaches Phase 2's text is the
agent's own choice, so deferral is unreliable. Under koto, the machine
transitions into `hop_design` and `koto next` hands the agent that state's
directive whether or not it wanted the hop. Reaching the hop stops being a
choice. The gate becomes structural rather than textual, and per-hop
material at the hop *does* govern.

Recommendation, revised for koto:

- Shape (b)'s **first sentence only** in bootstrap: "Every hop produces
  something the next hop consumes, and the consumption is literal: Phase 2
  invokes each child with the path of the artifact above it, not with the
  topic slug." Premise, non-aimable, no machinery, no cost.
- Shape (b)'s **"Skipping a hop doesn't buy a smaller artifact set"**
  paragraph in bootstrap. Bound.
- Shape (a)'s **four passages distributed one per hop state** — the
  `hop_brief`, `hop_prd`, `hop_design`, `hop_plan` directives. The
  machinery half is then read by an agent about to run that machinery, and
  the downstream-consequence clause closes it, exactly as drafted.
- **Delete shape (b)'s per-child summary sentences.** Once (a) lives at the
  hops, the four-clause summary in bootstrap is a second, smaller cost
  disclosure with no compensating reason. This is the duplication the draft
  accepted and koto makes unnecessary.

Net against the draft: same text, roughly half the bootstrap, no
duplication.

**Load-bearing dependency**: this holds only if the hop states are
unconditional transitions rather than evidence-routed on an agent-supplied
"should this hop run" field. `template-format.md:74-77` allows conditional
transitions with a `when` clause, and Layer 2 is evidence routing. If a
`/scope` template routes hop entry on agent evidence, the skip is back and
so is the draft's original argument. Flagged to the substrate lead.

#### 4.3 Item 3, `## Consolidation Judgment`

The draft's core move — strip the rationale, keep the bound — is right, and
it is the most direct available fix for #331. Verified: `SKILL.md:534-537`
and `phase-2-chain-orchestration.md:491-495` say the same thing about three
documents costing a reader three reads, and only the Phase 2 copy is
labelled `**Why it exists.**` and sits under the mechanism it justifies.

Split for the state sequence:

- **"A `/scope` run has exactly one mechanism that removes a document from
  disk [...] Nothing else in a `/scope` run deletes a document."** — bound,
  **bootstrap**. It forecloses the agent inventing a second deletion route
  at any state, so it must be resident throughout. Note this also absorbs
  the single-mechanism fact that item 4c removes from the lede, which is
  the draft's own accounting and is correct.
- **Bound 1, "It runs only after both artifacts exist"** — bound,
  **bootstrap**. Same reason: it constrains an assertion the agent could
  make at any state. This is the anti-#331 bound in its most compact form.
- **Bound 2, "decides against the two documents, never against their
  types"** — bound, **`judge_*` states**. It constrains a check performed
  only inside the judgment. Nothing earlier can violate it.
- **Bound 3, "Nothing is deleted without a carry check"** — bound,
  **`judge_*` states**. Same.
- **The reader-economy rationale** (currently `SKILL.md:474-478`) —
  **verdict-behaving premise; `judge_*` states only.** It is grammatically
  a reason but fails the citation test: it is the sentence the incident
  quoted. Under koto it is physically absent from context until both
  artifacts exist, which is the outcome the whole exercise wants. It
  already lives correctly at `phase-2-chain-orchestration.md:490-500`; the
  koto version routes the same text into the judgment state's directive (or
  its `<!-- details -->` half, since it is first-visit material).
- **The pointer to the full procedure** — **`judge_*` states**, as
  `<!-- details -->`.

#### 4.4 Item 4a, PLAN-as-product

Premise fix. **Bootstrap** — it must be, because the sentence it repairs is
at `SKILL.md:29` in the lede and the lede is bootstrap by construction. The
rewrite's mechanism is sound: an agent cannot reach
`docs/plans/PLAN-<topic>.md` in that sentence without also reading that
consuming a DESIGN is how it gets there.

The draft's open question 2 asks whether `SKILL.md:847` (the write-target
set) undercuts this. I checked. The security enumeration is a **bound**,
and bounds must be in bootstrap — it is the "closed write-target set"
pattern surface (`SKILL.md:824-834`), and `SKILL.md:838-841` already reads
"The PLAN is never a deletion target of a fold. At the terminal hop it is
the *survivor*." The path appears there as a survivor and a mutation
target, not as a product. No conflict; the draft can drop that worry.

#### 4.5 Item 4b, direct entry — a third destination

The draft's replacement is a strict improvement on `SKILL.md:442-445`: it
disclaims the *input* rather than the *artifact set*, and it names a
checkable mechanism (`/review-plan`'s design-fidelity category has nothing
to read). Keep the content.

But the placement is wrong in both the draft and the current file, and koto
makes that visible. The passage is addressed to an **author choosing an
entry point**. An agent already inside a `/scope` run is past that choice.
Under koto it is past it structurally — the machine is initialized. Telling
that agent "invoking `/design` or `/plan` directly stays supported" is a
licensing sentence delivered to a party who cannot legitimately act on it,
and no amount of following prose changes that.

So: a third destination beyond bootstrap and state directives —
**author-facing routing text**, i.e. the skill `description:` frontmatter
and whatever `/explore` reads when it routes. Not a state directive at all.
If the exploration wants it in `SKILL.md` for discoverability, it belongs
in the `## Input Modes` region (`:74-101`), where a reader is choosing how
to enter, and not in the chain-proposal region where an agent is choosing
whether to comply.

#### 4.6 Item 5, `## The Chain Is a Constant` — koto eats most of it

**Paragraph 1 is largely superseded by the substrate.** "`planned_chain:`
is the literal list `[brief, prd, design, plan]` on every run [...] Phase 1
has no input that can shorten it" is a *prose promise about a machine
property*. Under koto the state graph in the template frontmatter is that
property, enforced by the compiler and the transition rules, not by an
agent's compliance with a paragraph. Recommendation: keep one sentence
("the chain is the same four hops on every run; nothing in Phase 1
shortens it") in bootstrap and drop the enumeration of non-inputs. This is
a genuine koto dividend — the draft wrote that enumeration for a substrate
where prose was the only enforcement.

The re-entry-protection sentence stays, because `chain_skipped:` is a state
field the agent writes and can write wrongly. Bound. Bootstrap.

**Paragraph 2 is the best two sentences in the draft.** "Hold the two facts
apart. A constant chain is not a promise of four documents, and a reducible
artifact set is not a licence to run fewer steps." Bound. **Bootstrap,
verbatim.** It names the exact composition error #331 committed, and it
only subtracts.

#### 4.7 Summary table of the mapping

| Passage | Category | Destination |
|---|---|---|
| Item 1 ¶1, process-is-the-product | premise | bootstrap |
| Item 1 ¶2 first two sentences | bound | bootstrap |
| Item 1 ¶2, operational def. of "contribution" | bound | bootstrap |
| Item 1 ¶2, the four WHY/WHAT/HOW/WHEN values | premise, aimable | `judge_*`, pair-local |
| Item 1 ¶3, "cannot answer, shouldn't try" | bound | bootstrap |
| Item 2, shape (b) first sentence | premise | bootstrap |
| Item 2, shape (b) "skipping doesn't buy" ¶ | bound | bootstrap |
| Item 2, shape (b) four-clause summary | premise, aimable | cut |
| Item 2, shape (a) machinery halves | premise, aimable | `hop_<child>` |
| Item 2, shape (a) strands-downstream clauses | premise | `hop_<child>` |
| Item 3, single-deletion-mechanism sentence | bound | bootstrap |
| Item 3, bound 1 (both artifacts exist) | bound | bootstrap |
| Item 3, bounds 2 and 3 | bound | `judge_*` |
| Item 3, reader-economy rationale | verdict-behaving | `judge_*` details |
| Item 3, procedure pointer | reference | `judge_*` details |
| Item 4a, PLAN-as-deposit rewrite | premise | bootstrap |
| Item 4b, direct-entry rewrite | premise, author-facing | routing text / Input Modes |
| Item 4c, bound-not-purpose clause | bound | bootstrap |
| Item 5 ¶1, constant chain | superseded | one sentence, bootstrap |
| Item 5 ¶1, re-entry recording | bound | bootstrap |
| Item 5 ¶2, hold-the-two-facts-apart | bound | bootstrap |
| Obituaries (§6) | obituary | DESIGN amendment; no state |

### 5. Stress-testing the rule

Six failure modes, in descending order of how much they matter.

**5.1 Premise/verdict is not a property of the text. It is a property of
the text plus the agent's freedom at that state.**

This is the central failure mode and it reframes the whole exercise. The
same sentence behaves as a premise where the agent has no choice and as a
verdict where it does. "Phase 5's security review always runs" is inert at
`hop_design`, where the agent is inside `/design` and about to run it. The
same sentence at `chain_proposal`, where the agent is being asked to
confirm a chain, is a cost disclosure it can price. The draft's own
weakest moment — "an agent looking for a reason to skip can read 'two
reviewers' as cheap [...] that is a wording problem, not a placement
problem" — is this failure mode misdiagnosed. It is a placement problem,
and koto is what lets you fix it by placement.

Practical consequence: the classification must be redone against the actual
state graph, not against the phase list. Wherever the graph gives the agent
a branch, treat premises delivered at that branch as verdicts.

**5.2 The bootstrap does not shrink for free.** §1. koto directives are
additive. Any passage classified "bootstrap" is permanently resident, and
any passage classified "state" must be *deleted from `SKILL.md`*, not
merely echoed in a template. A koto adoption that leaves `SKILL.md:472-530`
in place while adding per-hop directives makes #331 strictly worse, because
the agent now holds the reduction argument *and* four machinery inventories
at Phase 0.

**5.3 Precondition leakage: a bound whose setup is earlier than its
verdict.** The consolidation judgment is correctly deferred. But
`phase-2-chain-orchestration.md:614-624` requires the contribution section
be composed **from the survivor's own body**, not from the document about
to be deleted — "Sourcing from the survivor is what makes a single
unreviewed authoring site tolerable." That constrains how the *survivor*
was written, which happened in an earlier state. If `hop_prd` produced a
PRD that never restated the brief's problem in its own words, `judge_brief_prd`
Step 3 has nothing to compose from and the carry check aborts a fold that
should have succeeded.

So a bound can be deferred correctly and still fail, because its
precondition was foreclosed upstream. The fix is not to move the verdict
earlier — that reintroduces #331 — but to state the *precondition* at the
hop without stating the verdict. Something like "write the PRD so it stands
on its own body" is a hop-state instruction that costs nothing and does not
disclose that a fold may follow.

**5.4 Deferred-verdict foreclosure, the general case.** The brief asks
about a verdict deferred so far the agent reaches its state having already
foreclosed it. §5.3 is the concrete instance I found. The general shape:
any verdict whose inputs are produced by earlier states is vulnerable. In
`/scope` the exposed verdicts are the citation preflight (an agent that
added cross-references during a hop can force `keep` without realizing) and
the carry check. Both are bounded by the same remedy: hop-state
preconditions stated as craft instructions, not as forecasts of the
judgment.

**5.5 Premise inflation.** Without the citation test (§3), anything can be
relabeled a premise — including the reader-economy argument, which is
literally the premise the consolidation judgment rests on. That relabeling
would restore `SKILL.md:474-478` to the bootstrap and undo the entire fix.
The test is what gives the cut teeth, and it needs to be written down
alongside the cut, not left implicit.

**5.6 Bounds are safe early, which is a rule and not an intuition.** A
bound cannot license, only forbid, so front-loading bounds carries no #331
risk. This is why the draft's item 3 rewrite works and why item 4c's
"can remove a document only after both documents exist" is strictly better
than "is the only thing reducing the artifact set" — same fact, one states
a capability limit and one states a mission. Worth stating explicitly
because the alternative intuition ("defer everything, it's safer") is
wrong and would starve the bootstrap of the constraints that stop the
incident.

### 6. The past-tense passages — a third thing, and the brief's inventory needs correcting

The brief lists six passages "narrating withdrawn designs in the past
tense," at `:472-489`, `:499-506`, `:508-517`, `:519-530`, `:872-881`, and
`:813`, totalling "roughly 30 of the purpose-bearing section's 60 lines."
I read all six. Three of the six are misclassified and the line count is
roughly double.

- **`:485-489` — genuine obituary.** "An earlier revision of this skill
  decided per hop, before each artifact existed, whether the child was
  worth invoking; the party making that call was the one that benefited
  from not doing the work." Five lines. (`:474-484`, the rest of that
  range, is present-tense argument, not narration.)
- **`:499-506` — genuine obituary.** "A briefly-shipped revision of this
  skill also let Phase 1 choose an entry altitude for the chain. It was
  withdrawn." Eight lines.
- **`:508-517` — not an obituary.** It is a present-tense rule ("A shorter
  conversation is still reached by invoking a child directly", "All four
  children ship as standalone entry points") with one past-referencing
  hinge: "What it no longer is, is the route to a smaller artifact set."
  Item 4b already replaces this content.
- **`:519-530` — not an obituary.** Same shape: "What it no longer means is
  a fixed outcome", followed by present-tense rule statement ("Every hop is
  decidable", "There is no durable-artifact floor").
- **`:872-881` — a changelog, not an obituary.** "Three corrections are
  folded into that enumeration, each a pre-existing defect rather than a
  consequence of this change." It narrates *fixes to this file*, not a
  withdrawn design. Ten lines.
- **`:813` — not past-tense narration at all.** I read it. The clause is
  "(the same `gh` surface it used to author and post the body)" — a
  back-reference to something the same run did earlier in its own
  lifecycle, inside the coordinated-abandonment paragraph. It is
  operationally live. It should come off the list.

So: two genuine obituaries (13 lines), one changelog (10 lines), two
present-tense rules with a "no longer" hinge, and one misidentification.
Roughly 13 of the section's 59 lines are obituary, not 30.

**Where they go: nowhere in the state sequence.** They are a fourth
category. They are not premises — an agent cannot act on "an earlier
revision decided per hop." They are not verdicts — they conclude nothing
about this run. Their audience is a *maintainer* considering re-adding a
withdrawn design, and that reader does not run `koto next`.

Destinations, split by what each obituary is doing:

- The **history** goes to the DESIGN doc's amendment record, which already
  carries this kind of material at
  `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:822`
  and `:871`.
- Where a **live prohibition** follows from the history, state the
  prohibition in the present imperative at the reference a maintainer
  reads. The model already exists and is the right one:
  `phase-2-chain-orchestration.md:719-731`, "**Do not add a guard that
  forces `keep` on the ground that the survivor would be the last
  artifact.** The single-mechanism rule will not catch such a guard [...]
  so this prohibition has to be written down rather than derived." That is
  an obituary converted into a live rule, and it demonstrates the
  conversion.

Applying it to the two genuine obituaries: `:485-489`'s live content is
"nothing may decide a hop before the hop's artifact exists" — already
covered by item 3's bound 1 and item 1 ¶3. `:499-506`'s live content is
"Phase 1 may not choose an entry altitude" — under koto this is enforced
by the state graph having one entry, so it becomes a *template invariant*
plus a maintainer note, not agent-facing prose. Both can be deleted from
`SKILL.md` outright with their live halves already placed.

The **changelog** at `:872-881` is the easiest call: it belongs in the
DESIGN amendment and nowhere else. It is ten lines of diff commentary
sitting inside a security-contract section, and it fails the audience test
completely — no running agent, and no maintainer reading the write-target
set, needs to know which three pre-existing defects a past PR folded in.

### 7. Paperwork

**The DESIGN amendment: holds, with a formatting correction.**
`docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` is 901
lines and already carries two amendments, at `:822` and `:871`. A third
appended `## Amendment` paragraph is the established form. Correction to
the brief: the existing headings use an **em dash**, `## Amendment —
2026-08-15` (verified via `cat -A`: `M-bM-^@M-^T`), not `--`. Match the
file.

**The `phase-0-setup.md:315` citation: holds.** Verified verbatim:
`"Why the Artifact Set Shrinks" section of `skills/scope/SKILL.md`.` It is
a by-title citation of a section this work deletes or renames, and it needs
the edit.

**A third by-title reference the brief did not list.**
`docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:427`
contains `# New "## Why the Artifact Set Shrinks" section — the
reader-facing rationale, stated here rather than cited from /brief`, inside
a fenced component-changes block under `## Solution Architecture`
(`:421-431`). It goes stale the moment the section is renamed. Because it
is a historical record of what a past change did, editing the block in
place would falsify the record; the amendment paragraph should note the
supersession instead. Flagging it because a grep for the section title
finds three hits, not two.

**What a koto shape adds.** Three items, all real:

1. **A template file.** `koto-user/SKILL.md:40-45` requires
   `koto init <name> --template <path>`, conventionally
   `${CLAUDE_SKILL_DIR}/koto-templates/<workflow>.md`. That is a new
   durable file, and `template-format.md:89-95` requires every state
   declared in frontmatter to have a matching `## state_name` body section
   or the compiler rejects it.
2. **A row in the `## Reference Files` table** at `SKILL.md:403-419`, which
   currently lists twelve files and no template.
3. **A conformance question on Resume Logic.** `SKILL.md:322-361` is a
   prose resume ladder bound to
   `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md`
   (rows 1-4 and 8-9 pattern-level, rows 5-7 parent-specific). koto owns
   resumption — sessions persist atomically and every transition is
   recoverable (`koto-user/SKILL.md:9`). A koto-driven `/scope` either
   keeps the prose ladder as a second, now-redundant resume mechanism or
   binds Slot 5-7 to koto session state. Either way the parent-skill
   pattern's required structural element list has to say which. That is
   paperwork against
   `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md:674-706`, not
   just against `/scope`, and it is the largest piece of paperwork the koto
   shape adds. Out of this lead's scope; recorded.

## Implications

**The content work and the koto adoption are not independent, and the
dependency runs one way.** koto governs when a directive arrives, and that
is exactly the lever the premise/verdict cut needs. Two of the draft's
recommendations were shaped by the absence of that lever and should be
revised now that it exists: the (a)+(b) duplication in `SKILL.md` (§4.2)
and the prose enumeration of `planned_chain:`'s constancy (§4.6). Both were
correct answers to "prose is the only enforcement." Neither is the best
answer to "the state machine is the enforcement."

**The bootstrap is the deliverable, and it should be small.** Everything
classified "bootstrap" above is permanently resident in every `/scope`
run. My mapping puts roughly eight short passages there: process-is-the-
product, the two foreclosure sentences, the contribution definition, the
"cannot answer, shouldn't try" line, the hop-consumption sentence, the
single-deletion-mechanism bound, the both-artifacts-exist bound, the
constant-chain sentence, and hold-the-two-facts-apart. That is a bootstrap
of purpose and bounds with no machinery inventory, no reader-economy
argument, and no obituaries — which is close to the inverse of what
`SKILL.md` currently front-loads.

**The reader-economy sentence's placement is now decidable.** #331's agent
quoted `SKILL.md:474-478` back at the skill. Under koto, that text is in
the `judge_*` state's directive and is physically absent from context until
both artifacts exist. That is not a rhetorical fix or a wording fix; it is
the mechanism the issue was asking for. It is the strongest argument in
this lead for the koto adoption being worth doing at all.

**A deletion budget falls out.** `SKILL.md:472-530` (59 lines) goes
entirely: 13 lines of obituary deleted outright, the reader-economy
rationale relocated to the judgment state, the direct-entry paragraph
rewritten and relocated to author-facing text, the durable-artifact-floor
and re-entry sentences absorbed into item 5's bootstrap paragraph.
`:532-578` shrinks by the draft's accounting (47 → 34) and then splits again
by §4.3, with only about half of the 34 staying in bootstrap. `:872-881`
(10 lines) goes to the DESIGN amendment. Against that, bootstrap gains the
passages listed above. The file should end meaningfully shorter, which is
the opposite of what a naive "add per-hop purpose prose" reading would
predict.

## Surprises

**The draft's strongest reasoning is the part koto invalidates.** The
(a)-plus-(b) recommendation is argued carefully and from the incident
itself — "deferred material only governs an agent that reaches the
deferral point [...] which is precisely the failure in issue #331." It is a
good argument about a skill whose control flow is the agent's compliance
with prose. It stops applying the moment control flow is a state machine.
Nothing else in the draft depends on that premise, so the rest survives
intact, but this is the one place where the koto context changes an answer
rather than just relocating text.

**The four contribution declarations are the most dangerous thing in the
draft.** The draft lifts them into the lede as a fix for an undefined term
and flags the risk it worries about (lede length). The risk that matters is
different: four sentences summarizing what each of the four documents
contains, delivered to an agent holding none of them, is a compression
recipe for exactly the Status section the incident produced. The draft's own
rejected fallback — one sentence plus a pointer — is the safer shape, and
the reason to prefer it is not lede length.

**`SKILL.md:813` is not what the brief thought it was.** It reads "the same
`gh` surface it used to author and post the body," a within-run
back-reference in the coordinated-abandonment paragraph, not a withdrawn-
design obituary. And the obituary count in the purpose-bearing section is
about 13 lines, not 30 — the higher figure comes from counting
present-tense rule statements that happen to contain a "no longer" hinge
(`:508-517`, `:519-530`) as past-tense narration. Both of those ranges are
live rules that need rewriting, not history that needs deleting, and
treating them as obituaries would delete live content.

**A third by-title reference exists.**
`DESIGN-scope-consolidation-over-skipping.md:427` names `## Why the
Artifact Set Shrinks` inside a fenced architecture block. The paperwork is
three references, not two.

**Premise/verdict needed a third and fourth category almost immediately.**
Two of the draft's five items would not classify under the binary. Bounds
and obituaries are not edge cases here — bounds are most of what should be
in the bootstrap, and obituaries are most of what should be deleted.

## Open Questions

1. **Are the hop states unconditional?** My revision of the draft's
   placement recommendation (§4.2) rests entirely on the agent not being
   able to skip a hop state. `template-format.md` Layer 2 supports
   conditional transitions and evidence routing, so a template *could*
   route hop entry on agent evidence. If it does, the draft's original
   (a)+(b) recommendation is right and mine is wrong. This is the single
   question that most changes this lead's output, and it belongs to
   whoever owns the substrate shape.

2. **Where does the `chain_proposal` state's directive sit on the premise/
   verdict cut?** The proposal is emitted to the *author* and asks for
   Proceed / Adjust / Bail (`SKILL.md:421-434`). It is the one state where
   the agent renders a list it could try to trim, so §5.1 says treat
   premises there as verdicts. But it is also the moment the author most
   needs to know what they are agreeing to. I did not resolve this. The
   draft's own open question 1 asks a version of it.

3. **Does the resume ladder survive koto?** §7 item 3. `SKILL.md:322-361`
   and `phase-resume.md` encode a nine-row ladder that duplicates what koto
   session state does natively. Resolving this is a change to the
   parent-skill pattern's required structural elements, which affects
   `/charter` too.

4. **Does the `<!-- details -->` split give a fifth destination?**
   `template-format.md:97-120`: details are returned on first visit or with
   `--full`. That is a real distinction — first-visit-only material for a
   state the agent may re-enter. The reader-economy rationale and the
   procedure pointer are both natural details rather than directives, but I
   have not checked whether a `judge_*` state is ever re-entered in a way
   that would make the difference matter.

5. **Should `/charter` get the same treatment?** The draft's open question
   4 notes `/charter` has an informal per-hop argument for `/roadmap` only,
   at its `phase-2-chain-orchestration.md:463-511`, and none for `/vision`
   or `/strategy`. If the premise/verdict cut is right, `/charter` has the
   same defect with less of the incident evidence. Not this issue's scope.

## Summary

Premise-versus-verdict is the right cut but needs two more categories to be
usable — bounds (constraints that only subtract legal moves, safe early,
and which turn out to be most of what belongs in the bootstrap) and
obituaries (withdrawn-design narration addressed to maintainers, which
belongs in no state directive at all) — plus an operational test that
grammar alone does not supply: can the agent cite this text as a reason to
do less? The rule's real failure mode is that premise-versus-verdict is not
a property of the text but of the text plus the agent's freedom at that
state, which is why the draft's strongest argument — put the per-hop
passages in `SKILL.md` because a skipping agent never reaches the hop —
dissolves under koto, where the machine transitions the agent into
`hop_design` whether it wanted the hop or not; that also means the four
contribution declarations the draft lifts into the lede should not be
there, since four sentences summarizing what each unwritten document
contains is a compression recipe for exactly the Status section #331
produced. The biggest open question is whether the koto template's hop
states are unconditional transitions or evidence-routed on agent-supplied
input, because my entire placement revision rests on the agent not being
able to choose to skip a state, and if it can, the draft's original
recommendation is correct and mine is not.
