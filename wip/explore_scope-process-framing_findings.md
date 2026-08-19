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
