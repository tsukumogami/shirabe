# Lead: Does `/scope` have a lower bound of applicable work, and what should an author holding thirteen documentation edits actually run?

## Findings

### 1. No routing surface names a destination for a coordinated multi-file documentation change

`/explore`'s Routing Guide (`skills/explore/SKILL.md:35-49`) offers seven rows.
The tactical-chain row is `"I have one feature to specify, from its framing
through its issues" -> /scope <topic>` (line 44). The two rows that could absorb
small work are `"This is simple, just do it" -> /work-on <issue>` (line 47) and
`"I have a PLAN and want it built" -> /execute <plan-path>` (line 46). Nothing
names a coordinated, multi-file, multi-repo change with no feature to specify.

The Quick Decision Table (`skills/explore/SKILL.md:53-63`) is the same shape.
`"Do I need any document at all?" -> File an issue, then /work-on`, with
`/scope` as the alternative "if the scope is likely to grow". `"What should we
build, and how?" -> /scope`.

The crystallize framework, which is the surface that actually decides after an
exploration, is narrower still. Stage 2 has exactly four entry points
(`skills/explore/references/quality/crystallize-framework.md:118-183`): File an
Issue, `/charter`, `/scope`, `/execute`. `/plan` is not among them, and
`grep -rn '`/plan' skills/explore/` returns only three hits, none of them a
routing destination — two are label-mechanics references and one is a
disclaimer that `/explore` writes none of those artifacts.

Score the incident's shape against those tables honestly and it lands nowhere.
Against File-an-Issue, the signal "one person can implement without
coordination" fails (the effort spanned two repos with landing order). Against
`/scope`, the lead signal "a single coherent feature emerged from exploration"
fails (there was no feature), and the anti-signal "multiple independent
features whose order affects delivery" half-fires on the sequencing. The work
scores weakly on both and strongly on neither. `/scope` wins by being the only
chain destination for tactical work, not by matching.

The one place the corpus does recognize documentation-shaped work is at
execution altitude: a PLAN issue outline carries an optional
`**Type**: code | docs | task` field (`skills/plan/references/quality/plan-doc-structure.md:211-223`),
and `/work-on`'s plan-backed child mode routes `docs` past the scrutiny, review
and QA panels straight to finalization (`skills/work-on/SKILL.md:168-171`). So
documentation work is a recognized work shape one altitude below the routing
question and an unrecognized one at the routing question itself.

### 2. The collapse removed the only two rows that named `/plan` as a destination — including the sequencing row

`git show 39b0981 -- skills/explore/SKILL.md` (the commit that collapsed the
tables, "feat(corpus): state one model for chain-step mandatoriness (#316)")
shows what the old tables carried. Two deleted rows named `/plan`:

    | "I have a design doc, need to break it into issues" | `/plan <design-doc-path>` | Decomposition of an existing artifact |
    | "What order do we build in?" | Plan | Design Doc (if approach isn't decided) |

The second one is the row the lead asks about. "What order do we build in?"
with Plan as the destination is a close description of the incident: known
edits, no open requirements, no architecture, real sequencing. It is gone.

The stated rationale for the collapse is at `skills/explore/SKILL.md:62-68`:
each removed distinction "separated two hops of the same chain, and each
mattered only while those hops were separately choosable." That rationale holds
cleanly for "PRD or design doc?" and for the what/how split. It over-applies to
the sequencing row, because `/plan` is not only a hop. It is a standalone entry
point with its own no-upstream input mode, which the next finding covers.

The Medium row (`| Medium | Known approach, some integration risk, design
decisions between viable options | /design then /plan |`) was also deleted, with
the note at `skills/explore/SKILL.md:87-92` that "a request that used to land on
Medium reads as Complex here." Medium would not have caught the incident either
— its condition is "design decisions between viable options", and there were
none. The row that would have caught it is the sequencing row, not Medium.

### 3. `/plan <topic>` is a real standalone entry point, and the router does not know it exists

Four surfaces guarantee direct child invocation:

- `skills/plan/SKILL.md:9` (the description): "Also use for direct topic
  planning without a source document."
- `skills/plan/SKILL.md:258-261`, Input Detection case 3: "**Anything else** --
  treat as a direct topic (input_type: topic). No upstream document is required.
  Use when /explore produced a clear scope with no open decisions, or when
  planning a well-understood list of capabilities directly."
- `CLAUDE.md:239-241`: "The child skills `/brief`, `/prd`, `/design`, and
  `/plan` remain directly invocable on their own for authors who already know
  which altitude they want."
- `skills/scope/references/phases/phase-1-discovery.md:38-42`: "`/design
  <topic>` and `/plan <topic>` are the documented ways to enter the tactical
  chain above `/brief`, and that choice is theirs and visible in what they
  typed. It is supported and stays supported."

So the destination exists, is documented three times, and is described in
`/plan`'s own input detection in terms that fit the incident almost exactly
("a well-understood list of capabilities"). The routing surface an agent reads
to find a destination does not carry it. That is a genuine surface-level
contradiction, not a judgment call.

### 4. Coordination is the property that forces `/scope`, and it is a hard force

The incident's work was coordinated across repos, and that is not a soft
signal. `references/coordination-strategy.md:6-7` states the binding: "`/scope`
and `/work-on` bind to this contract and carry only bindings — no consumer
restates it."

`/scope` owns creation. `skills/scope/SKILL.md:224-234`: "When intent is
present, `/scope` creates the coordination PR **up front**, before invoking any
child... `/scope` writes the body from the copy-pasteable template."

`/execute` explicitly refuses to create it. `skills/execute/SKILL.md:294-296`:
"This path is **metadata-only**: it reads issue/PR status and the merge-gate
result, never child PR bodies. It runs against an existing coordination PR
(**creating the coordination home up front stays `/scope`'s responsibility**;
`/execute` consumes it)." Step 1 then says "Locate the coordination PR for this
effort... before entering the loop" (`skills/execute/SKILL.md:313-315`).

`/plan` can produce a coordinated PLAN — `execution_mode: coordinated` with
per-issue `repo` and `pr_group` tags and a two-node merge-order DAG
(`skills/plan/SKILL.md:190-213`) — but nothing in `skills/plan/` mentions
creating a coordination PR (`grep -rn -i 'coordination PR' skills/plan/`
returns nothing).

So the sanctioned coordinated path is: `/scope --coordinated` creates the home,
then `/execute` consumes it. A standalone `/plan <topic>` in coordinated mode
produces a PLAN that `/execute` will then halt on, because the coordination PR
it requires was never authored. **There is no sanctioned path for a coordinated
multi-repo effort that does not go through `/scope`.** That is the strongest
piece of evidence that the incident's author had a real forcing function, not
just a bad habit.

Worth noting: `references/coordination-strategy.md:90-95` templates the
coordination PR body's Artifact Chain section as a four-line list — BRIEF, PRD,
DESIGN, PLAN. The coordinated contract's own body template presumes the full
chain ran.

### 5. The cost test: two of the three upstream documents have content to hold; one would be padded

**BRIEF** (`skills/brief/references/brief-format.md:125-177`): Status, Problem
Statement, User Outcome, User Journeys, Scope Boundary. For a coordinated
documentation effort, Problem Statement holds ("the shipped surfaces say X and
the behavior is Y"), User Outcome holds (what a reader can do afterward), Scope
Boundary holds *well* — which files are in, which look adjacent and are out, is
precisely the live question when the work is "five files across two repos".
User Journeys is the strained one: each journey must name "a concrete user, the
trigger that starts the journey, and the outcome shape" (line 168-172), and
journeys must be "distinct -- each exercises the feature from a different entry
point". A documentation change has readers rather than users, and writing three
distinct entry points into a set of doc edits is where padding starts.

**PRD** (`skills/prd/references/prd-format.md:70-87`): Status, Problem
Statement, Goals, User Stories, Requirements (numbered R1, R2, ... specific and
testable), Acceptance Criteria (checkboxes, "the contract"), Out of Scope. This
is the *most* applicable of the three to the incident's shape, not the least.
Thirteen edits map to thirteen numbered requirements and thirteen checkboxes
without strain, and "each requirement should be specific and testable" is
easier to satisfy for a prose edit than for most code. User Stories is the one
soft spot, and the format already grants the escape: "Use case descriptions are
acceptable for technical features where user stories feel forced" (line 79-80).

**DESIGN** (`skills/design/SKILL.md:71-84`): Status, Context and Problem
Statement, Decision Drivers, Considered Options ("at least 1 alternative per
decision"), Decision Outcome, Solution Architecture ("components, interfaces,
data flow"), Implementation Approach, Security Considerations ("always
include"), Consequences. This is the honest one. Solution Architecture has
nothing to hold for prose edits — there are no components, interfaces, or data
flow. Security Considerations is mandatory and would be a paragraph saying
documentation carries no new surface. Considered Options requires at least one
alternative per decision when the only decisions are wording and placement.

The chain already knows this and already sizes for it. R6 walks three predicates
(`skills/scope/references/phases/phase-1-discovery.md:207-284`): P1
architectural-alternatives count, P2 new-component references, P3 Complex
classification. For thirteen documentation edits all three read as
does-not-fire. `skills/scope/references/phases/phase-1-discovery.md:291-297`:
"All-negative verdicts still invoke `/design`; they size it down to the minimum
roster, and the resulting DESIGN records the one live option and why no
alternative was live. That is a shorter document than a contested design, and
it is a better audit trail than the silence it replaces."

So the padding pressure on DESIGN is real, and the skill's answer is a smaller
DESIGN rather than no DESIGN — an answer that is defensible and that
`SKILL.md` never surfaces to an agent, because it lives in a Phase 1 reference
file the agent may not have read when it makes the decision to skip.

### 6. The absorb path's cost is real, and its endpoint is byte-for-byte the shortcut's endpoint

Phase counts across the four children: `/brief` 6 phases with a two-reviewer
jury (`skills/brief/SKILL.md:211-227`); `/prd` 5 phases with parallel research
agents and a 3-agent jury (`skills/prd/SKILL.md:99-112`); `/design` 7 phases
including per-question decision agents, cross-validation, and a mandatory
security review (`skills/design/SKILL.md:160-174`); `/plan` 7 phases including
an adversarial `/review-plan` pass (`skills/plan/SKILL.md:446-456`). That is 25
phases, four human approval gates, three juries, and one security review.

Then the consolidation judgments. For a run that folds all the way down, three
hops fire, each running the eight-step procedure at
`skills/scope/references/phases/phase-2-chain-orchestration.md:554-673`:
citation preflight script, read both bodies, compose the contribution section in
memory, itemize a carry check (which accumulates — "a survivor absorbing a
document that already carried two contributions must confirm three things
carried", line 634-637), snapshot, splice `upstream:`, write `absorbed:`, write
the `## Status` absorption line, write the contribution section, rewrite the
survivor's own citations, `git rm`, re-run `shirabe validate`, commit. Times
three, with a rollback table per hop.

And the endpoint of all that is a single PLAN carrying
`absorbed: [brief, prd, design]`, which the implementation cascade then deletes
(`skills/plan/SKILL.md:37-40`). The shortcut's endpoint is a single PLAN. The
issue records that the validator caught the difference exactly once — FC18
rejected `absorbed: [brief, prd, design]` because the entries named documents
that did not exist — and that deleting the field made both paths validate
identically.

So the cost is not imagined. The expensive path and the free path converge on
the same artifact set, and the difference between them is entirely process:
three juries, one security review, one adversarial plan review, four approval
gates. Under the author's framing ("the process is the product") that is the
whole value and the convergence is not a defect. Under the framing the skill
currently states in prose (a smaller artifact set is better for the reader),
the two paths deliver the same product and one of them is free. The agent
optimized against the framing the document actually gave it.

### 7. Prior art: the floor question was asked, answered, and the answer was "no floor"

**Issue #280 (CLOSED)**, "/scope always leaves a permanent PRD and DESIGN, so it
cannot be the default entry point for work that warrants neither", is the
closest prior art and it is directly on point. Its opening line: "`/scope` is
the front door for tactical work of any size. Some of that work warrants a
durable PRD and DESIGN; plenty of it doesn't." Its central argument: "That's a
coherent position if `/scope` is one altitude-specific entry point among
several. It isn't the right position if `/scope` is meant to be the entry point
authors reach for by default, which is how it's being used. Asking the author to
predict, before starting, whether the work will turn out to warrant durable
artifacts is the same before-the-fact judgment #260 removed from Phase 1 — just
relocated into the choice of which skill to type."

That issue produced the artifact-persistence work.
`docs/briefs/BRIEF-scope-artifact-persistence.md:64-73` states the outcome:
"The author does not choose between those outcomes, and does not have to know
which one they are heading for when they start. They run one command, the chain
runs whole, and each hop's verdict is decided against the two documents in front
of it." Its first named user journey is literally titled "An author scopes a
self-contained fix and the chain folds to nothing durable" (line 75).

So the repository has already ruled, deliberately and recently, that **`/scope`
has no lower bound of applicable work**. The cost it removed was the
artifact-set cost. The cost it did not address, and did not claim to address, is
the process cost — 25 phases and four approval gates still run before the folds
begin.

**The removed redirect.** `skills/scope/references/phases/phase-1-discovery.md:303-329`
records what the artifact-persistence work deleted: "This section previously
stated a durable-artifact floor: that the smallest set a run could end with was
a PRD, a DESIGN and a PLAN... It also told maintainers not to guard the
zero-artifact case... **and redirected an author who wanted no durable record to
invoke `/plan` directly**." And: "the no-durable-record redirect went with them:
it pointed at an escape hatch from a floor that is no longer there."

This is the second removal of a `/plan`-as-destination pointer, in a different
file, for a different and independently sound reason. Between the two commits,
`/scope` lost the sentence pointing small work at `/plan`, and `/explore` lost
the two rows pointing sequencing work at `/plan`. Neither removal is wrong on
its own terms. Together they left no surface an agent reads that names
`/plan <topic>` as a destination.

**Related but distinct prior art:** issue #259 ("docs(readme): structure,
vocabulary and entry points defeat a first-time reader", OPEN) and issue #3
("Onboarding and skill discovery for new users", OPEN) both touch entry-point
discoverability, but neither discusses a work-size threshold. Issue #273 ("The
tactical workflow cannot produce a second downstream document under one
upstream", OPEN) is a different structural limit. No issue or design doc in the
corpus proposes a minimum-viable-work threshold for the chain.

### 8. `/scope`'s only redirect explicitly disclaims the motive an agent would have

`skills/scope/SKILL.md:508-517` does carry a redirect: "**A shorter
conversation is still reached by invoking a child directly.** `/design <topic>`
and `/plan <topic>` enter the tactical chain above `/brief`... What it no longer
is, is the route to a smaller artifact set: that is consolidation's call."

Read by an agent whose stated motive is artifact-set economy — which is exactly
what the incident's Status section records — this paragraph says: the exit you
are looking for is not this one, go back to consolidation. The redirect names
the right destination and then tells the reader it does not solve the problem
they have. `skills/scope/references/phases/phase-1-discovery.md:44-49` repeats
the disclaimer verbatim.

That is a placement observation more than a routing one, and it belongs beside
the issue's placement defect rather than replacing it. But it means the "just
route it elsewhere" answer is already present in `SKILL.md` and already
neutralized by the sentence following it.

## Implications

There is a real mismatch, and it is narrower than "the chain is too expensive
for small work."

The artifact-set half of the cost argument has already been fixed and the fix is
the settled position: `/scope` is the front door for tactical work of any size,
and a run against small work is designed to fold down to nothing durable. The
issue's framing ("the process is the product") is consistent with that, and the
answer to "the chain is too expensive" is not "route it out" — the repository
already decided it does not want a size-based route out.

What is genuinely missing is a *shape*-based destination, and the missing case
is narrow and identifiable: coordinated multi-file work with real sequencing and
nothing to specify. That case cannot leave `/scope`, because `/scope` is the only
skill that authors the coordination PR and `/execute` refuses to create one. So
for the incident specifically, `/scope` was in fact the correct command. The
author's economic complaint was legitimate and the routing answer to it is
"nowhere else, by design."

That reframes the fix. If `/scope` is correct for coordinated documentation
work, then what `SKILL.md` owes such an agent is not a redirect but a reason to
run the steps — which is the issue's own proposal. A routing sentence added to
`/scope` would have to say "run this anyway", which is a purpose statement
wearing a routing sentence's clothes.

Two things are separable and worth filing rather than folding into this issue:

1. `/explore` no longer names `/plan <topic>` as a destination, while `/plan`,
   `/scope`'s Phase 1, and CLAUDE.md all guarantee it. That is an `/explore`
   defect, outside this issue's blast radius, and it is real independent of
   anything about `/scope`'s argumentation.
2. `/plan` in coordinated mode produces a PLAN that `/execute` will halt on,
   because no surface creates the coordination PR outside `/scope`. That is
   either a documented restriction that should be stated in `/plan`, or a gap.

Neither is a prerequisite for fixing #331.

## Surprises

**The PRD is the most applicable upstream document for documentation work, not
the least.** The intuition that "thirteen doc edits don't warrant a PRD" does
not survive contact with the format. Numbered testable requirements and
checkbox acceptance criteria map onto thirteen discrete edits more cleanly than
onto most code changes. The DESIGN is the one that would be padded, and the
chain already sizes it down for exactly this case.

**The chain proposal already tells the author the folds are coming.** The
skeleton at `skills/scope/references/phases/phase-1-discovery.md:355-357` ends
with "Any artifact that turns out to be redundant is absorbed after it and its
successor both exist, not skipped now." An agent that reads Phase 1 sees this.
An agent that reads only `SKILL.md` sees the forty-line argument for why the set
shrinks and not this sentence.

**Two independently-sound edits removed the same pointer.** The `/explore`
collapse and the artifact-persistence floor removal each deleted a
`/plan`-as-destination reference, in different files, months apart, for
different reasons, and neither would have looked wrong in review. The result is
that `/plan <topic>` is documented as supported in three places and reachable
from none of the surfaces an agent consults when deciding what to run.

**`/scope`'s security enumeration and the coordinated contract's body template
both publish the full chain up front.** The issue already names the write-target
set (`skills/scope/SKILL.md:847`). The coordination PR body template at
`references/coordination-strategy.md:90-95` does the same thing in a second
place — a four-line Artifact Chain listing BRIEF, PRD, DESIGN, PLAN, authored
before any child runs, which the incident's own coordinated setting would have
required the agent to fill in. That is a second surface printing every address
in the chain before the journey. It is outside the `/scope`-prose blast radius
if the fix touches only `SKILL.md`, but it is the same defect shape.

## Open Questions

- Does the author want `/scope` to state, in prose, that it is the front door
  for tactical work of any size — making the #280 position visible to an agent
  rather than only recoverable from a closed issue and a brief? That is
  prose-and-placement, inside the blast radius, and it directly counters the
  economic motive.
- Should the missing `/explore` row be filed separately, or is naming it in
  #331's findings enough? It is outside the stated blast radius either way.
- Is the process cost (25 phases, four approval gates, three juries) something
  the author considers a problem at all, or is it the product? The issue's
  framing suggests the latter, in which case the finding here is that nothing
  says so where an agent reads it.
- Would a `Type: docs` notion at scoping altitude — parallel to the one PLAN
  outlines already carry — be a floor by another name, and therefore forbidden
  by the same reasoning that removed the durable-artifact floor?

## Summary

`/scope` has no lower bound by deliberate decision: closed issue #280 argued
`/scope` is "the front door for tactical work of any size", and the
artifact-persistence work implemented that by making every hop absorbable so
small work folds to nothing durable — the cost the author feared was removed,
not routed around. But the incident's work had a forcing property beyond size:
it was coordinated across repos, and `/scope` is the only skill that authors the
coordination PR (`skills/execute/SKILL.md:294-296` — "creating the coordination
home up front stays `/scope`'s responsibility"), so no alternative destination
existed and `/scope` was in fact the right command.

The `/explore` collapse did remove the row that would otherwise have caught this
shape — `| "What order do we build in?" | Plan | ... |` — and the
artifact-persistence work separately removed `/scope`'s sentence redirecting
no-durable-record work to `/plan`; together they leave `/plan <topic>` supported
in `/plan`'s own SKILL.md, CLAUDE.md, and `/scope`'s Phase 1, and named as a
destination by no routing surface an agent reads.

The cost claim is half true: of the three upstream documents, the PRD fits doc
work well (thirteen edits map to thirteen numbered testable requirements) and
only the DESIGN would be padded — and R6 already sizes that DESIGN to a minimum
roster. What is genuinely expensive is process, not paper: 25 phases, four
approval gates, three juries and a security review, converging on the same
single PLAN the shortcut produced in one step.
