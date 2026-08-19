# Exploration Findings: scope-process-framing

## Core Question

`/scope`'s `SKILL.md` spends its only motivated argument on why the artifact set
shrinks, states that argument before any artifact exists, and never states why
the steps are run at all. An agent read it for intent, found one purpose, and
acted on it -- producing the terminal artifact and asserting the upstream
documents away in prose. What should the skill say instead, and at which point
in the disclosure order should each thing be said, so that an agent reading it
for intent finds the process rather than the reduction?

## Round 1

Six leads dispatched, six returned. No agent failed.

### Key Insights

**The relocation the issue proposes has already happened; the remaining defect
is duplication.** (placement-at-hop, purpose-argument, charter-control --
independently) `skills/scope/references/phases/phase-2-chain-orchestration.md:492-500`
already carries the reader-economy argument under a `**Why it exists.**` label,
scoped to two bodies that exist, at the hop where the judgment fires. It is
near-verbatim with `SKILL.md:474-478`, and the phase-2 copy is the better one:
it says the reduction is only honest to do "*here* -- against two bodies that
exist" and names the failure mode of asking early ("answering it anyway is how
content gets lost"). Of the 107 lines in `SKILL.md`'s two reduction sections,
one sentence has no home elsewhere (the 484-489 history). The placement half of
the fix is a deletion, not a rewrite.

**The argumentation asymmetry is real and measurable, under a sharper statement
than the issue gives.** (purpose-argument) `SKILL.md` argues extensively --
`## Security Considerations` alone is 113 argued lines -- but every one of those
arguments is *rule-justification* ("here is why this rule is written this way").
`## Why the Artifact Set Shrinks` is the only *value-of-outcome* argument in 968
lines ("here is why this outcome is worth wanting"). The five sections that
describe what the chain actually does -- Workflow Phases, Resume Logic, Phase
Execution, Reference Files, State File Schema, 155 lines total -- contain zero
reason-giving prose between them. The `## Workflow Phases` Purpose column lists
mechanical operations; Phase 2, the phase that runs the entire chain, is
described as bookkeeping wrapped around the words "invoke child".

**"Contribution" is used eight times and never defined.** (purpose-argument)
`SKILL.md:552` says "Each type declares one contribution to the chain" without
saying what any type's contribution is. The operational definition lives only at
`phase-2-chain-orchestration.md:597-600`, inside Stage 2 of the judgment. The
sink-and-source framing is half-present in the file's vocabulary already; it
needs stating, not inventing.

**No child `SKILL.md` is reachable from `/scope`'s reference table.**
(purpose-argument) The table at `SKILL.md:403-419` lists thirteen files, all
pattern contracts or `/scope` phase procedures. The only genuine statement of
step-value in the tactical chain is `skills/prd/SKILL.md:142` -- "Phase 4 is not
optional, authors consistently miss ambiguity and testability gaps in their own
writing" -- and the only route to it is to invoke `/prd`, which is the act a
skipping agent omits. The rationale is downstream of the decision it should
govern.

**The past-tense obituary pattern is six passages, not one.**
(purpose-argument) `SKILL.md` 472-489, 499-506, 508-517, 519-530, 872-881, 813.
Roughly 30 of the purpose-bearing section's 60 lines are narration of designs
that no longer exist. What survives as live instruction is the reader-benefit
claim at 474-478 -- the half the incident agent acted on. The corpus contains a
model for the correct register at `phase-2-chain-orchestration.md:719-739`
("Do not add a guard that... so this prohibition has to be written down rather
than derived"): present imperative, addressed to the reader, reason attached.

**The write-target enumeration is not the disclosure channel.**
(write-target-set) `docs/plans/PLAN-<topic>.md` appears at `SKILL.md:29` in the
Overview's second paragraph -- 818 lines before the security section -- and
again at `:588`, `:764-766`, in all six `/scope` phase references, in
`/plan`'s own `SKILL.md:44`, and in `/explore`'s routing tables. Relocating the
enumeration changes nothing an agent knows. It would also break conformance:
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-security.md:49-73` binds the set
to `SKILL.md` by name twice ("declared in the parent's SKILL.md", "The
per-parent SKILL.md names the concrete paths") and requires concrete paths.
Nothing in `crates/` parses the set, so every option costs zero validator work.

**The sourcing property cannot hold, for a reason prior to disclosure.**
(sourcing-property) `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md:499-504`
binds `/scope` to inline Skill-tool dispatch: "The child runs in the parent's
agent context." There is no boundary across which an argument could be withheld.
Separately, `/plan`'s argument inside `/scope` is `docs/designs/DESIGN-<topic>.md`,
computable from the validated slug at Phase 0 and printed in three places
including `phase-2-chain-orchestration.md:183-187`, the file whose job is to
tell the orchestrator what to type. Closing either gap requires an opaque handle
or a real dispatch boundary -- mechanism, and outside `/scope`.

**Standalone entry is a deliberate, four-times-stated contract.**
(sourcing-property) `skills/plan/SKILL.md:256-258` says "No upstream document is
required"; `upstream` is absent from the Plan profile's `required_fields`
(`crates/shirabe-validate/src/formats.rs:405`); R6 early-returns on an absent
field (`checks.rs:1226-1229`); and `check_orphan` exempts PLANs by name as
"chain roots" (`lifecycle.rs:1303-1305`), with a DECISION doc behind it. A
rootless PLAN is a modelled, supported state.

**FC18's account in the issue is confirmed in source.** (sourcing-property)
`crates/shirabe-validate/src/checks.rs:421-424` early-returns the moment
`absorbed:` is absent; the doc comment at `:401-403` says so outright. All six
of FC18's clauses check internal consistency of a declaration that exists. There
is no reverse check against the body.

**The prose model already exists in the corpus.** (charter-control)
`skills/charter/references/phases/phase-2-chain-orchestration.md:463-511`, "Why
/roadmap Is Unconditional", argues affirmatively for running a step in
sink-and-source terms: skipping it "strands whatever it made actionable -- no
downstream artifact can pick the work up". Its confirmation prompt refuses size
as grounds outright ("Size never disqualifies a ROADMAP"), which is precisely
the refusal `/scope`'s reader-economy argument fails to make. It lives at a hop,
in a phase reference, not in `SKILL.md`.

**`/scope` was the correct command for the incident's work.**
(scale-lower-bound) Coordination forces it. `references/coordination-strategy.md:6-7`
binds `/scope` and `/work-on`; `skills/scope/SKILL.md:224-234` has `/scope`
create the coordination PR up front; `skills/execute/SKILL.md:294-296` says
"creating the coordination home up front stays `/scope`'s responsibility". A
standalone `/plan <topic>` in coordinated mode yields a PLAN that `/execute`
halts on. There is no sanctioned path for a coordinated multi-repo effort that
avoids `/scope`.

**The lower-bound question was already asked and answered "no floor".**
(scale-lower-bound) Closed issue #280 argued `/scope` is "the front door for
tactical work of any size"; the artifact-persistence work implemented that by
making every hop absorbable, so small work folds to nothing durable.
`docs/briefs/BRIEF-scope-artifact-persistence.md:75` carries a user journey
literally titled "An author scopes a self-contained fix and the chain folds to
nothing durable". That position is invisible to an agent -- recoverable only
from a closed issue and a BRIEF.

**The cost claim is half true.** (scale-lower-bound) Of the three upstream
documents, the PRD fits documentation work *better* than most code -- thirteen
edits map to thirteen numbered testable requirements and thirteen checkboxes,
and the format already grants an escape on User Stories. The BRIEF mostly holds;
its User Journeys section is the strained part. Only the DESIGN would be padded
(Solution Architecture has no components, interfaces, or data flow for prose
edits), and R6's three predicates already size that DESIGN down to a minimum
roster (`phase-1-discovery.md:291-297`). What is genuinely expensive is process,
not paper: 25 phases, four approval gates, three juries and a security review.

### Tensions

**The parity claim splits in two, and the issue states it as one.**
(charter-control vs the issue's closing bullet) `/charter` lacks
`## Why the Artifact Set Shrinks` and `## Consolidation Judgment` because it
lacks the *capability*, not because the sections are unwanted:
`docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:353-372`
ruled the model a no-op on the strategic chain (zero strategic hops are
absorbable, so porting it would install a rule that can only ever return
`keep`), and `parent-skill-pattern.md:141-147` ratified that a parent may define
none. So parity licenses removing the argumentation section and does not license
removing the mechanism section -- which is currently the only `SKILL.md`-level
notice that a `/scope` run deletes files.

**Removing the reduction argument leaves P2 as the next available
justification.** (purpose-argument) `references/workflow-principles.md:41` is
`## P2: Default to the lowest ceremony` -- "Reach for the least machinery the
work needs." `/scope` cites `workflow-principles.md` zero times, so P2 did not
cause this incident. But it is the framework's own stated principle, and it is
the argument a future agent finds once the `SKILL.md` one is gone. A rewrite
that says "the process is the product" without reconciling against P2 leaves a
live contradiction in the corpus.

**The two paths converge on byte-identical output, and only one framing makes
that acceptable.** (scale-lower-bound) A full run that folds all the way down
ends at a single PLAN carrying `absorbed: [brief, prd, design]`, which the
implementation cascade then deletes. The shortcut ends at a single PLAN. Under
"the process is the product" the convergence is not a defect -- the juries, the
security review and the adversarial plan pass are the whole value. Under the
framing `SKILL.md` currently states (a smaller artifact set is better for the
reader) the two paths deliver the same product and one of them is free. The
agent optimized against the framing the document actually gave it.

**Disclosure of the chain's addresses is structural, not editorial.**
(sourcing-property, write-target-set) `phase-2-chain-orchestration.md:183-187`
publishes all four addresses inside the file whose job is to explain the hop,
and it must, because it tells the orchestrator what to type. The address cannot
be hidden from the party that has to use it, and under inline dispatch that
party is also the party that might skip.

**Progressive disclosure holds at the phase-file level and is defeated at the
`SKILL.md` level.** (placement-at-hop) `phase-0-setup.md` and `phase-resume.md`
never mention consolidation; the phase-2 reference is correctly bound to Phase
2. But `SKILL.md` loads whole at invocation and never unloads, and it restates
phase-2. Secondary leaks inside the blast radius: three Phase-1 pointers at
phase-2 that carry the conclusion with them (`phase-1-discovery.md:35, 323,
558-559`), and a worked `absorb` example with concrete deletion and survivor
paths in `references/state-schema.md:121-160`, which the Reference Files table
binds to "All phases".

### Gaps

- **The replacement prose has not been drafted.** Every lead converges on what
  to remove; none produced candidate text for what replaces it.
- **The eval suite's loading behaviour is unknown.** Eval 17
  (`chain-shape-is-constant`) grades this exact failure -- an author who says
  framing and requirements are settled "is not offered a shorter chain" -- and
  presumably passes. Whether that is because evals load phase references the
  incident agent did not load decides whether eval coverage is evidence of
  anything.
- **`DESIGN-scope-consolidation-over-skipping.md` is status Current** and its
  Decision Outcome (`:412-415`) plus Component-changes block (`:426-430`) name
  both `SKILL.md` sections as deliverables. Removing them puts the skill out of
  sync with a current design. The design already carries two amendments, so a
  convention exists, but the right sync path has not been established.
- **`skills/brief/references/phases/phase-0-setup.md:315` cites
  `## Why the Artifact Set Shrinks` by title.** Deleting the section dangles the
  reference, and `/brief` is outside the stated `/scope`-only blast radius.
- **Whether `SKILL.md:43-46` is in the fix.** It states the reduction conclusion
  in the skill's third paragraph -- earlier than either section the issue targets
  -- but it is a structural declarator rather than an argument.

### Corrections to the issue's own account

Recorded because the issue is the primary source and these bear on it.

- **The audit trail is not removed before anyone reads it.**
  `references/state-schema.md:234-238` says Phase 3 copies `chain_ran`,
  `chain_skipped` and `consolidation_judgments` into the run's PR body before
  Phase 4 removes the state file, precisely so "a reviewer can tell 'not
  produced' from 'absorbed into this other document' after the scratch is gone."
  The trail is self-authored, which stands; it is not disposed of unread.
  (placement-at-hop)
- **"The argumentation in SKILL.md is one-sided" understates and overstates at
  once.** The file argues a great deal. The precise claim is that all of it
  argues rule correctness and only one passage argues what is worth wanting.
  Stating it loosely invites a rebuttal that the file is full of reasons, which
  is true and beside the point. (purpose-argument)
- **The reduction argument is not unique to `/scope` in the corpus.**
  `parent-skill-pattern.md:115-160` carries the mandatory-steps model both
  parents load on every phase, and states it better than `SKILL.md` does:
  "Chain steps are mandatory, and reduction is post-hoc." (charter-control)

### Findings that bear on other work

Not this issue's to fix; recorded so they are not lost.

- **A live R9 defect in the self-declared authoritative write-target set.**
  `SKILL.md:857-860` omits `docs/designs/current/` and `docs/plans/` from its
  `abandonment-forced` entry, while `SKILL.md:762-766` and
  `phase-4-cleanup.md:55-56` both include them. An abandonment triggered inside
  `/plan`, or against a Current-lifecycle DESIGN, writes outside the declared
  set and fails hard-finalization for a reason unrelated to safety.
  (write-target-set)
- **`/explore` no longer names `/plan <topic>` as a destination.** The table
  collapse in commit 39b0981 removed the row `| "What order do we build in?" |
  Plan |`, and the artifact-persistence work separately removed `/scope`'s
  sentence redirecting no-durable-record work to `/plan`
  (`phase-1-discovery.md:303-329`). Both removals are sound on their own terms.
  Together they leave `/plan <topic>` guaranteed in three places
  (`skills/plan/SKILL.md:9` and `:258-261`, `CLAUDE.md:239-241`,
  `phase-1-discovery.md:38-42`) and reachable from no routing surface an agent
  consults. (scale-lower-bound)
- **A coordinated standalone `/plan` produces a PLAN `/execute` will halt on**,
  because no surface outside `/scope` authors the coordination PR. Either a
  documented restriction that belongs in `/plan`, or a gap.
  (scale-lower-bound)
- **The coordination PR body template publishes the whole chain up front.**
  `references/coordination-strategy.md:90-95` templates an Artifact Chain
  section as a four-line list -- BRIEF, PRD, DESIGN, PLAN -- authored before any
  child runs. Same defect shape as the write-target enumeration, in a second
  place. (scale-lower-bound)

### Decisions

Recorded in `wip/explore_scope-process-framing_decisions.md`.

### User Focus

Pending. The round-1 narrowing questions were put to the author and are awaiting
a response.

## Accumulated Understanding

The incident has a single cause with two independent enablers, and the issue's
diagnosis is right about the cause and wrong about both proposed remedies.

The cause is that `SKILL.md` states exactly one thing as worth wanting, and that
thing is a smaller artifact set. Everything else the file argues is about
whether a rule is correctly written. The sections describing what the chain does
give an agent no reason to run it, the vocabulary of step-output ("contribution")
is used without being defined, and the one place in the tactical chain that
states why a step is run sits inside a child the skipping agent never invokes.
An agent reading for intent finds one motivated purpose and acts on it. That is
the whole mechanism, and it is prose-shaped, which is what makes the prose fix
the right first move.

The first proposed remedy -- relocating the persistence justification to the hop
-- is already done. The phase-2 reference carries it, correctly scoped, in
better words. The defect is that `SKILL.md` also hoists it, and the hoisted copy
grew to forty lines while the correctly-placed one stayed at nine. So the
intervention is smaller than the issue implies on this axis: delete the
duplicate, keep the original.

The second proposed remedy -- resolving the write-target enumeration against
disclosure ordering -- does not survive contact with the file. The terminal
artifact's address is in the Overview's second paragraph, in five other places
in the same file, in every phase reference, and in `/plan`'s own skill. Bounding
what the skill may write is worth keeping and the shared contract requires it to
be stated in `SKILL.md` with concrete paths. What is available instead is
changing the enumeration's *status* rather than its presence -- saying that
membership bounds a write rather than licensing one -- and fixing the two
sentences that actually handed over the licence: `SKILL.md:29`, which frames the
PLAN as the skill's product rather than a deposit, and `SKILL.md:442-445`, which
tells the reader outright that invoking `/plan` directly is a sanctioned move.

The caveat the issue raises about its own fix -- that deferring a justification
only helps if the decision point is reached -- is correct, and the sourcing
property it proposes cannot answer it. `/scope` dispatches children inline, in
its own agent context; there is no recipient to withhold an argument from, and
the argument is derivable from the slug regardless. What prose can honestly
reach instead is the constant-chain promise: `planned_chain:` is the literal
constant `[brief, prd, design, plan]`, `/scope` has no altitude selection, and
which artifacts survive is decided at Phase 2 against two written bodies. That
is already written correctly in `phase-1-discovery.md` and already graded by an
eval -- it simply lives in a file an agent that has decided to skip will never
open.

The scale question resolves against the mismatch hypothesis, but not trivially.
`/scope` genuinely was the right command: coordination forces it and no other
skill authors the coordination PR. The repository has already ruled that `/scope`
has no lower bound, and implemented that ruling. So what such an agent needs
from `SKILL.md` is not a redirect but a reason to run the steps -- which is the
issue's own proposal arriving from a different direction. The real cost is
process rather than paper, and under the author's framing that cost is the
product. Nothing in the skill says so where an agent reads it.

What remains genuinely open is what the replacement text says, whether the
purpose statement lives once in the lede or per-hop at each child, whether
`## Consolidation Judgment` is rewritten into a bounding statement or removed,
and how a corpus that tells agents to "default to the lowest ceremony" is
reconciled with a chain whose steps are mandatory.

## Round 2

Five leads dispatched, five returned. No agent failed. Round 2 was scoped to the
gaps round 1 opened rather than to new territory, plus one lead added from the
author's question about whether `/scope` uses koto.

### Key Insights

**P2 is not in conflict with a mandatory chain.** (p2-ceremony)
`references/workflow-principles.md:3` scopes the whole principle set to "the
roadmap and plan workflows", and all three of P2's derived rules (`:48-53`)
choose between output *forms* for work already decided.
`docs/prds/PRD-roadmap-plan-standardization.md:637` bounds it outright:
"Lowest-ceremony governs artifact ceremony (one PR or many; a PLAN doc or GitHub
issues)." A citation census finds five live skill-surface citations, all in
`/plan` and `/roadmap`, and zero from `/scope`, `/charter`, `/execute`, or
`parent-skill-pattern.md`. Round 1's flag was an overstatement: it is a reading
risk, not a contradiction.

**The corpus already carries the answer, unnamed, in a file `/scope` loads at
Phase 0.** (p2-ceremony) `references/pipeline-model.md:32-35` and `:84-89` put
the ceremony decision at entry-point selection -- `/work-on` versus `/scope`
versus `/charter` -- and then state "there is no transition that bypasses a
diamond's steps." Nothing connects that to P2.

**A sharper seam than P2.** (p2-ceremony) #280's "front door for tactical work
of any size" paired with a lowest-ceremony default reads as "the front door
should be cheap for small work". That pairing, not P2 alone, is what the prose
has to answer.

**Deleting the two reduction sections breaks no eval.** (eval-suite) Round 1's
flag on eval 17 was wrong: all four of its expectations are satisfied by
`SKILL.md:435-445` (`## Chain-Proposal Output`), above the deletion range. No CI
job greps `SKILL.md` section headings. The only forced edit anywhere is the
by-title citation at `skills/brief/references/phases/phase-0-setup.md:315`.

**No eval could catch the incident.** (eval-suite) All 30 `/scope` evals are
plan-only, so an agent that describes the chain correctly and then writes only a
PLAN passes every one. Three harness defects compound it: `expectations` is read
as `assertions` at `scripts/run-evals.sh:186` so graded criteria never reach the
metadata, `files:` preconditions are never materialized, and the suite runs on a
weekly cron rather than on PRs. Recorded as a coverage gap, not as an argument
for mechanism.

**The design paperwork is one paragraph.** (design-sync) The convention is an
appended `## Amendment -- <date>` section (em dash, ISO date) that leaves the
original text unedited, keeps `status: Current`, runs no `shirabe transition`,
and writes no superseding design or DECISION record. Codified as
`PRD-fold-record-removal.md` R10/AC15 and used three times on this document
family. Nothing in `shirabe validate --lifecycle` mechanically checks a Current
design's claims against the skill it describes.

**For this change specifically:** one amendment on
`DESIGN-scope-consolidation-over-skipping.md`. Its Decision Outcome (`:414-418`)
names `SKILL.md` conjunctively with the phase references, so deleting
`## Why the Artifact Set Shrinks` withdraws a named deliverable -- but "at the
layer that now performs the reduction" contrasts `/scope` with `/brief`, not
phase-2 with `SKILL.md`, so the decision holds and only a deliverable narrows.
The `## Consolidation Judgment` rewrite needs no separate paperwork. Against the
other Current designs the change is neutral-to-supported. (design-sync)

**The replacement prose exists in draft.** (replacement-prose) All five items
drafted as literal candidate text: a three-paragraph lede that lifts the
per-type contribution declarations (WHY/WHAT/HOW/WHEN) out of the four format
references and finally defines "contribution"; four per-hop passages naming each
child's real machinery and ending on what skipping strands downstream; a
`## Consolidation Judgment` cut from 47 lines of rationale to 34 lines of bound;
replacements for all three licensing sentences; and a `## The Chain Is a
Constant` section promoting `planned_chain:`'s constancy into `SKILL.md`.

**Defer verdicts, disclose premises.** (replacement-prose) The lead recommends
putting the purpose statements in `SKILL.md` rather than deferring them to the
hop, on the grounds that deferred material only governs an agent that reaches
the hop -- the exact failure in #331 -- and that the placement defect does not
apply, because "what this hop buys" is a *premise* rather than a *verdict* an
agent can aim at. This is the round's most transferable finding: progressive
disclosure should defer the outcome of a decision the agent has not earned,
while premises must arrive early, because an agent cannot optimize against a
reason to do the work.

**`SKILL.md:43-46` should be rewritten, not removed.** (replacement-prose) The
pattern's seven required structural elements do not include the asymmetry
enumeration, so removal breaks no conformance narrative, but it strands four
forward references. Changing "is the only thing reducing the artifact set" to
"can remove a document only after both documents exist" turns a stated purpose
into a stated bound and keeps the slot.

**koto does not create a context boundary.** (koto-dispatch) `koto-user/SKILL.md`
states it flatly: "koto tracks the relationship but doesn't launch child agents
-- you do that yourself." It creates a state file and a context namespace and
gates the parent until states go terminal. The isolation commonly attributed to
materialized dispatch is not koto's to give.

**The materialized binding passes children more context, not less.**
(koto-dispatch) `cross-issue-context.md` exists specifically so each `/execute`
child sees what its predecessors found, and instructs "Don't skip this step even
when only one prior child has completed."

**Neither binding was ever artifact-carrying.** (koto-dispatch) The pattern's
Layer-1 mechanism is "a parent hands a child a name and a topic key"
(`parent-skill-pattern.md:495-497`). A materialized `/work-on` child receives
four strings -- an issue number or artifact prefix, a source enum, an optional
type hint, a branch name (`plan-to-tasks.sh:373/721/728`, `execute.md:474`) --
and sources its own upstream by fetching it. The pattern states isolation is
*equal* under both bindings (`:521-528`), not greater under the second. So the
sourcing property is not reachable by changing the binding.

**What the binding would buy is gating, not starvation.** (koto-dispatch) A
`context-exists` gate could make the *parent* unable to skip a hop and still
finish. That is an enforcement-hardness upgrade on `/scope`'s existing R20
check, which today is a prose check the agent performs on itself. It is weaker
than the sourcing property and stronger than anything available now.

**The deciding objection is shape, not cost.** (koto-dispatch) `/execute` drives
a script-computed issue list with no author in the loop; its `--auto` mandate is
explicitly "do NOT pause between children" (`execute.md:424-432`). `/scope`
drives a 563-line author conversation whose unwritten content reaches children
only because the inline binding runs them in the parent's agent context
(`parent-skill-pattern.md:502-503`). Under materialization that content would
have to be serialized into koto context at each hop. In the lead's words: "That
is not a porting cost; it is a change to what `/scope` is."

**Cost, if someone decided to do it anyway.** (koto-dispatch) Dominated by four
new koto templates for children that have none -- koto's E9/F5 compile rules
require one each, authored over skills that are 900-2700 lines of conversational
prose. Then: re-expressing the eight-step per-child loop including the ~270-line
consolidation judgment as states; dual state (a koto session alongside the
255-line `wip/` schema, which `/execute` already lives with); reconciling a koto
session against a 360-line artifact-status resume ladder, where `/execute`'s
home-PR-keyed solution does not transfer because `/scope` has no PR mid-Phase-2;
a koto eval fixture apparatus built from scratch; and four cross-skill
template-path assertions. Pattern text is cheaper than feared --
`parent-skill-pattern.md:519-522` already anticipated a second parent adopting
binding two; only the Observability Surface (`:570-590`) would need widening.

### Tensions

**The reframe's premise splits.** The author proposed redirecting this work to
adopting koto for `/scope`, on the grounds that koto allows progressive
disclosure and therefore keeps an agent inside the workflow rather than handing
it everything up front. The research supports the mechanism and refutes the
isolation reading. koto delivers a state's directive when the agent reaches that
state, which is the one thing prose cannot fix, because the structural defect
round 1 identified is that `SKILL.md` loads whole at invocation and never
unloads. It does not deprive a child of anything -- children source their own
upstream under both bindings, and the materialized binding deliberately gives
them more. So the adoption case rests on instruction sequencing and gating, not
on starving the agent of what it would rationalize with.

**Progressive disclosure is not uniformly good, and a koto design could get this
backwards.** Pairing the koto finding with the prose lead's premise/verdict
distinction: a workflow that defers every instruction until its state is reached
would withhold purpose from the early states, which is precisely the condition
that produced #331. The sequencing has to defer verdicts while front-loading
premises.

**Enforcement hardness is available without the sourcing property.** R20 already
checks that the previous hop's artifact exists before the next begins. It is
prose the agent runs against itself. koto's `context-exists` gate is the same
check with a substrate that does not depend on the checker's good faith. That is
a real and modest gain, and it should not be oversold as the sourcing property.

### Gaps

- **Whether a conversational parent can be a koto workflow at all.** This is the
  live question the reframe raises and round 2 could only bound, not settle.
  `/execute`'s precedent does not transfer, because it has no author in the
  loop and `/scope`'s Phase 1 is 563 lines of author dialogue.
- **Who ticks a child session.** Nothing in `skills/execute/` names it: two
  `koto next` calls ship, both on the parent's own session, and no Agent-tool
  call or `unassigned_children` handling appears anywhere. The "fresh child"
  property asserted at `execute.md:428-430` is not visibly implemented.
- **The `/scope` eval suite cannot express the failure.** Plan-only scenarios
  grade what an agent says, not what it wrote. Any future work that wants
  evidence of adherence has to reckon with this.

### Findings that bear on other work

- **Three eval-harness defects**, independent of this issue: `expectations` read
  as `assertions` (`scripts/run-evals.sh:186`), `files:` preconditions never
  materialized, and the suite on a weekly cron rather than on PRs.
  (eval-suite)

## Accumulated Understanding

*Rewritten after round 2. Supersedes the round-1 statement above.*

The incident's cause is settled and is prose-shaped. `/scope`'s `SKILL.md`
states exactly one thing as worth wanting, and that thing is a smaller artifact
set; the sections describing what the chain does give no reason to run it; the
vocabulary of step-output is used without being defined; and the only genuine
statement of step-value in the tactical chain sits inside a child the skipping
agent never invokes. An agent reading for intent found one motivated purpose and
acted on it.

Both remedies the issue proposes fail on evidence, and both failures point the
same way. The persistence justification is already delivered at the hop, in
better words, so that half is a deletion rather than a relocation. The
write-target enumeration is not the disclosure channel -- the terminal address
appears in the Overview's second paragraph and five other places in the same
file, and the shared security contract requires the set to be stated in
`SKILL.md` with concrete paths. And the sourcing property cannot hold, because
`/scope` dispatches children inline in its own agent context and because neither
dispatch binding was ever artifact-carrying: the pattern hands a child "a name
and a topic key", and children source their own upstream. Changing the binding
does not repair that; it was never in scope for the contract at either layer.

What remains after the prose fix is structural, and it is a single thing:
`SKILL.md` loads whole at invocation and never unloads. Every phase reference is
already correctly bound to its phase. Prose can shrink the parent file, delete
its duplicated argument, define "contribution", convert six passages of
withdrawn-design narration into live instruction, and fix the two sentences that
handed over the licence. Prose cannot make that file arrive in pieces. That is
the residue, and it is what the koto question is really about.

On koto, the honest position is narrower than the enthusiasm and still worth
acting on. koto does not isolate a child and does not withhold anything from
one; the boundary people attribute to materialized dispatch is not koto's to
give, and the shipped materialized binding passes children more context on
purpose. What koto does give is a state machine whose directives arrive when
their state is reached, and gates that a parent cannot satisfy by asserting it
satisfied them. Applied to `/scope`, that addresses exactly the residue prose
leaves, and it upgrades R20 from a self-administered prose check to a substrate
gate. The obstacle is not effort but shape: `/execute` materializes a
script-computed issue list with no author in it, while `/scope` is a
conversation, and the unwritten parts of that conversation reach children today
only because the child runs in the parent's context. Whether a conversational
parent can be expressed as a koto workflow without losing the conversation is
the open design question, and it is a better question than whether `/scope`
should adopt koto.

Two constraints should travel with any koto work. It buys instruction
sequencing and gating, not isolation -- a design that assumes a boundary will
build toward one that does not exist. And disclosure should defer verdicts while
front-loading premises: "the artifact set can shrink" is a verdict an agent can
aim at and must not precede the work it judges, while "what this hop buys" is a
premise an agent cannot optimize against and can only act on. A workflow that
defers uniformly would withhold purpose from its earliest states, which is the
condition that produced this incident in the first place.

The framing content survives the reframe intact and is not superseded by it.
koto governs when a directive arrives, never what it says. A koto-driven
`/scope` whose first state delivers the current `## Why the Artifact Set
Shrinks` reproduces #331 with better plumbing.

## Decision: Crystallize

Phases 0 through 4 ran, including two full discover-converge rounds (six leads
in round 1, five in round 2, all returned). The crystallize evaluation is at
`wip/explore_scope-process-framing_crystallize.md`.

**Outcome: a chain, entering at `/scope`.** Stage 1 scored a chain at 5 with no
anti-signals, ahead of a Rejection Record at 3; stage 2 scored `/scope` at 9
with no anti-signals, ahead of `/charter` at -2 and file-an-issue at -3.
`/execute` failed its candidacy precondition (the only PLAN on disk is
`multi-pr` and off-topic) and competitive analysis failed on Public visibility.

**The author elected to re-explore under a corrected framing before scoping.**
During round 2 the author redirected the line of work: the subject is adopting
`koto` for `/scope` in a way that resolves the incident. That election is
compatible with the ranking rather than in tension with it -- the framework names
where this exploration's work enters, and the answer is `/scope`; the author's
choice is that the scoping conversation should happen under the corrected
framing, which this run reached only at its end and only after falsifying two
premises the reframe was stated with.

**Successor:** `.niwa/dispatch-briefs/scope-koto-adoption.md`, which carries this
run's findings forward -- including the two falsified premises (koto buys
instruction sequencing and gating, not isolation; the sourcing property is
unreachable under either dispatch binding), the defer-verdicts/front-load-premises
disclosure rule, the established koto costs, and the framing content that
survives the reframe because koto governs when a directive arrives, never what it
says.

**Do not resume this exploration.** It is complete through Phase 4. Phase 5
(Produce) is deliberately not run here: the successor exploration receives the
work, and producing a handoff into `/scope` on the superseded framing would
route the author into a scoping conversation they have already set aside.
