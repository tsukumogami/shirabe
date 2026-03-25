# Phase 4: Crystallize

Evaluate accumulated findings to recommend an artifact type.

## Goal

Score the exploration's findings against the crystallize decision framework,
rank artifact types by fit, and present the user with a recommendation. The
user confirms the type, rejects all options (loop back), or picks an alternative.

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
- **Crystallize framework**: loaded in Step 4.1

## Steps

### 4.1 Load the Decision Framework

Read the full crystallize framework:
`../quality/crystallize-framework.md`

This file contains signal/anti-signal tables for each artifact type, the
evaluation procedure, tiebreaker rules, disambiguation rules, and handling
for deferred types. Don't rely on the summary in SKILL.md -- load the full
reference.

### 4.2 Read Accumulated Findings

Read `wip/explore_<topic>_findings.md`. Focus on:

- **Accumulated Understanding** -- the synthesized view of everything learned
- **User Focus** sections from each round -- what the user said matters most
- **Tensions** and **Gaps** -- these often indicate what type of artifact
  would address the remaining uncertainty
- **Decisions** sections from each round -- what was already decided

Also read `wip/explore_<topic>_decisions.md` if it exists. The decisions file
tracks scope narrowing, option elimination, and priority choices made during
convergence rounds. These decisions directly inform artifact type selection --
if decisions were made, they need to live somewhere permanent, which weighs
against "No artifact."

If the decisions file doesn't exist, that's fine -- it means no explicit
decisions were captured (common in first rounds or purely informational
explorations).

If the Accumulated Understanding section is thin, also read the individual
research files from the latest round for detail.

### 4.3 Score Each Type

**Before scoring, remember:** artifacts capture decisions already made, not just
decisions yet to be made. `wip/` is cleaned before every PR merges. If exploration
produced architectural choices, dependency selections, or design rationale, those must
live in a permanent document. The question is not "is anything still undecided?" —
it's "did we decide something a future contributor needs to know?"

For each of the five supported types (PRD, Design Doc, Plan, No Artifact, Rejection Record):

1. Walk through the signal table. For each signal, check whether the findings
   provide evidence for or against it. Be specific -- cite actual findings,
   not vague impressions.
2. Walk through the anti-signal table the same way.
3. Score = count of signals present minus count of anti-signals present.

Also check the deferred types (Spike Report, Decision Record, Competitive
Analysis, Prototype, Roadmap). If a deferred type scores highest, handle it
per the framework's Deferred Types section before continuing.

### 4.4 Rank and Demote

Rank supported types by score, highest first.

Apply the demotion rule: any type with one or more anti-signals present drops
below all types without anti-signals, regardless of raw score. A type scoring
3 with 1 anti-signal ranks below a type scoring 1 with 0 anti-signals.

### 4.5 Apply Tiebreakers

If the top two types are tied or within 1 point after demotion, use the
tiebreaker rules from the framework:

- **PRD vs Design Doc**: Did requirements emerge during exploration (identified by
  /explore), or were they given as input before exploration started? Identified ->
  PRD. Given -> Design Doc.
- **PRD vs No artifact**: Can one person act on this without a written contract?
  Yes -> No artifact. No -> PRD.
- **Design Doc vs Plan**: Does a PRD or design doc already exist for this topic?
  Yes -> Plan. No -> Design Doc.

### 4.6 Check for Insufficient Signal

If no supported type scores above 0 after demotion, the findings are too vague.

1. Tell the user the findings don't clearly point to any artifact type.
2. Identify which signals are missing and what questions would surface them.
3. Recommend another discover-converge round with specific leads targeting
   the gaps.
4. Return control to the orchestrator, which routes back to Phase 2 with
   new leads.

Don't force a choice when the evidence isn't there.

### 4.7 Present Recommendation

Use AskUserQuestion to present the evaluation results. Format the options
so the user can make an informed choice.

**Recommended type** -- the top-scoring type, marked "(Recommended)". Explain
which signals matched, referencing actual findings. Don't use generic signal
descriptions -- ground them in what the exploration discovered.

**Alternative types** -- other types that partially fit. For each, note which
signals matched and which anti-signals or missing signals caused the lower
ranking.

**Deferred types** (if any scored well) -- note separately with the suggested
alternative from the framework.

**"None of these"** -- always include as the last option. If selected, the
user goes back to explore further.

Example AskUserQuestion:

> Based on your exploration findings, here's how the artifact types match:
>
> 1. **Design Doc (Recommended)** -- Your exploration established clear
>    requirements (recipe format and CLI flags are well-defined) but surfaced
>    three competing approaches for the version resolver. The core open question
>    is architectural.
> 2. **PRD** -- Partially fits because stakeholder alignment is needed on
>    the plugin API. But the "what" is mostly clear; the "how" is the gap.
> 3. **No artifact** -- Ranked lower because three implementation approaches
>    need comparison before committing.
> 4. **None of these** -- Go back and explore further.

### 4.8 Route Based on User Choice

**Type selected:** Proceed to Step 4.9 (write decision), then Phase 5.

**"None of these":** Return control to the orchestrator. The orchestrator
captures new leads from the user and routes back to Phase 2 for another
discover-converge round. Don't add the `## Decision: Crystallize` marker
back -- the orchestrator will re-add it when the user is ready again.

### 4.9 Write Crystallize Decision

Write `wip/explore_<topic>_crystallize.md`:

```markdown
# Crystallize Decision: <topic>

## Chosen Type
<type name>

## Rationale
<Why this type fits best. Reference specific findings and signals.>

## Signal Evidence
### Signals Present
- <signal>: <evidence from findings>

### Anti-Signals Checked
- <anti-signal>: <not present / present but outweighed>

## Alternatives Considered
- **<type>**: <why it ranked lower>

## Deferred Types (if applicable)
- **<type>**: <why it was noted, what alternative was chosen>
```

Commit: `docs(explore): crystallize artifact type for <topic>`

## Quality Checklist

Before proceeding:
- [ ] Crystallize framework loaded from the full reference file
- [ ] Accumulated findings read (not just the latest round)
- [ ] All five supported types scored with specific evidence

## Artifact State

After this phase:
- Scope file at `wip/explore_<topic>_scope.md`
- Research files from all rounds at `wip/research/explore_<topic>_r*_lead-*.md`
- Findings file at `wip/explore_<topic>_findings.md` (with `## Decision: Crystallize` marker)
- Crystallize decision at `wip/explore_<topic>_crystallize.md`

## Next Phase

Proceed to Phase 5: Produce (`phase-5-produce.md`)
