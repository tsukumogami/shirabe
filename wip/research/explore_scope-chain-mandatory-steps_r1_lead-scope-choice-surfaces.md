# Lead: Which `/scope` surfaces still present a fixed chain as a choice, and what does each one actually do?

## Findings

### 1. The Phase 1 chain proposal and its `Proceed / Adjust / Bail?` options block

The proposal is specified twice, in `skills/scope/SKILL.md:388-423` (Chain-Proposal
Output) and `skills/scope/references/phases/phase-1-discovery.md:290-328`. Both agree
on what it emits: the four children, a per-child re-entry verdict, the R6 per-predicate
verdicts behind `/design`'s roster size, the pre-authoring upstream notice inside the
`/brief` entry, and an options block containing `Proceed`, `Adjust`, `Bail`.

The skeleton at `phase-1-discovery.md:301-317` opens with "Planned chain (the full
tactical chain, as always):" and ends `/plan — runs (ALWAYS)`. Every line of it is
derivable from two things Phase 0 and the discovery globs already established: whether
a settled artifact sits at each canonical path, and whether `--upstream` was supplied.
Nothing in the proposal is contingent on the author's answer.

**What the author is being asked.** Nothing that changes the run. `planned_chain:` is
the constant `[brief, prd, design, plan]` minus re-entry-protected children
(`phase-1-discovery.md:14-16, 399-418`; `references/state-schema.md:48-53`, which
states outright "There is no field recording where the chain starts, because it always
starts at `brief`"). `SKILL.md:401-403`: "The proposal never offers a shorter chain,
because `/scope` has no way to produce one."

**Nothing downstream consumes the confirmation.** There is no state field recording
that the author answered — `references/state-schema.md` enumerates every `/scope`
field and none of them is a proposal acknowledgement. Phase 2 reads `planned_chain:`
and `chain_skipped:` only (`phase-2-chain-orchestration.md:751-770`). The Proceed
branch is defined as "advance to Phase 2", which is what happens with or without it.

**Under `--auto` the prompt does not fire at all.** `phase-1-discovery.md:391-394`:
"It is defined in `--auto` mode. The proposal is emitted and the run auto-proceeds
[...] Nothing blocks, so there is no default to get wrong." So the entire decision
point is already optional, and the non-interactive run produces the identical chain.

**Is there any input to the proposal that could change the chain?** Only re-entry
protection, which is computed from the filesystem before the prompt is emitted, and
the `/brief` framing-shift override, which is computed from the author's answer to the
R4 question *earlier in Phase 1* — not from the Proceed/Adjust/Bail answer. So no: by
the time the options block is printed, the chain is fully determined.

**One spec-level disagreement worth fixing while the section is being rewritten.**
`SKILL.md:399` says the three substrings are matched "(case-insensitive)";
`phase-1-discovery.md:297` says "(case-sensitive, exact spelling per AC9)".
`references/parent-skill-pattern.md:596` classifies the chain-proposal triad as
**per-token, not contiguous**, on the stated ground that "Proceed is the expected
path" — i.e. the pattern already records that this triad is *not* a co-equal menu,
unlike the `Re-evaluate / Revise / Bail` triad on the resume ladder.

### 2. The Adjust branch — what it actually changes

Defined at `SKILL.md:409-412` and `phase-1-discovery.md:323-325, 460-472`. The
canonical sentence is `phase-1-discovery.md:465-466`: "Adjust does not change which
children run, because that list is fixed."

Tracing what re-running discovery with adjustment input alters:

- **R6 predicate verdicts → `/design`'s roster size.** This is real and is the only
  documented persistent effect: `phase-1-discovery.md:467-468` ("Re-entry re-runs the
  R6 predicates and re-emits the chain proposal"), and R7 sizes the decision roster
  from those verdicts (`phase-1-discovery.md:250-264`). But note the roster is
  **re-derived anyway** by the post-`/prd` gate against the real PRD body
  (`phase-1-discovery.md:90-105`), which is explicitly justified as the reason a
  Phase-1 estimate is safe: "a wrong estimate is corrected the moment the PRD lands"
  (lines 165-168). So Adjust's one real effect is on a value that self-corrects one
  child later.

- **Roster size, not roster membership.** `phase-1-discovery.md:156-160`: the
  predicates "do **not** decide whether `/design` is invoked. `/design` runs on every
  chain."

- **The framing-shift answer → `/brief`'s re-entry verdict.** This is the one place
  the claim "Adjust does not change which children run" is **false as written**.
  Adjustment input explicitly includes "a corrected framing-shift answer"
  (`phase-1-discovery.md:463-465`), and a positive framing-shift answer fires `/brief`
  even when an Accepted BRIEF sits at the canonical path (`phase-1-discovery.md:64-67,
  127-131`). That moves `/brief` out of `chain_skipped:` and into `planned_chain:`.
  The fixed list is the *full chain*; `planned_chain:` is not fixed, and Adjust can
  change it in exactly one direction (adding `/brief` back).

- **Topic framing / re-framed topic — no carrier into Phase 2.** Adjust re-enters at
  Phase 1 discovery, not Phase 0, so it cannot change the topic slug (validated once
  at Phase 0, and every path in the run is composed from it). No state field records
  the adjusted framing: `references/state-schema.md` has no such field. Phase 2
  invokes children with the slug and artifact paths only
  (`phase-2-chain-orchestration.md:164-199`). So a "re-framed topic" reaches `/brief`
  only through undocumented conversational context.

- **Ungraded.** No eval asserts anything about the Adjust *branch*; the token "Adjust"
  appears only inside options-block substring assertions (evals 7 and 25).

**Contrast with `/charter`, which is where this option came from.** In
`skills/charter/references/phases/phase-1-discovery.md:383-390`, Adjust genuinely
reshapes the chain: "The redirected discovery may force a previously-skipped child on
(e.g., 'force `/vision` on, even though an Accepted VISION exists'), opt out of a child
that would otherwise fire, or reframe the topic entirely." `/scope` inherited the
triad from a parent where it had chain-shape semantics and kept it after #302 removed
those semantics.

### 3. The Bail branch and R8 bail-handling

`SKILL.md:413-418` and `phase-1-discovery.md:326-328`: Bail routes to R8 bail-handling
— "force-materialize if any wip state exists for the topic (the state file, any child
intermediate, or any research scratch); clean-cancel otherwise."

**The clean-cancel branch is unreachable from Phase 1.** Phase 0 always writes
`wip/scope_<topic>_state.md` before returning control to Phase 1
(`phase-0-setup.md:273-309`, "Phase 0 advances the `phase_pointer:` to `phase-1`
immediately before returning control"). The state file *is* wip state under the
disjunction as written, so at the Phase-1 Bail the condition always holds and the exit
is always `abandonment-forced`.

**And the abandonment-forced branch cannot be satisfied there either.** At Phase 1 no
child has run, so there is no intermediate to force-materialize. Phase 3's rule
(`phase-3-exit-finalization.md:172-176`) sets `triggering_child:` to "whichever child
Phase 2 was about to invoke when the bail fired — the first child in `planned_chain:`
that has not yet completed", i.e. `brief`, and the exit's contract
(`phase-3-exit-finalization.md:135-155`) is to force-materialize *that child's
intermediate* as a Draft at `docs/briefs/BRIEF-<topic>.md`. There is nothing to
materialize from. R9 condition 2 (`phase-3-exit-finalization.md:218-221`) then refuses
finalization on the empty `exit_artifacts:` that results.

So the Phase-1 Bail is specified into a corner: it must record `abandonment-forced`,
it has no artifact to produce, and R9 fails it. The bail-handling contract was written
for a mid-chain bail (which is what eval 12 grades — a stale-state resume, not a
Phase-1 Bail) and was never re-checked against the Phase-1 position of the prompt.
Nothing in the eval suite exercises Bail at Phase 1.

Bail is also redundant with the ordinary way out: an author who does not want the run
does not have to answer, and Phase 0 already exists as a stop point with no state
consequences before the state file is written (it stops on a bad slug, a bare
`--upstream`, or an empty argument).

### 4. `chain_skipped:` and the re-entry protection gates

Confirmed. `phase-1-discovery.md:428-430`: "That is the only reason Phase 1 ever
writes" — `settled-artifact-at-canonical-path-reentry-protection`
(`phase-1-discovery.md:107-146, 419-427`; `references/state-schema.md:81-91`). The
prose is emphatic that this is not a worth judgment (`phase-1-discovery.md:133-140`).
The settled statuses per child are the table at `phase-1-discovery.md:119-122`.

**The second reason Phase 2 writes is actually two reason strings, not one.** Both
`phase-1-discovery.md:429-432` and `references/state-schema.md:89-91` say "one further
reason" (singular). The templates write two distinct literals:

- `"PRD-boundary rejection"` — `references/decision-record-prd-rejection.md:73-75`,
  applied to any `/design` or `/plan` still in `planned_chain:`.
- `"DESIGN-boundary rejection"` — `references/decision-record-design-rejection.md:71-74`,
  applied to `/plan` only.

Eval 11 (`us-4-prd-rejection-sub-shape`) pins the first string:
`"chain_skipped records /design and /plan with reason 'PRD-boundary rejection'"`.
Neither reason string is enumerated in `references/state-schema.md`'s `chain_skipped`
entry, and `phase-2-chain-orchestration.md`'s own Phase-N Reject Handling section
(lines 350-417) never mentions writing `chain_skipped:` at all — the only place the
Phase 2 write is specified is inside the two Decision Record templates.

### 5. The stale paragraph at `phase-1-discovery.md:38-43`

**Yes, the two passages contradict each other.**

Lines 38-43: "**An author who wants a shorter chain reaches for a child skill
directly.** `/design <topic>` and `/plan <topic>` are the documented ways to enter the
tactical chain above `/brief`, and that choice is theirs and visible in what they
typed."

Lines 266-288 ("What Phase 1 Does Not Decide About the Artifact Set"): the section
records that the durable-artifact floor and the redirect both "rested on the
type-level absorbability test, which is gone [...] the redirect describes an escape
hatch from a constraint that no longer exists."

The later section is narrower than it looks, though: it retires the redirect for the
**no-durable-record** case (invoke `/plan` directly to leave nothing behind), which is
now reachable inside `/scope` because a run can absorb down to nothing. It does not
address the **shorter-chain** case at lines 38-43. Whether that one survives depends
on a claim nobody has written down: absorption reduces the *artifact set* but not the
*work* — an author who says the framing is settled still sits through a BRIEF
conversation and a PRD conversation before the fold happens. So lines 38-43 are not
obviously wrong on their own terms; they are stale in that they present the redirect
as the response to "a shorter chain", when after #302 the corpus's own answer is "the
chain is not shortened, the artifact set is reduced afterwards."

**Other copies of the same advice** (all say some variant of "reach for a child
directly if you know the altitude"):

| Location | Wording |
|---|---|
| `skills/scope/SKILL.md:10-12` (frontmatter description) | "Do NOT use when the author already knows which artifact altitude they want (reach for `/brief`, `/prd`, `/design`, or `/plan` directly)." |
| `skills/scope/SKILL.md:401-403` | "The proposal never offers a shorter chain [...] An author who wants to start above `/brief` invokes `/design` or `/plan` directly." |
| `skills/scope/SKILL.md:461-465` | "**A shorter chain is still reached by invoking a child directly.** `/design <topic>` and `/plan <topic>` enter the tactical chain above `/brief`, which is what CLAUDE.md tells authors to do when they know the altitude they want." |
| `skills/scope/references/phases/phase-1-discovery.md:38-43` | the passage above |
| `skills/scope/references/phases/phase-1-discovery.md:274-281` | the *retired* form (invoke `/plan` directly for no durable record), explicitly labelled as describing a constraint that no longer exists |
| `CLAUDE.md:171-174` | "The child skills `/brief`, `/prd`, `/design`, and `/plan` remain directly invocable on their own for authors who already know which altitude they want." |
| `skills/scope/evals/evals.json` eval 17 | `"Plan points the author at invoking /design directly if they want to start above /brief"` |

Nothing in `skills/brief/SKILL.md`, `skills/prd/SKILL.md`, `skills/design/SKILL.md`, or
`skills/plan/SKILL.md` carries a copy — the children never mention the redirect.
`skills/charter/SKILL.md:12` carries the strategic-chain analogue, which is untouched
by #302.

### 6. The post-`/prd` re-evaluation gate and `chain_revised:`

`phase-1-discovery.md:90-105`. It re-evaluates P1/P2/P3 against the real PRD body,
writes `chain_revised: true` if any verdict changed, re-narrates `/design`'s roster
shape, and the author confirms the revised shape before Phase 2 proceeds.

**It never changes which children run.** Stated at `phase-1-discovery.md:103-105`:
"The re-evaluation changes `/design`'s roster size, never whether `/design` runs.
`planned_chain:` is the whole chain on every run and is not revised here."

**`chain_revised:` is an orphan field.** It appears nowhere in
`skills/scope/references/state-schema.md`'s field enumeration, and nothing reads it —
the only other hit in the repo is `docs/designs/current/DESIGN-shirabe-pattern-v1-ergonomics.md:305`,
which describes the *retired* semantics: "if the PRD doesn't surface alternatives,
`/design` is skipped and a `chain_revised` record is written". The field is a survivor
of the produce-or-skip reading of R6/R7 that `phase-1-discovery.md:156-160` explicitly
retires. Under the current rule its only possible meaning is "the roster was resized",
and its name says something the skill no longer does. No eval grades it.

The gate also carries a **second confirmation prompt** ("The author confirms the
revised shape before Phase 2 proceeds") whose branch behavior is undefined — there is
no options block, no branch list, and no state record of the answer.

### 7. Phase 0 — does anything let the author shorten the chain?

No. Every Phase 0 surface either rejects, informs, or configures:

- **`--upstream <path>`** (`phase-0-setup.md:133-231`) records `consumed_upstream:` and
  is handed to `/brief` and `/plan`. It does **not** hold `/brief` back — `/brief` runs
  and grounds on the roadmap (`phase-2-chain-orchestration.md:168-177`), and eval 26
  pins this: "the notice does not fire [...] and /brief is invoked as `/brief
  inline-diff --upstream docs/roadmaps/ROADMAP-editor.md`". Its only proposal-visible
  effect is suppressing the pre-authoring upstream notice. **Note the asymmetry with
  `/charter`**, where supplying `--upstream` makes the `/vision` entry read "skip"
  (`skills/charter/evals/evals.json:309`) — same flag, chain-shortening in one parent
  and not the other.
- **Slug-prefix convention check** (`phase-0-setup.md:90-120`) is explicitly
  non-blocking and recommends a rename, nothing more.
- **`--auto`** suppresses the prompt and takes the recommended default; it does not
  shorten anything.
- **`--max-rounds=N`** caps re-evaluation re-entries *across* chain instances, and
  `phase-1-discovery.md:469-472` states it explicitly does not govern Adjust
  iterations.
- **`--coordinated` / `--no-coordinated`** select the coordination-PR path.
- A path in the positional slot is rejected (`phase-0-setup.md:83-88`), so there is no
  "enter at this artifact" mode.

### 8. Evals — what is graded

26 evals in `skills/scope/evals/evals.json`.

**Eval 17, `chain-shape-is-constant`** (the entry-altitude shortcut eval). Prompt:
`/scope refactor-topic  (the author says the problem and the requirements are settled;
they only want to talk about architecture)`. Assertions, verbatim:

- `"Plan runs the whole chain and does not offer a shortened one"`
- `"Plan explains that skipping the BRIEF here would be a judgment about an unwritten document"`
- `"Plan points the author at invoking /design directly if they want to start above /brief"`
- `"Plan notes a redundant BRIEF is removed by the Phase 2 consolidation judgment, after both documents exist"`

Its `expected_output` ends: "The correct redirect for an author who genuinely wants to
start at the architecture is to invoke `/design` directly, and `/scope`'s prose says
so." So eval 17 **pins the direct-invocation redirect** as a graded behavior. Any
rewrite that removes the lines-38-43 advice must update this eval or it will fail.

**Eval 7, `us-1-cold-standalone-full-run`** pins the options block:
`"Plan emits a chain-proposal output containing the literal substrings Proceed, Adjust
and Bail"`, alongside `"Plan populates planned_chain: as [brief, prd, design, plan] on
this run"` and `"Plan describes no starting-altitude choice and no state field
recording one"`. Removing the triad breaks this eval's fifth assertion only.

**Eval 25, `pre-authoring-notice-cold-start`** pins the exact options-block string:
`"Plan leaves the options block \"Proceed / Adjust / Bail?\" unchanged and adds no new
option or decision point"`.

**Eval 8, `us-2-prd-auto-skip`** pins the re-entry reason string and the
not-a-worth-judgment framing.

**Two evals are stale against #302 and currently assert the retired type-level rule:**

- **Eval 18, `durable-artifact-floor-is-structural`**: "no hop above BRIEF-to-PRD is
  absorbable, so the smallest set a run can end with is a PRD, a DESIGN and a PLAN"
  and `"Plan notes that a PLAN-alone outcome is unreachable through /scope and requires
  invoking /plan directly"`. This is exactly the floor
  `phase-1-discovery.md:271-281` and `phase-2-chain-orchestration.md:710-730` ("There
  is no durable-artifact floor") say is gone. The eval's whole premise is now false.
- **Eval 20, `consolidation-keep-at-unmapped-hop`**: `"Plan finds the prd->design
  mapping is not total and records absorbable: false"` and `"Plan derives absorbability
  from the per-type required-section contracts rather than a hard-coded list of hops"`.
  `absorbable:` was retired (`references/state-schema.md:116-128`) and reading the
  types' required-section lists is now the explicitly forbidden input
  (`phase-2-chain-orchestration.md:520-534`: "*No check in this judgment may read
  either type's required-section list, or compare the two types' section sets.*"). The
  eval grades the violation.
- **Eval 19** is partly stale in the same way — its `expected_output` says "Stage 1
  finds the mapping total [...] so absorb is available", but Stage 1 is now the
  citation preflight (`phase-2-chain-orchestration.md:536-573`). Its assertion list
  survives; only the narration is wrong.

**Not graded anywhere:** the Adjust branch behavior, the Bail branch behavior, a
Phase-1 bail, the post-`/prd` re-evaluation gate, `chain_revised:`, and the second
confirmation prompt that gate carries.

## Implications

**The chain proposal's options block is the surface the author's complaint is about,
and it is safe to change.** Nothing downstream consumes the answer, no state field
records it, `--auto` already skips it, and the only eval assertions touching it are
substring checks in evals 7 and 25. The proposal's *content* is worth keeping — the
per-child re-entry verdicts, the R6 predicate reasons, and the upstream notice are all
information the author cannot get elsewhere. What has no work left to do is the
question mark. The natural replacement is an announcement: emit the same body, drop
the options line, and let the author interrupt if they want to (which is what Bail
degenerates to anyway).

**If the triad is kept, Adjust needs a different name and a smaller claim.** Its real
effects are re-running the R6 predicates and correcting the framing-shift answer —
i.e. it adjusts *discovery inputs*, not the chain. And the sentence "Adjust does not
change which children run, because that list is fixed" is false in the one case where
a corrected framing-shift answer un-skips `/brief`; that needs fixing regardless of
what happens to the prompt.

**Bail at Phase 1 is broken today and should be resolved either way.** The clean-cancel
branch is unreachable because Phase 0 always wrote the state file, and the
abandonment-forced branch has no intermediate to materialize and fails R9's non-empty
`exit_artifacts:` check. If the prompt goes away, this resolves by deletion. If it
stays, the wip-state disjunction needs to exclude the parent's own state file.

**Three orphaned artifacts of the retired produce-or-skip model should be swept in the
same pass:** `chain_revised:` (written by phase-1, absent from the state schema, read
by nobody, named after a behavior that no longer exists), the post-`/prd` gate's
undefined second confirmation prompt, and the singular "one further reason" claim about
`chain_skipped:` when Phase 2 writes two distinct reason strings that the state schema
does not enumerate.

**Evals 18 and 20 must be rewritten as part of this work, not after it.** They
currently grade the type-level absorbability rule that PR #302 replaced, so any agent
optimizing against the eval suite is being pulled back toward the pre-#302 model. Eval
17 is the one to keep and is the reason the direct-invocation redirect cannot simply be
deleted from the prose without a corresponding eval edit.

## Surprises

1. **Adjust *can* change `planned_chain:`.** The framing-shift override is reachable
   from Adjust's own documented input list, so `phase-1-discovery.md:465-466` is
   contradicted by `phase-1-discovery.md:64-67`. The exploration's working assumption
   ("Adjust cannot change the list") is right about the full chain and wrong about
   `planned_chain:`.

2. **Bail at Phase 1 cannot be executed as specified.** Both branches are blocked —
   clean-cancel by the always-present state file, abandonment-forced by having no
   intermediate and failing R9. This was not on the list of things to check.

3. **`--upstream` shortens `/charter`'s chain but not `/scope`'s.** Same flag token,
   same declared meaning, opposite effect on chain shape. An author moving between the
   two parents has no way to predict this.

4. **Eval 20 grades a behavior the skill now forbids.** It asserts the judgment derives
   absorbability from per-type required-section contracts; `phase-2-chain-orchestration.md`
   states that reading those lists is the defining violation.

5. **`chain_revised:` is written by a phase reference but absent from the skill's own
   state schema.** The state schema is otherwise scrupulous about the I-5
   conditional-field discipline, so the omission reads as the field having been
   forgotten rather than deliberately unlisted.

6. **The pattern reference already knows the chain-proposal triad is not a real menu.**
   `references/parent-skill-pattern.md:596` classifies it as per-token specifically
   because "Proceed is the expected path" — the pattern documented the asymmetry before
   #302 made it total.

## Open Questions

1. Does removing the `Proceed / Adjust / Bail?` prompt need pattern-level sign-off?
   `references/parent-skill-pattern.md:571-573` lists the chain-proposal output as a
   parent-specific extension beyond the seven structural elements, so a parent that
   emits an announcement rather than a prompt appears conformant — but `/charter` keeps
   its prompt with real semantics, and the pattern reference's confirmation-form table
   would then describe a row only one parent fills. Human call on whether the pattern
   doc changes too.

2. Is the shorter-chain redirect at `phase-1-discovery.md:38-43` still true? It depends
   on whether "shorter chain" means fewer artifacts (absorption handles it, so the
   redirect is obsolete) or less conversation (absorption does not handle it, so the
   redirect is the only answer). The corpus never says which, and eval 17 grades the
   redirect either way.

3. Should the Adjust affordance survive in any form? The R6 predicate re-run is
   self-correcting one child later, and the framing-shift correction could be folded
   back into the discovery prompt itself. Whether losing the explicit re-entry loop
   costs anything is an author-experience judgment, not something the docs answer.

4. Who owns the eval rewrites for 18, 19 and 20? They are consolidation-judgment evals
   rather than chain-proposal evals, so they may belong to a different slice of this
   exploration.

## Summary

The Phase 1 chain proposal's `Proceed / Adjust / Bail?` block is the surface the
author's complaint names, and it is inert: `planned_chain:` is fully determined before
the prompt is printed, no state field records the answer, nothing downstream consumes
it, and `--auto` already skips it entirely — while Adjust's one real effect (re-running
the R6 predicates to size `/design`'s roster) is self-correcting at the post-`/prd`
gate, and Bail at Phase 1 cannot execute either of its two branches as specified. The
main implication is that the proposal should become an announcement carrying the same
body minus the question, with three retired-model artifacts swept alongside it —
`chain_revised:`, the post-`/prd` gate's undefined second confirmation, and the stale
shorter-chain redirect at `phase-1-discovery.md:38-43` that eval 17 currently pins.
The biggest open question is what "shorter chain" means to an author now that
absorption reduces the artifact set but not the conversation, because that decides
whether the direct-invocation redirect survives — and evals 18 and 20 must be rewritten
regardless, since they still grade the type-level absorbability rule PR #302 removed.
