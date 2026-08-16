# Phase 4: Crystallize

Evaluate accumulated findings to decide what the exploration reached and where
its work goes next.

## Goal

Score the exploration's findings against the crystallize decision framework in
two stages, rank the results, and present the user with a recommendation. Stage 1
scores what the exploration is; stage 2 scores which entry point receives a chain.
The user confirms, rejects all options (loop back), or picks an alternative.

## Resume Check

If `wip/explore_<topic>_findings.md` has a `## Decision: Crystallize` marker
but `wip/explore_<topic>_crystallize.md` doesn't exist, the user already chose
to crystallize but the evaluation wasn't written. Run the full evaluation.

If `wip/explore_<topic>_crystallize.md` already exists, skip to Phase 5.

## Inputs

- **Findings file**: `wip/explore_<topic>_findings.md` (especially the
  `## Accumulated Understanding` section)
- **Research files**: `wip/research/explore_<topic>_r*_lead-*.md` (for detail
  when the findings summary is insufficient)
- **Scope file**: `wip/explore_<topic>_scope.md` (for the `## Visibility` value
  the competitive-analysis precondition reads, and for the `## Entry Assessment`
  section when Phase 0 wrote one)
- **Crystallize framework**: loaded in Step 4.1

## Steps

### 4.1 Load the Decision Framework

Read the full crystallize framework:
`../quality/crystallize-framework.md`

This file contains the candidacy preconditions, the stage-1 and stage-2
signal/anti-signal tables, the evaluation procedure, every tiebreaker rule, the
disambiguation rules, and handling for the deferred type. Don't rely on the
summary in SKILL.md -- load the full reference.

### 4.2 Read Accumulated Findings

Read `wip/explore_<topic>_findings.md`. Focus on:

- **Accumulated Understanding** -- the synthesized view of everything learned
- **User Focus** sections from each round -- what the user said matters most
- **Tensions** and **Gaps** -- these often indicate what remaining uncertainty
  the next step has to absorb
- **Decisions** sections from each round -- what was already decided

Also read `wip/explore_<topic>_decisions.md` if it exists. The decisions file
tracks scope narrowing, option elimination, and priority choices made during
convergence rounds. These decisions directly inform the evaluation -- if
decisions were made, they need to live somewhere permanent, which weighs against
filing an issue and walking away.

If the decisions file doesn't exist, that's fine -- it means no explicit
decisions were captured (common in first rounds or purely informational
explorations).

If the Accumulated Understanding section is thin, also read the individual
research files from the latest round for detail.

### 4.3 Establish Candidacy

Before scoring anything, evaluate the two preconditions. A precondition governs
candidacy, not weight: an arm that fails one is absent from the ranking, absent
from the options you present, and must not be mentioned in the recommendation.

**`/execute`:** look for a qualifying PLAN -- a file at `docs/plans/PLAN-*.md`,
or any `.md` whose frontmatter has `schema: plan/v1`, whose `execution_mode` is
`single-pr` or `coordinated`. A `multi-pr` PLAN does not qualify; `/execute`
refuses that mode. No qualifying PLAN means no `/execute` arm this run.

```bash
ls docs/plans/PLAN-*.md 2>/dev/null
```

Read the frontmatter of any match before treating it as qualifying.

**Competitive analysis:** read the `## Visibility` section of
`wip/explore_<topic>_scope.md`, written by Phase 0. `Public` removes the
category from stage 1.

Record both outcomes. They go into the crystallize decision file.

### 4.4 Score Stage 1

**Before scoring, remember:** artifacts capture decisions already made, not just
decisions yet to be made. `wip/` is cleaned before every PR merges. If exploration
produced architectural choices, dependency selections, or design rationale, those must
live in a permanent document. The question is not "is anything still undecided?" —
it's "did we decide something a future contributor needs to know?"

For each candidate stage-1 category (Rejection Record, Spike Report, Decision
Record, Competitive Analysis, A Chain):

1. Walk through the signal table. For each signal, check whether the findings
   provide evidence for or against it. Be specific -- cite actual findings,
   not vague impressions.
2. Walk through the anti-signal table the same way.
3. Score = count of signals present minus count of anti-signals present.

Also check the deferred type (Prototype). If it scores highest, handle it per
the framework's Deferred Types section before continuing.

### 4.5 Rank, Demote, and Break Stage-1 Ties

Rank the stage-1 categories by score, highest first.

Apply the demotion rule: any category with one or more anti-signals present drops
below all categories without anti-signals, regardless of raw score. A category
scoring 3 with 1 anti-signal ranks below a category scoring 1 with 0 anti-signals.
This applies to "a chain" exactly as it applies to the four terminal outcomes.

If the top two are tied or within 1 point after demotion, apply these:

- **A chain vs Rejection Record**: overall conclusion "proceed" -> a chain.
  "Don't proceed" -> Rejection Record.
- **A chain vs Spike Report**: did the exploration answer "can we?" and stop, or
  did the answer commit someone to building? Answered and stopped -> Spike
  Report. Committed -> a chain.
- **A chain vs Decision Record**: is the entire output one choice between named
  options? Yes -> Decision Record. One input among several a build still needs
  -> a chain.

### 4.6 Decide Whether Stage 2 Runs

Run stage 2 if either holds:

- "A chain" is the top-ranked stage-1 category
- "A chain" is within 1 point of the top-ranked category after demotion

The second condition exists because a stage-1 error can't be recovered at stage 2.
An exploration wrongly scored as a terminal outcome would never reach the entry
points at all, so a near-tie presents both and the author sees the entry point the
close call nearly cost them.

If neither holds, the recommendation is the terminal outcome. Skip to Step 4.8.

### 4.7 Score Stage 2, Rank, Demote, and Break Ties

For each candidate entry point (File an Issue, `/charter`, `/scope`, and
`/execute` only if Step 4.3 established its candidacy), walk the signal and
anti-signal tables the same way and score. Rank, then apply the same demotion
rule.

If the scope file carries an `## Entry Assessment` section, read it as one more
piece of evidence here: it says what the issue looked like before any research
ran. It is evidence, not a verdict, and the findings win where the two
disagree -- the assessment saw only the issue body.

If the top two are tied or within 1 point after demotion, apply these:

- **`/scope` vs File an issue**: can one person act on this without a written
  contract? Yes -> file an issue. No -> `/scope`.
- **`/charter` vs File an issue**: does anyone else need the strategic argument?
  Yes -> `/charter`. No -> file an issue.
- **`/charter` vs `/scope`, the existence question**: does the project exist yet?
  No -> `/charter`. Yes -> `/scope`.
- **`/charter` vs `/scope`, the multi-feature boundary**: does the work span more
  than one feature whose order affects delivery? Yes -> `/charter`. One bounded
  feature, however large -> `/scope`. Feature size is not the test; the number of
  separately-sequenced features is.
- **`/scope` vs `/execute`**: a qualifying PLAN unlocks `/execute`, and that is
  already settled as a precondition. Nothing else on disk unlocks anything: a PRD
  or a DESIGN covering this topic is **not** a reason to enter the chain below
  `/scope`. The chain runs whole and reduces per hop afterward, against artifacts
  that exist. Reading an existing upstream document as permission to skip ahead
  is the most likely route back to entry-altitude selection.
- **`/execute` vs File an issue**: is the whole PLAN the work, or one issue out
  of it? The whole PLAN -> `/execute`. One issue -> file it, next step `/work-on`.

### 4.8 Check for Insufficient Signal

If no stage-1 category scores above 0 after demotion, the findings are too vague.

1. Tell the user the findings don't clearly point anywhere.
2. Identify which signals are missing and what questions would surface them.
3. Recommend another discover-converge round with specific leads targeting
   the gaps.
4. Return control to the orchestrator, which routes back to Phase 2 with
   new leads.

Don't force a choice when the evidence isn't there.

If stage 1 returned a chain but nothing scores above 0 at stage 2, don't loop
back. Work exists; only its altitude is unsettled. Present the candidate entry
points and let the author choose.

### 4.9 Present Recommendation

Use AskUserQuestion to present the evaluation results. Format the options
so the user can make an informed choice.

**Recommendation** -- the top-ranked outcome, marked "(Recommended)". For a
terminal outcome, explain which signals matched. For a chain, name the entry
point and the exact command to run. Ground the explanation in what the
exploration discovered rather than in generic signal descriptions.

**Alternatives** -- other candidates that partially fit. For each, note which
signals matched and which anti-signals or missing signals caused the lower
ranking. Never offer an arm that failed its precondition in Step 4.3.

**Deferred type** (if it scored well) -- note separately with the suggested
alternative from the framework.

**"None of these"** -- always include as the last option. If selected, the
user goes back to explore further.

Example AskUserQuestion:

> Based on your exploration findings, here's where this lands:
>
> 1. **`/scope` (Recommended)** -- The exploration converged on one feature, the
>    version resolver, and left both a requirements gap (provider fallback order)
>    and an architectural one (three competing resolver designs). Run
>    `/scope version-resolver`.
> 2. **File an issue** -- Partially fits: the CLI surface is small. But three
>    approaches need comparison first, and Round 2 settled a dependency choice
>    that needs a durable home.
> 3. **Spike Report** -- Ranked lower because feasibility was never the open
>    question; all three approaches work.
> 4. **None of these** -- Go back and explore further.

### 4.10 Route Based on User Choice

**Outcome selected:** Proceed to Step 4.11 (write decision), then Phase 5.

**"None of these":** Return control to the orchestrator. The orchestrator
captures new leads from the user and routes back to Phase 2 for another
discover-converge round. Don't add the `## Decision: Crystallize` marker
back -- the orchestrator will re-add it when the user is ready again.

### 4.11 Write Crystallize Decision

Write `wip/explore_<topic>_crystallize.md`:

```markdown
# Crystallize Decision: <topic>

## Chosen Type
<terminal outcome name, or the entry point: file an issue | /charter | /scope | /execute>

## Candidacy
- /execute: <candidate, PLAN at <path> with execution_mode <mode> | not a candidate, reason>
- Competitive analysis: <candidate (private) | not a candidate (public)>

## Rationale
<Why this outcome fits best. Reference specific findings and signals.>

## Stage 1 Evidence
### Signals Present
- <signal>: <evidence from findings>

### Anti-Signals Checked
- <anti-signal>: <not present / present>

### Ranking
- <category>: <score> <(demoted)>

## Stage 2 Evidence
<Omit this section when stage 2 didn't run; state why it ran when the trigger was
the within-one-point margin rather than a chain outcome.>

### Signals Present
- <signal>: <evidence from findings>

### Anti-Signals Checked
- <anti-signal>: <not present / present>

### Ranking
- <entry point>: <score> <(demoted)>

## Tiebreakers Applied
- <rule>: <which branch and why>

## Alternatives Considered
- **<outcome>**: <why it ranked lower>

## Deferred Type (if applicable)
- **Prototype**: <why it was noted, what alternative was chosen>
```

Commit: `docs(explore): crystallize outcome for <topic>`

## Quality Checklist

Before proceeding:
- [ ] Crystallize framework loaded from the full reference file
- [ ] Both candidacy preconditions evaluated before any scoring
- [ ] Accumulated findings read (not just the latest round)
- [ ] All candidate stage-1 categories scored with specific evidence
- [ ] Stage 2 run when stage 1 returned a chain or came within one point
- [ ] No arm that failed its precondition appears in the presented options

## Artifact State

After this phase:
- Scope file at `wip/explore_<topic>_scope.md`
- Research files from all rounds at `wip/research/explore_<topic>_r*_lead-*.md`
- Findings file at `wip/explore_<topic>_findings.md` (with `## Decision: Crystallize` marker)
- Crystallize decision at `wip/explore_<topic>_crystallize.md`

## Next Phase

Proceed to Phase 5: Produce (`phase-5-produce.md`)
