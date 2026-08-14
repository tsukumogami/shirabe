# Lead: Can the tactical children receive absorbed content today, and do they read their upstream at all?

## Findings

### 1. The BRIEF's claim about `/prd` is now STALE. #260 shipped the consumption mechanism.

`docs/briefs/BRIEF-scope-consolidation-over-skipping.md:63-66` states:

> "`/prd` records an upstream BRIEF's path and transitions its status, but its
> drafting phase draws the problem, goals, stories, and exclusions from its own
> scoping conversation and never reads the brief's body."

That was true when the brief was written. It is **false today**. `skills/prd/references/phases/phase-3-draft.md:63-85` now carries an explicit consumption block in step 3.2:

> **When an upstream BRIEF exists (Input Mode 2), read it first.** The brief already
> settled this feature's framing, and four of its five required sections map onto
> sections this PRD must carry:
>
> | BRIEF section | PRD section |
> |---|---|
> | Problem Statement | Problem Statement |
> | User Outcome | Goals |
> | User Journeys | User Stories |
> | Scope Boundary (in-list / out-list) | Requirements / Out of Scope |
>
> Draw those four sections from the brief's body, not from this PRD's own Phase 1
> conversation.

And it names the carry check as the reason (`phase-3-draft.md:82-85`):

> "Carrying the framing forward properly is also what makes the downstream
> consolidation judgment usable. `/scope` checks section by section whether this PRD
> carries the brief's four concerns before it removes a redundant brief; a PRD
> written without reading its brief fails that check, and both documents stay."

The per-section drafting guidelines were rewritten to match (`phase-3-draft.md:88-102`): Problem Statement, Goals, User Stories, and Out of Scope each say "Draw from the upstream BRIEF when one exists, otherwise from Phase 1 scope."

Note the asymmetry: **`/prd` Phase 1 (Scope) still does not read the brief.** `skills/prd/references/phases/phase-1-scope.md` has no mention of an upstream at all — it runs the full six-dimension conversational scoping and writes `wip/prd_<topic>_scope.md` from that dialogue alone. So a `/scope`-driven `/prd` still re-derives the framing conversationally in Phase 1, then in Phase 3 is told to prefer the brief's body over what Phase 1 produced. The consumption is a drafting-time override, not an input-time short-circuit.

### 2. `/design` reads the PRD, but is contractually forbidden from carrying it.

`skills/design/references/phases/phase-0-setup-prd.md:25-27` reads the PRD ("Read the PRD file from the path provided in `$ARGUMENTS`"), and steps 0.3 and 0.4 derive from it. But 0.3 is explicit that this is a *translation*, not a carry (`phase-0-setup-prd.md:82-86`):

> "Write the design doc's 'Context and Problem Statement' section. Translate the PRD's
> problem framing into implementation terms... **Don't copy the PRD verbatim.** A design
> doc reader needs a different framing: the PRD explains what to build and why; the
> design doc explains what technical problem needs solving."

Goal statement at `phase-0-setup-prd.md:9`: "**Synthesize (not copy-paste)** the problem statement into technical terms."

Only two DESIGN sections come from the PRD at all: Context and Problem Statement (0.3) and Decision Drivers (0.4). No other phase reads the PRD — grepping `skills/design/references/phases/phase-1-decomposition.md` and `phase-4-architecture.md` for "PRD" returns nothing.

The format reference makes the non-carry a rule, not an accident. `skills/design/references/design-format.md:278-287`:

> "Standing alone is scoped to **this section**. It is not licence to re-narrate the
> rest of the upstream. State the problem in full here, then cite everything the
> upstream already says -- **requirements by their numbers, goals and exclusions by
> reference** -- rather than restating it. A DESIGN that opens by citing its PRD's
> requirement numbers loses nothing; one that re-narrates the PRD in full costs its
> reader a second read of a document they can open."

And `design-format.md:166-167`, under what the DESIGN must NOT contain:

> "**Requirements articulation** -- belongs in the upstream PRD. The DESIGN cites
> requirements (R1, R2, ...) but does not introduce new ones."

`design-format.md:178-179` goes further and pushes content *upward*: "If a DESIGN draft starts introducing new requirements or atomic implementation tasks, **extract that content into the upstream PRD**."

### 3. `/plan` reads the DESIGN deeply — the deepest consumption of the three — and still does not carry it.

`skills/plan/references/phases/phase-1-analysis.md:114-124` is the most literal consumption in the chain:

> - **Implementation Phases**: Copy from design's Implementation Approach section
> - **Success Metrics**: Copy from design's Consequences/Success Criteria sections

and `phase-1-analysis.md:180-184` writes into `wip/plan_<topic>_analysis.md`:

> `## Implementation Phases (from design)`
> `<Copy the Implementation Approach section verbatim>`

Phase 3 decomposes directly from the design's body — `phase-3-decomposition.md:136`: "Break down the 'Solution Architecture' and 'Implementation Approach' sections: each component or distinct change becomes one issue." Its prerequisites list (`phase-3-decomposition.md:37-40`) includes "The original source document."

So `/plan` genuinely decomposes from the DESIGN, not from the topic. But the copies land in `wip/plan_<topic>_analysis.md`, which is non-durable by the wip-hygiene rule and deleted before merge. The durable PLAN itself is bound by the same anti-carry rule (`skills/plan/references/plan-format.md:205-218`):

> - **Technical architecture** -- belongs in the upstream DESIGN. The PLAN references the DESIGN's decisions but does not re-litigate them.
> - **Requirements articulation** -- belongs in the upstream PRD. The PLAN cites requirements (R1, R2, ...) but does not introduce new ones.
>
> [...] extract that content into the upstream DESIGN/PRD/ROADMAP and **replace the PLAN content with a citation**.

`plan-format.md:295-298` confirms the intended shape: the PLAN's scope section is "One or two tight paragraphs. Names the DESIGN's contract and the [...] work covers without opening the DESIGN."

### 4. The crux: Stage 3 verifies a carry; it never performs one.

`skills/scope/references/phases/phase-2-chain-orchestration.md:458-464`:

> "On `absorb`, walk the upstream's required sections one at a time and **record where
> each landed**. This is the receiving mechanism: an absorb that is not itemized is a
> recommendation, and a recommendation with nothing confirming the transfer is how
> content goes missing."

"Record where each landed" is past tense. The four completion steps (`phase-2-chain-orchestration.md:486-496`) are:

> 1. Read the absorbed artifact's own `upstream:` value.
> 2. Set the survivor's `upstream:` to that value, or remove the field when the absorbed artifact had none.
> 3. `git rm` the absorbed artifact.
> 4. Re-run `shirabe validate` on the survivor.

**There is no step that edits the survivor's body.** The only write to the survivor is a frontmatter field re-point. The abort path confirms the reading (`phase-2-chain-orchestration.md:480-484`): "Any `carried: false` **aborts the absorb**: the verdict is downgraded to `keep`, the finding names the section that did not arrive." *Did not arrive* — the arrival is expected to have already happened.

The DESIGN says this outright. `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:255-259`, Decision 5 Option A (chosen):

> "an explicit per-section carry check, recorded as a table, **run before the upstream is
> removed**. For each required section of the absorbed type, the check names where in the
> survivor that concern landed and marks it carried or not-carried."

And D5 at `DESIGN-scope-consolidation-over-skipping.md:106-109`:

> "**Content that moves must be received and verified.** A recommendation that content be
> carried forward is what already failed. Absorption is only legitimate when something
> checks, section by section, that the content arrived."

Received (by the child, at authoring time) *and* verified (by the parent, after the fact). Two different actors.

**So the answer to the crux question is: the carry is performed by the child at authoring time. Stage 3 is a gate, not a mover.** That is precisely why #260 had to touch `skills/prd/references/phases/phase-3-draft.md` at the same time it added the consolidation judgment — the two changes are one mechanism split across a parent and a child. `skills/brief/references/phases/phase-0-setup.md:229-232` names the old failure this fixed:

> "nothing received what it folded: the path recommended `/prd` and named the content to
> carry forward, but `/prd` had no absorb step and no input mode for folded framing, so a
> fold left the framing in the ephemeral source it was supposed to be rescued from."

### 5. No worked example exists on disk. No absorb has ever run.

- Every one of the 35 PRDs carrying an `upstream:` points at a BRIEF at `docs/briefs/BRIEF-<same-topic>.md`. Not one skips a BRIEF.
- `git log --diff-filter=D -- 'docs/briefs/*'` returns **nothing**. No BRIEF has ever been deleted from this repo.
- The only absorb-related commit is `3f702b6 feat(scope): always walk the whole chain and consolidate after the fact (#260)` — the change that authored the mechanism, not a run of it.

So there is zero empirical evidence of what an absorb produces. Everything above is read off the specs.

## Implications

**For BRIEF-to-PRD, the machine is complete and coherent.** The child carries (phase-3-draft.md 3.2), the parent verifies (Stage 3), the survivor inherits the frontmatter link (Decision 6). The carry check will pass on a chain-driven run because the same instructions that made the PRD carry the four sections are the ones the check looks for. It will correctly fail on a PRD authored before #260, or on one authored by a `/prd` that ignored 3.2 — which is the intended failure direction.

**For every hop above it, the model does not extend, and not only for the reason the mapping table gives.** The table (`phase-2-chain-orchestration.md:426-428`) rejects PRD-to-DESIGN and DESIGN-to-PLAN on *structural* grounds: the downstream type has no required section that houses Goals, User Stories, Requirements, Acceptance Criteria, Out of Scope, Decision Drivers, Considered Options, etc. But there is a second, independent blocker the table does not mention: **the downstream formats forbid carrying that content even if a home existed.** `design-format.md:166-167` bans requirements articulation from a DESIGN; `plan-format.md:205-218` bans technical architecture from a PLAN and instructs the author to extract such content *upward* into the DESIGN. The formats are actively anti-carry in the direction the author wants content to roll.

**This means "roll content forward at every hop, all the way to the PLAN" is not one change but three or four.** To make PRD-to-DESIGN absorbable you would have to: (a) add homes to the DESIGN schema for Goals/Stories/Requirements/AC/Out of Scope — which `DESIGN-scope-consolidation-over-skipping.md:228` explicitly rejected as Decision 4 Option B; (b) reverse the design-format rule that a DESIGN cites requirements by number rather than restating them; and (c) add a consumption block to `phase-0-setup-prd.md` mirroring `/prd`'s 3.2 so the DESIGN actually carries what it now has room for. Only then does the Stage 3 check have anything to find. The same three-part change repeats at DESIGN-to-PLAN.

**The dangling-citation problem is the sharpest concrete consequence.** DESIGNs cite their PRD's requirements as bare `R1, R2` numbers (`design-format.md:281`), and PLANs cite them too (`plan-format.md:208-209`). Absorbing a PRD into a DESIGN deletes the document those numbers resolve against. Unless the absorb also rewrites every `R<n>` citation in the survivor and in anything downstream of it, an absorb at that hop turns the chain's most-used cross-reference into an orphan. Nothing in Stage 3 does that today, and `shirabe validate`'s R6 check (`phase-2-chain-orchestration.md:498-501`) only validates that `upstream:` resolves to a tracked file — it would not catch a dead R-number.

**If the author wants the parent to do the writing instead**, that is a genuine architectural alternative and it dodges (c) above: Stage 3 would gain a merge step before the `git rm`. But it collides head-on with the D5 rationale (`DESIGN-scope-consolidation-over-skipping.md:106-109` and Decision 5 Option C at 265-267), which rejected exactly the shape where the mover and the verifier are the same actor: "trust the absorb verdict with no itemized check. This is the shipped fold path: a recommendation with no receiver and nothing confirming the transfer." A parent that both writes the content and then checks its own write has re-created the non-independence the design flagged as its residual risk (Decision 5 Option D, deferred: "an independent reviewer agent per absorb").

## Surprises

1. **The BRIEF that motivates this exploration contains a factually stale claim.** Its lines 63-66 assert `/prd` never reads the brief's body. #260 fixed that in the same PR that authored the consolidation judgment. Anyone reasoning from the BRIEF alone would conclude the carry check must always fail — the opposite of the truth for the one absorbable hop.

2. **`/plan` reads its upstream more thoroughly than `/design` does** — literally "copy verbatim" for the Implementation Approach — and yet DESIGN-to-PLAN is the *least* absorbable hop, because everything it copies lands in a `wip/` file that gets deleted before merge, and the durable PLAN is format-forbidden from restating architecture. Depth of reading and absorbability are uncorrelated.

3. **The child-side carry lives in a child skill file, but the abort logic lives in the parent, and neither file's Quality Checklist mentions the other.** `phase-3-draft.md`'s checklist (lines 198-203) checks only that sections are present and requirements are numbered — not that the four brief-derived sections actually came from the brief. So a `/prd` run that silently ignores its 3.2 instruction passes its own gate and only fails one hop later, in `/scope`, with a `carried: false` that reads as a content judgment rather than a process miss.

4. **`/prd` Phase 1 still runs full conversational scoping even when a BRIEF exists**, then Phase 3 tells it to prefer the brief over its own Phase 1 output for four of six sections. Nothing reconciles the two; the author has already spent the conversation.

5. **The BRIEF's own User Outcome describes the parent as the mover.** `BRIEF-scope-consolidation-over-skipping.md:92-93`: "the run says so, **folds the content into the one that stays**, and leaves a record of what happened." Read literally, that is a parent-side merge — which is not what shipped. The shipped mechanism has the child carry and the parent verify. The BRIEF and the implementation disagree about who does the folding, which may be the source of the assumption this exploration is testing.

## Open Questions

- Does `shirabe validate` have any check that would catch an orphaned `R<n>` citation after an absorb? R6 only resolves `upstream:` paths. Worth confirming against `crates/shirabe-validate/src/`.
- If Stage 3 gained a merge step, what re-runs the child's quality gates (the PRD jury, the DESIGN's three-reviewer Phase 6) against the merged body? The survivor was reviewed before the merge, and nothing in the current Stage 3 re-reviews.
- `/design`'s freeform mode (`phase-0-setup-freeform.md`) was not examined here; if the absorb model changes, its interaction with a PRD-less DESIGN needs checking.
- Whether the `wip/plan_<topic>_analysis.md` verbatim copies could be repurposed as the carry vehicle for DESIGN-to-PLAN — they hold the right content, but wip-hygiene deletes them, so the PLAN would need to absorb them into its durable body first.

## Summary

The BRIEF's claim is stale: `/prd` Phase 3.2 now explicitly reads its upstream BRIEF and draws Problem Statement, Goals, User Stories, and Out of Scope from its body rather than from its own Phase 1 conversation (`skills/prd/references/phases/phase-3-draft.md:63-102`), and it names the downstream carry check as the reason — so the BRIEF-to-PRD carry is performed by the child at authoring time, and Stage 3 only verifies it, never writes anything into the survivor's body beyond the `upstream:` frontmatter re-point (`phase-2-chain-orchestration.md:458-501`). `/design` and `/plan` both read their upstreams, but their format references forbid carrying that content — a DESIGN "cites requirements by their numbers" rather than restating them (`design-format.md:281`) and a PLAN must "replace the PLAN content with a citation" when it drifts into architecture (`plan-format.md:217-218`) — so extending absorption upward requires changing the formats, not just the mapping table, and would orphan the `R<n>` cross-references that both downstream types depend on. No absorb has ever run in this repo: all 35 PRDs with an `upstream:` point at their same-topic BRIEF, and `git log --diff-filter=D -- 'docs/briefs/*'` is empty, so there is no worked example to read.
