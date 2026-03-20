# Phase 0: Setup

Establish the working branch, resolve context, and triage the issue if needed.

## Goal

Get onto a topic branch with visibility and scope resolved, ready for scoping.
If starting from a `needs-triage` issue, assess whether exploration is the right
path before proceeding.

**Label vocabulary reference:** `references/label-reference.md`

## Resume Check

If already on a `docs/<topic>` branch and `wip/explore_<topic>_scope.md` exists,
skip to Phase 1. If the scope file doesn't exist but you're on the topic branch,
proceed from Step 0.2.

## Steps

### 0.1 Branch Setup

If already on a `docs/<topic>` branch, skip to Step 0.2.

Otherwise:
- Derive topic from `$ARGUMENTS` (issue title or provided topic string)
- Convert to kebab-case: `docs/<topic>`
- Create from latest main and switch to it
- Confirm you're on the correct branch

### 0.2 Context Resolution

Resolve visibility and scope per the Context Resolution section in SKILL.md.
Log the effective context before continuing:

```
Exploring with [Private|Public] visibility in [Strategic|Tactical] scope...
```

### 0.3 Issue Entry Point

**If starting from an issue with `needs-triage` label:** proceed to Step 0.4.

**If starting from an issue with `needs-design` label:** Gather context from
upstream strategic issues and design docs by reading any linked issues, related
design docs referenced in the issue body, and upstream artifacts noted in the
codebase. Then proceed to Phase 1.

**If starting from a plain topic (no issue):** proceed directly to Phase 1.

### 0.4 Triage Stage 1: Investigation vs. Actionable

Run a two-stage triage to determine what the issue actually needs. Stage 1 determines
whether the issue needs upstream artifact work, breakdown, or is ready.

Launch 3 agents in parallel, each arguing for one category:

**Agent 1 -- needs investigation:**
Argue that this issue requires upstream artifact work before it can be implemented.
Look for: ambiguity in requirements or approach, multiple possible solutions,
technical risk, feasibility questions, cross-cutting concerns, unclear scope
boundaries.

**Agent 2 -- needs breakdown:**
Argue that this issue is well-understood but too large for one session. Look for:
clear approach but multiple independent pieces, no technical uncertainty, scope
that implies several PRs or distinct work items.

**Agent 3 -- ready:**
Argue that this issue can be implemented directly. Look for: clear requirements,
single deliverable, low risk, straightforward approach, small scope (one person,
one PR).

Each agent writes a 3-5 line assessment to chat (no files needed). Include the
issue number and a confidence level (low/medium/high).

#### Stage 1 Agent Prompt Template

```
You are assessing a placeholder issue for triage from the perspective of a [ROLE].

Issue: [TITLE]
Body: [BODY]
Upstream context: [CONTEXT FROM STEP 2]

Evaluate which category fits best:

1. **Needs Investigation**: Has unknowns that require upstream artifact work --
   requirements unclear, approach undecided, feasibility unknown, or architectural
   choice needed
2. **Needs Breakdown**: Well-specified but too large for one session, multiple
   independent chunks, no design decisions needed
3. **Ready**: Atomic task, clear acceptance criteria, single session of work,
   no design decisions needed

Provide:
- Your recommended category (investigation/breakdown/ready)
- Brief rationale (2-3 sentences)
- Confidence level (high/medium/low)
```

#### Stage 1 Synthesis

After agents respond, synthesize:
1. If unanimous: that category is the result
2. If split: the majority category is the result, note dissent

If the result is **needs investigation**, proceed to Step 0.5.

If the result is **needs breakdown** or **ready**, present to the user using
AskUserQuestion:
- **Break down** -- create sub-issues, then use /work-on for each
- **Implement directly** -- skip exploration; use /work-on

Route based on the user's choice:
- **Break down:** Create sub-issues from the original. Stop and suggest the user
  run `/work-on` on individual sub-issues.
- **Implement directly:** Remove the `needs-triage` label. Stop and suggest the
  user run `/work-on <issue-number>`.

### 0.5 Triage Stage 2: Investigation Type

Only reached when Stage 1 determined "needs investigation." Launch 3 agents in
parallel, each arguing for a specific artifact type:

**Agent 1 -- needs-prd:**
Argue that requirements are the primary gap. Look for: unclear or contested
requirements, multiple stakeholders with different expectations, "what to build"
is the open question.

**Agent 2 -- needs-design:**
Argue that the approach is the primary gap. Look for: requirements are clear but
the technical approach isn't, multiple valid architectures, integration risk, "how
to build" is the open question.

**Agent 3 -- needs-spike / needs-decision:**
Argue that either a feasibility question or a single architectural choice is the
primary gap. Look for: "can we build this?" uncertainty (spike), or a clear choice
between 2-3 known options that just needs a decision (decision record). State which
one fits and why.

Each agent writes a 3-5 line assessment to chat (no files needed).

#### Stage 2 Agent Prompt Template

```
You are assessing what type of upstream artifact work an issue needs.

Issue: [TITLE]
Body: [BODY]
Upstream context: [CONTEXT FROM STEP 2]
Stage 1 result: The jury agreed this issue needs investigation before implementation.

Evaluate which investigation type fits best:

1. **needs-prd**: Requirements unclear or contested. "What to build" is the open
   question. Multiple stakeholders may disagree on scope or behavior.
2. **needs-design**: What to build is clear, how to build it is not. Technical
   approach needs exploration, multiple valid architectures exist.
3. **needs-spike**: Feasibility is unknown. "Can we build this?" needs answering
   before committing to an approach.
4. **needs-decision**: A single architectural choice between known options.
   The options are identified but the trade-offs haven't been evaluated.

Primary gap heuristic: when both requirements AND approach are unclear, route
to the earlier-stage artifact (needs-prd before needs-design). Requirements
clarity is a prerequisite for meaningful design work.

Provide:
- Your recommended type (needs-prd/needs-design/needs-spike/needs-decision)
- Brief rationale (2-3 sentences)
- Confidence level (high/medium/low)
```

#### Stage 2 Synthesis

After agents respond, synthesize:
1. If unanimous: that type is the recommendation
2. If split: the majority type is the recommendation, note dissent
3. If three-way split: apply the primary gap heuristic -- when both requirements
   AND approach are unclear, prefer the earlier-stage artifact (needs-prd before
   needs-design, needs-design before needs-spike)

Present the assessments side-by-side and recommend the strongest one. Ask the user
to confirm via AskUserQuestion:

> Based on the assessments, this issue looks like it **[needs a PRD / needs design /
> needs a spike / needs a decision record]**. How would you like to proceed?
>
> 1. **Explore** -- continue with /explore to produce the artifact
> 2. **Different type** -- you see a different need (user can override the recommendation)
> 3. **Implement directly** -- skip investigation; use /work-on

Route based on the user's choice:

- **Explore (or confirmed type):** Update the issue label (remove `needs-triage`,
  add the chosen `needs-*` label). If the chosen type is `needs-design`, gather
  upstream context from linked issues and existing design docs before proceeding
  to Phase 1. For other types, proceed to Phase 1 as well -- /explore will
  crystallize to the appropriate artifact type.
- **Different type:** Apply the user's chosen label instead and proceed as above.
- **Implement directly:** Remove the `needs-triage` label. Stop and suggest the
  user run `/work-on <issue-number>`.

## Quality Checklist

Before proceeding:
- [ ] On branch `docs/<topic>`
- [ ] Visibility and scope resolved and logged
- [ ] If from needs-triage: two-stage triage complete, user confirmed routing

## Artifact State

After this phase:
- On the `docs/<topic>` branch
- Context resolved (visibility + scope)
- If from an issue: triage handled, upstream context gathered
- No wip/ files yet

## Next Phase

Proceed to Phase 1: Scope (`phase-1-scope.md`)
