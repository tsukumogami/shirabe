# Content Quality Review: BRIEF-work-on-standalone-completeness

## Verdict
PASS

## Per-criterion findings

### 1. Problem Statement: problem, not smuggled solution

The statement is: "A `/work-on` run invoked on its own opens a pull request and then stops, leaving a change that looks finished and is not." That names a gap a reader feels (a false sense of completion), not a feature to build. It then walks through the evidence (three dispatched runs, two days, three repos) and a diagnosis that explicitly rejects the naive fix ("the obvious reading of this is that the steps live in the wrong skill... that reading is half wrong"). Rejecting a candidate solution and narrowing to the actual gap is the opposite of smuggling one in.

The two counter-intuitive claims flagged in the task brief are both present and both argued rather than asserted: "`/work-on` never creates a draft pull request, so there is nothing for it to mark ready" is given as a factual claim about current behavior, and "it already carries the closing keyword and the pull-request body contract, in a reference file that `/execute` consumes too" is followed by direct evidence — "the instruction to include the closing keyword reached all three of those runs and all three skipped it, which is what tells you the gap is enforcement and not delivery." That is a real inferential chain (instruction existed → was reachable → was skipped anyway → therefore the defect is enforcement, not absence), not a bare assertion the reader has to take on faith.

One recurring phrase sits close to the solution/problem line: "the rest of the finishing obligations exist as prose a run may skip rather than as gated states a run cannot pass" (repeated in the frontmatter `problem` field and body). "Gated states" echoes `/execute`'s actual mechanism (named two paragraphs later: "workflow states with evidence schemas"). This is defensible as diagnosis — it's describing a real, already-existing contrast (prose in one skill vs. enforced states in the sibling skill) rather than inventing a new mechanism for `/work-on` to adopt — but it is the one place a stricter reading could call it solution-adjacent. It does not cross into prescribing a fix; the brief never says `/work-on` must use workflow states or evidence schemas.

### 2. User Outcome: outcome-shaped

The section is written from the vantage of the person running the skill: "ends up with a pull request that is actually mergeable... nothing waiting on a person to remember a step," and for the failure path, "it stops and says which obligation it could not discharge, rather than reaching a terminal state that reads as success." That is what changes for the user, not a list of what gets built. It names the user explicitly twice (the person running `/work-on`, and separately "a dispatched agent running the skill unattended" plus "a person reviewing the result afterwards"). It matches the frontmatter `outcome` field's content. The closing line about plan cadence ("Running a whole plan is unaffected in cadence...") is a boundary clarification rather than a feature enumeration — it tells the reader what does *not* change, which is still framed as an experience, not a parts list.

### 3. User Journeys: concrete and distinct

Four journeys, each with a `###` heading, a named user, a trigger, and an outcome shape:

- Maintainer, ordinary issue with no document chain → cascade passes through cleanly, invisibly.
- Maintainer, issue at the end of a document chain → chain gets pulled to terminal state as part of the same run.
- Orchestrator, multi-issue plan → cascade fires once at the plan level, per-issue children do not finalize.
- A person handing a multi-pr plan to the single-issue entry point → redirected to the correct entry point instead of a silent partial result.

These are genuinely different entry points, not the same path re-told: no-chain vs. with-chain vs. plan-level vs. misuse/redirect. The third journey is the one worth double-checking against the second, since both involve document chains — but the second is explicitly the single-issue path finalizing its own chain, and the third is explicitly the single-issue path *not* finalizing because a plan owns it. That is the distinction the whole brief hinges on (child runs get a "do not finalize" signal), so keeping both journeys is correct rather than redundant; collapsing them would erase the exact contrast that matters most for this feature.

### 4. Scope Boundary: real exclusions

IN list: cascade reachability from a single-issue run (including the no-chain case), prose-to-gate conversion, ownership of shared cascade machinery, moving multi-pr execution to the plan-owning skill, a distinct "do not finalize" signal for children, and reachability of obligations by a child run. These are specific enough that a PRD author knows what's being built.

OUT list, checked one by one against "would a reader otherwise assume this is in scope":
- Definition-of-done gate returning cannot-verify — plausible assumption, since the brief is about the same finishing pipeline; explicitly scoped out as a pre-existing per-repo configuration gap unrelated to this feature.
- Staleness gate calling a missing script — same pipeline, same treatment, cites it's already tracked elsewhere.
- Terminal workflow states destroying their own context record — a plausible adjacent target given the theme of "gates and terminal states," explicitly filed and solved elsewhere.
- Gates unable to observe whether a review panel ran — plausible given the "enforcement" theme, deliberately deferred with a stated reason (avoid redesigning it twice).
- Naming fossils from the earlier skill split — plausible since the brief revisits that same split's decisions, acknowledged as worth doing but not this feature.
- Merging the pull request — directly adjacent to "reaches a mergeable pull request," the most obvious place a reader could assume the boundary extends further than it does.

None of these read as filler ("world peace"); each is something a reader tracking the same problem space could plausibly assume was included. Both lists carry enough specificity for a downstream PRD author to know where the feature ends.

### 5. Open Questions: genuine deferrals, not a hidden blocker

Three questions:
- Whether the single-issue skill keeps accepting a multi-pr plan for compatibility, refuses it, or stops accepting it, and what a misuse case sees.
- Whether the cascade changes what "done" means for a no-document issue, or is a pure pass-through.
- Whether the two accepted documents this feature contradicts (DESIGN-execute-skill.md, PRD-execute-skill.md) get superseded by a decision record or amended in place.

All three are framing choices with multiple reasonable answers that a PRD is positioned to settle (compatibility posture, semantics of "done" for an edge case, and procedural handling of contradicted prior decisions). None of them reads as "we don't know if this feature should exist" — the brief has already committed to the feature's shape via its Problem Statement, User Outcome, and Scope Boundary. The third question is the most interesting one to check: it flags that this brief inverts recorded decisions in two accepted documents, but treats "how to formally supersede them" as a process detail for the PRD, not as a reason the brief itself is unsound — that's a legitimate defer, not a buried blocker, precisely because the brief's References section shows the contradiction was investigated, not overlooked.

### 6. Content boundaries

No numbered functional requirements, no acceptance criteria, no user stories, no implementation task breakdown, no feature sequencing against other features. The closest thing to technical detail is the paragraph about child workflows being "seeded directly from its compiled template and never loads the skill's own `SKILL.md`" — this is architecture-flavored, but it's used to explain *why* the problem is hard to fix in the wrong place (a reachability constraint on the bug itself), not to specify how the fix should be built. It stays at the level of "here is a fact about the current system that makes this problem sneaky," which is consistent with the Problem Statement's job of making the gap legible. The IN list mentions "a signal that tells a child run not to finalize" and "where the shared cascade machinery lives" as boundary items, not designs — no interface shape, no data flow, no state name is specified. This brief stays at BRIEF altitude throughout.

### 7. Public-visibility cleanliness

This is the `tsukumogami/shirabe` repo (confirmed via `git remote -v`), a public repo per the workspace's repo table. The only issue reference is "tracking issue #361" with no repo qualifier, which per the format doc's rule reads as a same-repo (public) issue number and is explicitly permitted ("public GitHub issue numbers from the same repo are routinely cited and not in scope of this restriction"). A grep of the document for private-repo names, internal codenames, and workspace-internal terms (`private`, `vision`, `coding-tools`, `dot-niwa`, `tsukumogami/<repo>#`) returned nothing. The References section cites four in-repo documents (two DESIGN/PRD files, two DECISION records), all of which exist in this repo's `docs/` tree and are durable, non-`wip/` paths. No private-visibility leakage found.

## Required changes

None.

## Observations

- The "gated states" framing (frontmatter `problem` and body, criterion 1) sits close to naming the shape of a fix. It stays on the right side of the line because it describes an already-existing contrast in a sibling skill rather than proposing new machinery for this one, but if a future revision starts prescribing *how* the enforcement should work (specific schema shapes, state names) inside this document, that would need to move to Open Questions or be cut.
- The brief is unusually forthright about inverting two previously accepted documents (DESIGN-execute-skill.md, PRD-execute-skill.md). That is exactly the kind of thing a Problem Statement should surface rather than bury, and it does — worth calling out as a strength, not just a pass.
